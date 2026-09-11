#Requires -Version 7.0
<#
.SYNOPSIS
    Stops the Vagrant/Hyper-V guest 'ClaudeVm'. Meant to be aliased, so it can be
    called from any directory.
.DESCRIPTION
    Runs `vagrant halt` against the Vagrantfile next to this script (via VAGRANT_CWD),
    independent of the current working directory. A guest that is already off is a no-op.
    Needs permission to manage Hyper-V (elevated session, or 'Hyper-V Administrators' — see README).
.PARAMETER Force
    Power off instead of shutting the guest down cleanly (`vagrant halt --force`).
.EXAMPLE
    Set-Alias Vagrant-ClaudeVm-Down D:\Dev\ClaudeVM\Stop-ClaudeVm.ps1   # then: Vagrant-ClaudeVm-Down
#>
[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$VagrantDir = $PSScriptRoot
if (-not (Test-Path (Join-Path $VagrantDir 'Vagrantfile'))) { throw "no Vagrantfile in $VagrantDir" }
if (-not (Get-Command vagrant -ErrorAction SilentlyContinue)) { throw 'vagrant is not on PATH' }

$env:VAGRANT_CWD = $VagrantDir
$env:VAGRANT_DEFAULT_PROVIDER = 'hyperv'

$haltArgs = @('halt') + $(if ($Force) { '--force' } else { @() })

Write-Host "==> vagrant $haltArgs  (cwd $VagrantDir)"
& vagrant @haltArgs
if ($LASTEXITCODE -ne 0) { throw "vagrant halt failed ($LASTEXITCODE)" }
