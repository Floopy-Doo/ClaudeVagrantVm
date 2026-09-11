#Requires -Version 7.0
<#
.SYNOPSIS
    Opens an SSH session on the Vagrant guest 'ClaudeVm'. Meant to be aliased, so it
    can be called from any directory.
.DESCRIPTION
    Connects through the SSH config alias 'vagrant_vm' (see the one-time setup in the
    README), not through `vagrant ssh` — that is faster and needs no elevated session.
    Anything after the parameters is run as a command on the guest instead of opening
    an interactive shell.
.PARAMETER SshHost
    SSH config alias to connect to. Default 'vagrant_vm' (env CLAUDE_VM_SSH_HOST).
.PARAMETER Command
    Command to run on the guest. Omit for an interactive shell.
.EXAMPLE
    Set-Alias Vagrant-ClaudeVm-SSH D:\Dev\ClaudeVM\Connect-ClaudeVm.ps1   # then: Vagrant-ClaudeVm-SSH
.EXAMPLE
    Vagrant-ClaudeVm-SSH uptime
#>
[CmdletBinding()]
param(
    [string]$SshHost = ($env:CLAUDE_VM_SSH_HOST ?? 'vagrant_vm'),
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$Command
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) { throw 'ssh is not on PATH' }

# No BatchMode here: an interactive session may legitimately need to prompt.
$sshArgs = @('-o', 'ConnectTimeout=15', $SshHost) + $Command

& ssh @sshArgs
exit $LASTEXITCODE
