Setup a Hyber-V vm for usage of agentic coding with Claude Code / Codex and dotnet.
Intended for use on Windows devices.

### Peparations
the repo contains a claude.md and a settings.json. use your own claude config and replace existing.

### One time setup
1. host: install vagrant
2. Host: Powershell: `New-VMSwitch -Name "VagrantNatSwitch" -SwitchType Internal`
3. Host: Powershell: `New-NetIPAddress -IPAddress 192.168.50.1 -PrefixLength 24 -InterfaceAlias "vEthernet (VagrantNatSwitch)"`
4. Host: Powershell: `New-NetNat -Name "VagrantNatSwitch" -InternalIPInterfaceAddressPrefix 192.168.50.0/24`
5. host: vagrant up
6. host: configure ssh alias for vm
  - vagrant ssh-config > vagrant-ssh
  - append to ~/.ssh/config
  - change config alias to vagrant_vm 
7. host: ssh vagrant_vm
8. guest: clone git repo from real remote ( in folder  /coding)
9. guest: remove real remote from git repo
10. host: setup git upstream to vagrant
    - in repo: git remote add vagrant_claude vagrant_claude:/home/vagrant/coding/repo
