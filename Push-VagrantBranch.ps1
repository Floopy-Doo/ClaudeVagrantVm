#Requires -Version 7.0
<#
Force-push a local branch to the vagrant VM — an isolated working environment
(a non-bare repo) where the branch may currently be checked out, possibly in a
linked git worktree.

    .\Push-VagrantBranch.ps1              # current branch
    .\Push-VagrantBranch.ps1 feature/x    # named branch

Unlike `Jms-Push-Vagrant` (which only refreshes main via a fixed `temp` parking
branch), this detaches whichever worktree — main or linked — currently holds the
branch, force-pushes, then re-checks the branch out there, clobbering the guest
working tree.

Configuration mirrors the bash `git push-claude` contract:
    git config claude.remote    git remote / ssh host   (default: vagrant_vm)
    git config claude.dir       repo path on the guest  (default: ~/coding/JMS5)
Run from inside the local clone you want to push from.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Branch,
    [string]$Remote,
    [string]$Dir,
    [string]$SshHost
)

$ErrorActionPreference = 'Stop'
# Native exit codes are checked explicitly below; don't let PS turn stderr into a terminating error.
$PSNativeCommandUseErrorActionPreference = $false

$SshOpts = '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15'

function Invoke-Native([string]$FilePath, [string[]]$ArgumentList) {
    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) { throw "$FilePath $($ArgumentList -join ' ') failed ($LASTEXITCODE)" }
}

function ConvertTo-ShellQuoted([string]$Value) {
    "'" + $Value.Replace("'", "'\''") + "'"
}

# Ships the bash body over ssh base64-encoded rather than piping a here-string into
# `bash -s`: PowerShell writes CRLF line endings to a native stdin pipe, which bash
# chokes on. Returns stdout with trailing newline trimmed; stderr passes through.
function Invoke-RemoteBash([string]$TargetHost, [string]$Script, [string[]]$Arguments) {
    $normalized = $Script -replace "`r`n", "`n"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($normalized))
    $quoted = ($Arguments | ForEach-Object { ConvertTo-ShellQuoted $_ }) -join ' '
    $output = & ssh @SshOpts $TargetHost "echo $encoded | base64 -d | bash -s -- $quoted"
    if ($LASTEXITCODE -ne 0) { throw "remote command on $TargetHost failed ($LASTEXITCODE)" }
    ($output -join "`n").TrimEnd("`n")
}

if (-not $Branch) {
    $Branch = (& git symbolic-ref --quiet --short HEAD)
    if (-not $Branch) { throw 'detached HEAD, pass a branch name' }
}

if (-not $Remote) { $Remote = (& git config --default vagrant_vm claude.remote) }
if (-not $Dir) { $Dir = (& git config --default '~/coding/JMS5' claude.dir) }

if (-not $SshHost) {
    # The remote name and the ssh alias usually coincide, but not always — prefer the
    # host out of the configured URL (user@host:path or ssh://user@host/path).
    $url = (& git remote get-url $Remote 2>$null)
    if ($LASTEXITCODE -eq 0 -and $url) {
        $stripped = $url -replace '^ssh://', ''
        $SshHost = ($stripped -split '[:/]', 2)[0] -replace '^.*@', ''
    }
    if (-not $SshHost) { $SshHost = $Remote }
}

Write-Host "==> pushing '$Branch' to $Remote ($SshHost : $Dir)"

# 1. Find the worktree (main or linked) holding the branch on the guest and detach it
#    so the ref can be force-updated. Prints the worktree path, empty if none.
$detachScript = @'
set -eu
cd "${1/#\~/$HOME}"
branch="$2"
wt=$(git worktree list --porcelain | awk -v b="refs/heads/$branch" '
  /^worktree /{ path = substr($0, 10) }
  /^branch /  { if (substr($0, 8) == b) { print path; exit } }')
if [ -n "$wt" ]; then
  cd "$wt"
  git switch --detach >&2
fi
printf '%s' "$wt"
'@

$worktree = Invoke-RemoteBash $SshHost $detachScript @($Dir, $Branch)
if ($worktree) { Write-Host "==> detached guest worktree $worktree" }

$restoreScript = @'
set -eu
cd "$1"
git switch --force "$2"
'@

try {
    # 2. Push the branch as-is — nothing has it checked out now.
    Invoke-Native git @('push', '--force', $Remote, "${Branch}:${Branch}")
}
finally {
    # 3. Re-checkout the branch in that same worktree, clobbering its working tree.
    #    In `finally` so a failed push never strands the guest in detached HEAD.
    if ($worktree) {
        Invoke-RemoteBash $SshHost $restoreScript @($worktree, $Branch) | Out-Null
        Write-Host "==> restored '$Branch' in $worktree"
    }
}

Write-Host "==> done"
