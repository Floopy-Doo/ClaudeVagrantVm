#Requires -Version 7.0
<#
Pulls superpowers plan/spec docs (docs/superpowers/plans, docs/superpowers/specs)
from the vagrant VM to a local folder, mirroring the remote relative path layout.
Run from PowerShell 7 on the Windows host. Assumes the `vagrant_vm` SSH host alias
is already usable non-interactively (key-based auth via ~/.ssh/config).
#>

param(
    [string]$SshHost = 'vagrant_vm',
    [string]$Destination = (Join-Path $HOME 'superpowers-docs'),
    [string[]]$SearchRoots = @('coding', 'presentation')
)

$ErrorActionPreference = 'Stop'

$remoteArchive = "/tmp/superpowers-docs-$([guid]::NewGuid().ToString('N')).tar.gz"
$rootsArg = ($SearchRoots | ForEach-Object { "'$_'" }) -join ' '

$remoteScript = @"
cd ~
find $rootsArg -type d \( -name .git -o -name node_modules -o -name bin -o -name obj \) -prune -o -type f \( -path '*/docs/superpowers/plans/*.md' -o -path '*/docs/superpowers/specs/*.md' \) -print > /tmp/superpowers-filelist.txt
if [ -s /tmp/superpowers-filelist.txt ]; then
    tar -czf $remoteArchive -T /tmp/superpowers-filelist.txt
    echo OK
else
    echo NO_MATCHES
fi
rm -f /tmp/superpowers-filelist.txt
"@

Write-Host "Scanning $SshHost for plans/specs under: $($SearchRoots -join ', ') (including .claude/worktrees/*)"
$remoteResult = ssh $SshHost $remoteScript
if ($LASTEXITCODE -ne 0) {
    throw "ssh to $SshHost failed (exit $LASTEXITCODE)"
}

$marker = $remoteResult | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 1
if ($marker -eq 'NO_MATCHES') {
    Write-Host 'No plan/spec files found.'
    exit 0
}

New-Item -ItemType Directory -Force -Path $Destination | Out-Null
$localArchive = Join-Path ([System.IO.Path]::GetTempPath()) (Split-Path $remoteArchive -Leaf)

try {
    scp -q "${SshHost}:$remoteArchive" $localArchive
    if ($LASTEXITCODE -ne 0) { throw "scp failed (exit $LASTEXITCODE)" }

    # Round-tripping through a remote file (rather than piping ssh's stdout straight
    # into a local tar process) sidesteps PowerShell's native-to-native pipeline,
    # which is not guaranteed binary-safe for a gzip stream.
    tar -xzf $localArchive -C $Destination
    if ($LASTEXITCODE -ne 0) { throw "local extraction failed (exit $LASTEXITCODE)" }

    $fileCount = (tar -tzf $localArchive | Measure-Object).Count
    Write-Host "Extracted $fileCount file(s) to $Destination"
}
finally {
    Remove-Item -Path $localArchive -ErrorAction SilentlyContinue
    ssh $SshHost "rm -f $remoteArchive" 2>$null | Out-Null
}
