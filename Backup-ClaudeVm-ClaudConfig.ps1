#Requires -Version 7.0
<#
.SYNOPSIS
    Backs up ~/.claude from the Vagrant guest onto a rolling git branch (own worktree).
    Run on the host from inside the Vagrantfile repo. Commits locally, never pushes.
.NOTES
    Needs rsync in the guest and OpenSSH scp on the host. Excludes are applied on the guest.
    Env overrides: CLAUDE_BACKUP_BRANCH (claude-vm-backup), CLAUDE_BACKUP_MACHINE (''),
    CLAUDE_BACKUP_GUEST_HOME (/home/vagrant), CLAUDE_BACKUP_GUEST_DIR (.claude)
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Invoke-Native([string]$FilePath, [string[]]$ArgumentList, [int[]]$OkExit = 0) {
    & $FilePath @ArgumentList
    if ($LASTEXITCODE -notin $OkExit) { throw "$FilePath $ArgumentList failed ($LASTEXITCODE)" }
}

$Branch     = $env:CLAUDE_BACKUP_BRANCH     ?? 'claude-vm-backup'
$GuestHome  = $env:CLAUDE_BACKUP_GUEST_HOME ?? '/home/vagrant'
$GuestDir   = $env:CLAUDE_BACKUP_GUEST_DIR  ?? '.claude'
$MachineArg = @($env:CLAUDE_BACKUP_MACHINE | Where-Object { $_ })
$Stage      = '/tmp/claude-backup-stage'
$Excludes   = '.credentials.json', '*.jsonl', '.git', 'shell-snapshots', 'ide', 'debug',
              'paste-cache', 'file-history', 'statsig', 'telemetry', 'todos', 'plugins'

$RepoRoot = & git rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0) { throw 'not inside a git repository' }
$RepoRoot = Convert-Path $RepoRoot
if (-not (Test-Path "$RepoRoot/Vagrantfile")) { throw "no Vagrantfile in $RepoRoot" }
$WorktreeDir = "$RepoRoot-claude-backup-wt"

Push-Location $RepoRoot
try {
    if (-not ((& vagrant --machine-readable status @MachineArg 2>$null) -match ',state,running$')) {
        Write-Host '==> Starting VM'
        Invoke-Native vagrant (@('up') + $MachineArg)
    }

    $SshCfg = Join-Path ([IO.Path]::GetTempPath()) "claude-vm-ssh-$(New-Guid).cfg"
    try {
        Write-Host "==> Staging $GuestDir on guest"
        $exclArgs = ($Excludes | ForEach-Object { "--exclude='$_'" }) -join ' '
        $stageCmd = "set -eu; command -v rsync >/dev/null || { echo 'rsync missing in guest' >&2; exit 3; }; " +
                    "rm -rf '$Stage' && mkdir -p '$Stage' && rsync -aL $exclArgs '$GuestHome/$GuestDir/' '$Stage/$GuestDir/'"
        # rsync exit 24 = files vanished during transfer, expected while Claude Code is running
        Invoke-Native vagrant (@('ssh') + $MachineArg + @('-c', $stageCmd)) -OkExit 0, 24

        & vagrant ssh-config @MachineArg | Set-Content $SshCfg
        if ($LASTEXITCODE -ne 0) { throw "vagrant ssh-config failed ($LASTEXITCODE)" }
        $sshHost = (Select-String -Path $SshCfg -Pattern '^Host\s+(\S+)' | Select-Object -First 1).Matches[0].Groups[1].Value

        & git worktree prune
        if (-not (Test-Path "$WorktreeDir/.git")) {
            Write-Host "==> Creating worktree '$Branch' at $WorktreeDir"
            & git show-ref --verify --quiet "refs/heads/$Branch"
            $addArgs = if ($LASTEXITCODE -eq 0) { $WorktreeDir, $Branch } else { '--orphan', '-b', $Branch, $WorktreeDir }
            Invoke-Native git (@('worktree', 'add') + $addArgs)
        }

        Write-Host '==> Copying to worktree'
        Get-ChildItem $WorktreeDir -Force | Where-Object Name -ne '.git' | Remove-Item -Recurse -Force
        Invoke-Native scp @('-q', '-r', '-F', $SshCfg, "${sshHost}:$Stage/$GuestDir", (Resolve-Path -Relative $WorktreeDir))
        if (-not (Get-ChildItem "$WorktreeDir/$GuestDir" -Force)) { throw 'copied directory is empty' }

        $git = '-C', $WorktreeDir, '-c', 'core.autocrlf=false'
        Invoke-Native git ($git + @('add', '-A', '-f'))
        & git @git diff --cached --quiet
        if ($LASTEXITCODE -eq 0) { Write-Host '==> No changes, nothing to commit'; return }

        $stamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        Invoke-Native git ($git + @('commit', '-q', '-m', "Backup $GuestDir from VM @ $stamp"))
        Write-Host "==> Committed to '$Branch' (local only)"
    } finally {
        Remove-Item $SshCfg -Force -ErrorAction SilentlyContinue
        & vagrant ssh @MachineArg -c "rm -rf '$Stage'" 2>$null | Out-Null
    }
} finally {
    Pop-Location
}
