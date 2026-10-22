<#
.SYNOPSIS
    Copies everything on E: (Evidence) to a USB drive, folder structure intact.

.DESCRIPTION
    Each run makes a new dated folder on the USB drive, EvidenceBackup\yyyy-MM-dd_HHmm, holding an
    exact copy of E: (folders, files, timestamps, attributes). An older backup is never overwritten,
    so a good copy survives even if malware later changes or deletes files on E:.
    RestoreEvidence.ps1 puts a backup back.

    Antivirus (Defender here, or on any PC the drive is plugged into) may quarantine malware
    samples as they're copied. robocopy then reports those files as failed and this script says so.

    Back up when the machine is CLEAN (online, after a restore). Refuses while GoDark is
    active unless you use -Force.

.PARAMETER Drive
    Drive letter of the USB drive, e.g. F. If omitted and exactly one USB drive is plugged
    in, that one is used; with several, you're asked to choose.

.PARAMETER Force
    Back up even though GoDark appears to be active.

.EXAMPLE
    .\BackupEvidence.ps1
    .\BackupEvidence.ps1 -Drive F
#>
param(
    [string]$Drive,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UsbDrive.ps1')
$Source = 'E:\'

Assert-NotDark -Force:$Force
if (-not (Test-Path $Source)) { Write-Bad "E: (Evidence) not found."; exit 1 }
$target = Select-UsbDrive $Drive
$dest = "$($target.DriveLetter):\EvidenceBackup\$(Get-Date -Format 'yyyy-MM-dd_HHmm')"

# --- Check there's room -----------------------------------------------------------------
$used = (Get-ChildItem $Source -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '^E:\\(System Volume Information|\$RECYCLE\.BIN)\\' } |
    Measure-Object Length -Sum).Sum
if (-not $used) { $used = 0 }
Write-Step ("E: holds {0:N2} GB; {1}: has {2:N2} GB free" -f ($used / 1GB), $target.DriveLetter, ($target.SizeRemaining / 1GB))
if ($used -gt $target.SizeRemaining) {
    Write-Bad "Not enough space on $($target.DriveLetter):. Nothing was copied."
    exit 1
}
New-Item -ItemType Directory -Force -Path $dest | Out-Null

# --- Copy -------------------------------------------------------------------------------
Write-Step "Copying E: to $dest"
$log = Join-Path $dest '..\backup-log.txt'
robocopy $Source $dest /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NP /NDL `
    /XD (Get-SystemFolderExcludes $Source) /LOG+:$log | Out-Null
$rc = $LASTEXITCODE
# robocopy gives the backup folder the drive root's Hidden+System attributes; make it visible again.
attrib -h -s $dest

# --- Verify: same files, same sizes -----------------------------------------------------
$src = @(Get-ChildItem $Source -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '^E:\\(System Volume Information|\$RECYCLE\.BIN)\\' })
$missing = @($src | Where-Object {
    $copy = Join-Path $dest $_.FullName.Substring(3)
    -not (Test-Path -LiteralPath $copy) -or (Get-Item -LiteralPath $copy -Force).Length -ne $_.Length
})

Write-Host ""
if ($rc -ge 8 -or $missing.Count -gt 0) {
    Write-Bad "$($missing.Count) of $($src.Count) file(s) did not copy (robocopy exit $rc):"
    $missing | Select-Object -First 20 | ForEach-Object { Write-Bad "  $($_.FullName)" }
    Write-Bad "Antivirus quarantining malware samples is the usual cause. Log: $log"
    exit 1
}
Write-Host "  BACKED UP $($src.Count) file(s) to $dest  " -BackgroundColor DarkGreen -ForegroundColor White
Write-Host "  Eject the drive from the taskbar before unplugging it." -ForegroundColor Green
exit 0
