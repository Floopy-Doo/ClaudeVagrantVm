#Requires -Version 7.0
<#
.SYNOPSIS
    Starts the Vagrant/Hyper-V guest 'ClaudeVm'. Meant to be aliased, so it can be
    called from any directory.
.DESCRIPTION
    Runs `vagrant up` against the Vagrantfile next to this script (via VAGRANT_CWD),
    independent of the current working directory. Provisioners are skipped by default
    so a routine start never re-runs apt/installers; pass -Provision to run them.
    Needs permission to manage Hyper-V (elevated session, or 'Hyper-V Administrators' — see README).
.PARAMETER Provision
    Run the provisioners (`vagrant up --provision`).
.PARAMETER WaitForSsh
    Block until the guest answers on the SSH alias (default 'vagrant_vm'), max -TimeoutSeconds.
.PARAMETER SshHost
    SSH config alias used by -WaitForSsh. Default 'vagrant_vm' (env CLAUDE_VM_SSH_HOST).
.PARAMETER TimeoutSeconds
    Upper bound for -WaitForSsh. Default 180.
.EXAMPLE
    Set-Alias Vagrant-ClaudeVm-Up D:\Dev\ClaudeVM\Start-ClaudeVm.ps1   # then: Vagrant-ClaudeVm-Up -WaitForSsh
#>
[CmdletBinding()]
param(
    [switch]$Provision,
    [switch]$WaitForSsh,
    [string]$SshHost = ($env:CLAUDE_VM_SSH_HOST ?? 'vagrant_vm'),
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$VagrantDir = $PSScriptRoot
if (-not (Test-Path (Join-Path $VagrantDir 'Vagrantfile'))) { throw "no Vagrantfile in $VagrantDir" }
if (-not (Get-Command vagrant -ErrorAction SilentlyContinue)) { throw 'vagrant is not on PATH' }

# Set for the child process only, so an interactive shell keeps its own settings.
$env:VAGRANT_CWD = $VagrantDir
$env:VAGRANT_DEFAULT_PROVIDER = 'hyperv'

# --no-provision by default: the provisioners install packages and reboot the guest,
# which is not what a plain start should do.
$upArgs = @('up', '--provider', 'hyperv') + $(if ($Provision) { '--provision' } else { '--no-provision' })

Write-Host "==> vagrant $upArgs  (cwd $VagrantDir)"
& vagrant @upArgs
if ($LASTEXITCODE -ne 0) { throw "vagrant up failed ($LASTEXITCODE)" }

if ($WaitForSsh) {
    Write-Host "==> Waiting for ssh '$SshHost' (max ${TimeoutSeconds}s)"
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        & ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new $SshHost true 2>$null
        if ($LASTEXITCODE -eq 0) { Write-Host "==> '$SshHost' is up"; return }
        Start-Sleep -Seconds 5
    }
    throw "'$SshHost' did not answer within ${TimeoutSeconds}s"
}
