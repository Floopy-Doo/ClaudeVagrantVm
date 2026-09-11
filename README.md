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
   - the guest timezone is set to the host's timezone (needs PowerShell 7 `pwsh` on the host). Override with `$env:TZ="Europe/Helsinki"; vagrant up`; re-apply after a change with `vagrant provision`
6. host: configure ssh alias for vm
  - vagrant ssh-config > vagrant-ssh
  - append to ~/.ssh/config
  - change config alias to vagrant_vm 
7. host: ssh vagrant_vm
8. guest: clone git repo from real remote ( in folder  /coding)
9. guest: remove real remote from git repo
10. host: setup git upstream to vagrant
    - in repo: git remote add vagrant_claude vagrant_claude:/home/vagrant/coding/repo

### Start / stop / connect

`Start-ClaudeVm.ps1` and `Stop-ClaudeVm.ps1` wrap `vagrant up` / `vagrant halt` and point
Vagrant at this repo themselves (`VAGRANT_CWD`), so they work from any directory.
Both need an **elevated** PowerShell 7 session, or a user in *Hyper-V Administrators* (see the
tip below) — the Hyper-V provider does.
`Connect-ClaudeVm.ps1` just sshes to the `vagrant_vm` alias and needs no elevation.

Add to your PowerShell profile (`notepad $PROFILE`):

```powershell
Set-Alias Vagrant-ClaudeVm-Up   D:\Dev\ClaudeVM\Start-ClaudeVm.ps1
Set-Alias Vagrant-ClaudeVm-Down D:\Dev\ClaudeVM\Stop-ClaudeVm.ps1
Set-Alias Vagrant-ClaudeVm-SSH  D:\Dev\ClaudeVM\Connect-ClaudeVm.ps1
```

Then:

```powershell
Vagrant-ClaudeVm-Up                # start, skipping provisioners
Vagrant-ClaudeVm-Up -WaitForSsh    # start and block until `ssh vagrant_vm` answers
Vagrant-ClaudeVm-Up -Provision     # start and re-run the provisioners
Vagrant-ClaudeVm-Down              # graceful shutdown
Vagrant-ClaudeVm-Down -Force       # power off
Vagrant-ClaudeVm-SSH               # interactive shell on the guest
Vagrant-ClaudeVm-SSH uptime        # run a single command on the guest
```

> **Tip — skip the elevated shell.** Members of the local *Hyper-V Administrators* group may
> manage VMs without elevation. Run once in an elevated PowerShell, then sign out and back in
> (group membership is only picked up at logon):
>
> ```powershell
> Add-LocalGroupMember -Group 'Hyper-V Administrators' -Member "$env:USERDOMAIN\$env:USERNAME"
> ```
>
> Afterwards `Vagrant-ClaudeVm-Up` / `-Down` work from a normal shell.
