#Requires -Version 7.0
<#
.SYNOPSIS
    Backs up ~/.claude from the Vagrant guest onto a rolling git branch.
    Run on the host from inside the Vagrantfile repo. Commits locally, never pushes.
.DESCRIPTION
    The VM must already be running and reachable through the SSH config alias 'vagrant_vm'
    (see README). The script does not start the VM; it fails if the connection is refused.
    Each run creates a git worktree for the backup branch at '.worktree/<branch>' in the repo
    (created from 'main' on first use, rebased onto current 'main' afterwards; a rebase that
    does not complete aborts the run), copies the staged backup into it, commits it as
    'backup-claude/', and removes the worktree again.
.NOTES
    Needs rsync in the guest and OpenSSH ssh/scp on the host. Excludes are applied on the guest.
    Env overrides: CLAUDE_BACKUP_BRANCH (claude-vm-backup), CLAUDE_BACKUP_BASE (main),
    CLAUDE_BACKUP_SSH_HOST (vagrant_vm), CLAUDE_BACKUP_GUEST_HOME (/home/vagrant),
    CLAUDE_BACKUP_GUEST_DIR (.claude), CLAUDE_BACKUP_DIR (backup-claude)
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Invoke-Native([string]$FilePath, [string[]]$ArgumentList, [int[]]$OkExit = 0) {
    & $FilePath @ArgumentList
    if ($LASTEXITCODE -notin $OkExit) { throw "$FilePath $ArgumentList failed ($LASTEXITCODE)" }
}

# Must be called with the repo root as the current location.
function Remove-Worktree([string]$Path) {
    if (-not (Test-Path $Path)) { return }
    & git worktree remove --force $Path 2>$null | Out-Null
    if (Test-Path $Path) {
        Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
        & git worktree prune
    }
    if (Test-Path $Path) { Write-Warning "worktree directory left behind: $Path" }
}

$Branch    = $env:CLAUDE_BACKUP_BRANCH     ?? 'claude-vm-backup'
$Base      = $env:CLAUDE_BACKUP_BASE       ?? 'main'
$SshHost   = $env:CLAUDE_BACKUP_SSH_HOST   ?? 'vagrant_vm'
$GuestHome = $env:CLAUDE_BACKUP_GUEST_HOME ?? '/home/vagrant'
$GuestDir  = $env:CLAUDE_BACKUP_GUEST_DIR  ?? '.claude'
$BackupDir = $env:CLAUDE_BACKUP_DIR        ?? 'backup-claude'
$Stage     = '/tmp/claude-backup-stage'
$Excludes  = '.credentials.json', '*.jsonl', '.git', 'shell-snapshots', 'ide', 'debug',
             'paste-cache', 'file-history', 'statsig', 'telemetry', 'todos', 'plugins'
# BatchMode: never prompt for passwords/host keys; fail instead of hanging.
$SshOpts   = '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15'

$RepoRoot = & git rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0) { throw 'not inside a git repository' }
$RepoRoot = Convert-Path $RepoRoot
if (-not (Test-Path "$RepoRoot/Vagrantfile")) { throw "no Vagrantfile in $RepoRoot" }
# Fixed path inside the repo, under the gitignored '.worktree/'. Deterministic so a run that
# was killed mid-way can be cleaned up on the next run instead of leaking a random temp dir.
$WorktreeRoot = Join-Path $RepoRoot '.worktree'
$WorktreeDir  = Join-Path $WorktreeRoot $Branch

Push-Location $RepoRoot
try {
    Write-Host "==> Staging $GuestDir on guest via ssh '$SshHost'"
    $exclArgs = ($Excludes | ForEach-Object { "--exclude='$_'" }) -join ' '
    $stageCmd = "set -eu; command -v rsync >/dev/null || { echo 'rsync missing in guest' >&2; exit 3; }; " +
                "rm -rf '$Stage' && mkdir -p '$Stage' && rsync -aL $exclArgs '$GuestHome/$GuestDir/' '$Stage/$BackupDir/'"
    # rsync exit 24 = files vanished during transfer, expected while Claude Code is running
    Invoke-Native ssh ($SshOpts + @($SshHost, $stageCmd)) -OkExit 0, 24

    & git worktree prune
    if ((& git rev-parse --abbrev-ref HEAD) -eq $Branch) {
        throw "branch '$Branch' is checked out in $RepoRoot; run 'git switch $Base' there first"
    }
    & git show-ref --verify --quiet "refs/heads/$Base"
    if ($LASTEXITCODE -ne 0) { throw "base branch '$Base' does not exist" }
    & git show-ref --verify --quiet "refs/heads/$Branch"
    $branchExists = $LASTEXITCODE -eq 0
    # longpaths: Claude project dirs nest deep enough to exceed Windows' 260-char limit; the
    # checkout in 'worktree add' needs it too, or long files are silently missing afterwards.
    $gitCfg = '-c', 'core.autocrlf=false', '-c', 'core.longpaths=true'
    $git    = @('-C', $WorktreeDir) + $gitCfg

    $addArgs = if ($branchExists) { $WorktreeDir, $Branch } else { '-b', $Branch, $WorktreeDir, $Base }
    Write-Host "==> Creating worktree for '$Branch' at $WorktreeDir"
    Remove-Worktree $WorktreeDir
    New-Item -ItemType Directory -Force -Path $WorktreeRoot | Out-Null
    Invoke-Native git ($gitCfg + @('worktree', 'add', '-q') + $addArgs)

    if ($branchExists) {
        Write-Host "==> Rebasing '$Branch' onto '$Base'"
        # autoStash off: a dirty fresh worktree signals a broken checkout and must fail, not be hidden.
        & git @git -c rebase.autoStash=false rebase -q $Base
        if ($LASTEXITCODE -ne 0) {
            & git @git rebase --abort 2>$null | Out-Null
            throw "rebase of '$Branch' onto '$Base' did not complete; resolve manually"
        }
    }

    # Drop the previous snapshot from index + worktree so deletions on the guest are reflected.
    # '.claude' is the pre-rename location; drop it once, then this entry can go away.
    Invoke-Native git ($git + @('rm', '-r', '-q', '-f', '--ignore-unmatch', '--', $BackupDir, '.claude'))

    Write-Host '==> Copying to worktree'
    # scp treats 'D:/...' as host:path, so copy into '.' from inside the worktree.
    Push-Location $WorktreeDir
    try { Invoke-Native scp ($SshOpts + @('-q', '-r', "${SshHost}:$Stage/$BackupDir", '.')) }
    finally { Pop-Location }
    if (-not (Get-ChildItem "$WorktreeDir/$BackupDir" -Force)) { throw 'copied directory is empty' }

    Invoke-Native git ($git + @('add', '-A', '-f', '--', $BackupDir))
    & git @git diff --cached --quiet
    if ($LASTEXITCODE -eq 0) { Write-Host '==> No changes, nothing to commit'; return }

    $stamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    Invoke-Native git ($git + @('commit', '-q', '-m', "Backup $GuestDir from VM @ $stamp"))
    Write-Host "==> Committed to '$Branch' (local only)"
} finally {
    Remove-Worktree $WorktreeDir
    & ssh @SshOpts $SshHost "rm -rf '$Stage'" 2>$null | Out-Null
    Pop-Location
}
