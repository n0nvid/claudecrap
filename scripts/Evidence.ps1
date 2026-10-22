<#
.SYNOPSIS
    Desktop "Evidence" menu: type BACKUP to copy E: to a USB drive (BackupEvidence.ps1) or
    RESTORE to copy a backup back onto E: (RestoreEvidence.ps1).
#>

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Menu.ps1')

$choices = [ordered]@{
    BACKUP  = 'Copy all of E: to a USB drive (new dated folder each time)'
    RESTORE = 'Copy a backup from the USB drive back onto E:'
}
switch (Read-MenuChoice 'Evidence' 'Plug in the USB drive first.' $choices) {
    'BACKUP'  { & (Join-Path $PSScriptRoot 'BackupEvidence.ps1') }
    'RESTORE' { & (Join-Path $PSScriptRoot 'RestoreEvidence.ps1') }
}
