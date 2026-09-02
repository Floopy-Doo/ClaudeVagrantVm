require "yaml"
require "fileutils"

vm_name = "ClaudeVm"

CHOICES_FILE = File.join(File.dirname(__FILE__), ".vagrant", "install-choices.yml")

def ask?(question)
  print "#{question} [y/N]: "
  %w[y yes].include?($stdin.gets&.strip&.downcase)
end

def load_or_ask_choices
  # Already decided once → reuse, never ask again.
  return YAML.load_file(CHOICES_FILE) if File.exist?(CHOICES_FILE)

  # Only the provisioning commands should prompt; halt/destroy/ssh/status must not.
  defaults = {
    "claude" => false,
    "dotnet" => false,
    "codex" => false
  }

  provisioning = %w[up provision reload].include?(ARGV[0])
  return defaults unless provisioning

  choices = {
    "claude" => ask?("Install claude?"),
    "dotnet" => ask?("Install dotnet?"),
    "codex" => ask?("Install codex?")
  }

  FileUtils.mkdir_p(File.dirname(CHOICES_FILE))
  File.write(CHOICES_FILE, choices.to_yaml)

  choices
end

choices = load_or_ask_choices

Vagrant.configure("2") do |config|
  config.vm.box = "gusztavvargadr/ubuntu-desktop-2404-lts"

  # Pin the switch so `vagrant up` never stops to ask which one to attach to.
  config.vm.network "public_network", bridge: "VagrantNatSwitch"

  config.vm.synced_folder ".", "/vagrant", disabled: true

  # VagrantNatSwitch has no DHCP server, so the guest has no IPv4 address until
  # the netplan provisioner below has run and the box has rebooted. Vagrant
  # reaches it over IPv6 link-local until then, which is slow to discover.
  config.vm.boot_timeout = 600

  config.vm.provider "hyperv" do |hv|
    hv.vmname = vm_name
    hv.memory = 32768
    hv.cpus = 8
  end

  # Network setup in bridge mode.
  # The netplan config lives in netplan/99-static.yaml and is uploaded verbatim,
  # so no heredoc quoting/indentation can mangle it. The file provisioner runs as
  # the 'vagrant' user and cannot write to /etc, so it lands in /tmp and the shell
  # provisioner below installs it with root ownership and 0600.
  config.vm.provision "file",
    source: "network-config.yaml",
    destination: "/tmp/99-static.yaml"

  #
  # This provisioner must NOT run `netplan apply`: applying it reconfigures the
  # very interface Vagrant's SSH session is riding on, and the session dies
  # ("The SSH connection was unexpectedly closed by the remote end") before the
  # provisioner can report success. Instead the config is only validated here
  # and `reboot: true` lets Vagrant bring the box down and reconnect cleanly —
  # by then the guest holds 192.168.50.10 and Hyper-V reports it to Vagrant.
  config.vm.provision "shell", reboot: true, inline: <<~SHELL
    set -eu
    install -o root -g root -m 600 /tmp/99-static.yaml /etc/netplan/99-static.yaml
    rm -f /tmp/99-static.yaml

    # The box ships world-readable netplan files; netplan warns about each one
    # on every invocation. Tighten them so the output stays readable.
    chmod 600 /etc/netplan/*.yaml

    # cloud-init rewrites /etc/netplan/50-cloud-init.yaml on boot and would
    # otherwise re-assert DHCP on eth0 after the reboot below.
    mkdir -p /etc/cloud/cloud.cfg.d
    printf 'network: {config: disabled}\\n' \\
      > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg

    # Fails the provisioner on a malformed file, while the old network is still
    # up and the box is still reachable.
    netplan generate
  SHELL

  # Root-level setup
  config.vm.provision "shell", inline: <<~SHELL
    set -eu
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y docker.io nodejs npm git unzip bash-completion curl
    usermod -aG docker vagrant

    # rtk (Rust Token Killer) — installed system-wide, so it must run as root.
    # It lands in /usr/local/bin to be on the vagrant user's PATH both
    # interactively and when Claude invokes the hook.
    #
    # RTK_INSTALL_DIR belongs on the `sh` that runs the script, NOT on the
    # curl that fetches it: in `VAR=x curl ... | sh` the assignment applies
    # only to curl, so the installer would silently fall back to its default
    # of $HOME/.local/bin — /root/.local/bin here, which is off the PATH.
    curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh \\
      | RTK_INSTALL_DIR=/usr/local/bin sh
    test -x /usr/local/bin/rtk

    # Pre-create ~/.claude so the file provisioners below can upload into it.
    install -d -o vagrant -g vagrant -m 755 /home/vagrant/.claude
  SHELL

  # Per-user installs — runs as 'vagrant', so $HOME = /home/vagrant
  config.vm.provision "shell",
    privileged: false,
    env: {
      "INSTALL_CLAUDE" => choices["claude"].to_s,
      "INSTALL_DOTNET" => choices["dotnet"].to_s,
      "INSTALL_CODEX" => choices["codex"].to_s
    },
    inline: <<~SHELL
      set -eu

      if [ "$INSTALL_CLAUDE" = "true" ]; then
        curl -fsSL https://claude.ai/install.sh | bash
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
      fi

      if [ "$INSTALL_DOTNET" = "true" ]; then
        curl -fsSL https://dot.net/v1/dotnet-install.sh | bash
        echo 'export PATH="$HOME/.dotnet:$PATH"' >> ~/.bashrc
      fi

      if [ "$INSTALL_CODEX" = "true" ]; then
        curl -fsSL https://chatgpt.com/codex/install.sh | bash
      fi
    SHELL

  # Deploy the repo's Claude config into the VM, then wire rtk's hook into it.
  # Provisioners run in definition order, so these run after the shell block above.
  config.vm.provision "file", source: "settings.json", destination: "/home/vagrant/.claude/settings.json"
  config.vm.provision "file", source: "CLAUDE.md", destination: "/home/vagrant/.claude/CLAUDE.md"

  # Runs as the vagrant user (privileged: false). Merges rtk's PreToolUse hook
  # into the just-uploaded settings.json and sets up ~/.config/rtk/.
  config.vm.provision "shell", privileged: false, inline: <<~SHELL
    set -eu
    /usr/local/bin/rtk init -g --auto-patch
  SHELL
end