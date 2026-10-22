<#
.SYNOPSIS
    Restores E: (Evidence) from a backup made by BackupEvidence.ps1, folder structure intact.

.DESCRIPTION
    Lists the dated backups on the USB drive (newest first) and restores the one you pick.

    Two ways to restore:
      EXACT  E: ends up identical to the backup. Files on E: that aren't in the backup are DELETED.
      MERGE  Files from the backup are copied back over E:; anything else on E: is left alone.

    Refuses while GoDark is active unless you use -Force.

.PARAMETER Drive
    Drive letter of the USB drive, e.g. F.

.PARAMETER Force
    Restore even though GoDark appears to be active.

.EXAMPLE
    .\RestoreEvidence.ps1
#>
param(
    [string]$Drive,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UsbDrive.ps1')
$Target = 'E:\'

Assert-NotDark -Force:$Force
if (-not (Test-Path $Target)) { Write-Bad "E: (Evidence) not found."; exit 1 }
$usb = Select-UsbDrive $Drive

# --- Pick a backup ----------------------------------------------------------------------
$root = "$($usb.DriveLetter):\EvidenceBackup"
$backups = @(Get-ChildItem $root -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object Name -match '^\d{4}-\d{2}-\d{2}_\d{4}$' | Sort-Object Name -Descending)
if (-not $backups) { Write-Bad "No backups found in $root."; exit 1 }

Write-Host ""
for ($i = 0; $i -lt $backups.Count; $i++) {
    $files = @(Get-ChildItem $backups[$i].FullName -Recurse -File -Force)
    $size = ($files | Measure-Object Length -Sum).Sum
    Write-Host ("  [{0}] {1}   {2,6} files  {3,8:N2} GB{4}" -f ($i + 1), $backups[$i].Name, $files.Count, ($size / 1GB), $(if ($i -eq 0) { '   (newest)' }))
}
$pick = Read-Host "  Which backup? (Enter = 1)"
if (-not $pick) { $pick = '1' }
$n = 0
if (-not [int]::TryParse($pick, [ref]$n) -or $n -lt 1 -or $n -gt $backups.Count) { Write-Bad "Not a listed number."; exit 1 }
$source = $backups[$n - 1].FullName

# --- Pick the mode ----------------------------------------------------------------------
Write-Host ""
Write-Host "  EXACT = make E: identical to the backup (DELETES anything on E: that isn't in it)" -ForegroundColor Yellow
Write-Host "  MERGE = copy the backup over E:, keep everything else" -ForegroundColor Yellow
$mode = Read-Host "  Type EXACT or MERGE"
if ($mode -cnotin 'EXACT', 'MERGE') { Write-Bad "Cancelled."; exit 1 }

# --- Restore ----------------------------------------------------------------------------
$copyMode = if ($mode -ceq 'EXACT') { '/MIR' } else { '/E' }
Write-Step "Restoring $source to E: ($mode)"
robocopy $source $Target $copyMode /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NP /NDL /NFL `
    /XD (Get-SystemFolderExcludes $Target) | Out-Null
$rc = $LASTEXITCODE

# --- Verify: every backed-up file is on E: with the same size -----------------------------
$files = @(Get-ChildItem $source -Recurse -File -Force)
$bad = @($files | Where-Object {
    $onE = Join-Path $Target $_.FullName.Substring($source.Length + 1)
    -not (Test-Path -LiteralPath $onE) -or (Get-Item -LiteralPath $onE -Force).Length -ne $_.Length
})

Write-Host ""
if ($rc -ge 8 -or $bad.Count -gt 0) {
    Write-Bad "$($bad.Count) of $($files.Count) file(s) did not restore (robocopy exit $rc):"
    $bad | Select-Object -First 20 | ForEach-Object { Write-Bad "  $($_.FullName)" }
    Write-Bad "Antivirus quarantining malware samples is the usual cause."
    exit 1
}
Write-Host "  RESTORED $($files.Count) file(s) from $($backups[$n - 1].Name) to E: ($mode)  " -BackgroundColor DarkGreen -ForegroundColor White
exit 0
