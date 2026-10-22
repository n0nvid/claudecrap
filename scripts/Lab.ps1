#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Desktop "Lab" menu: type BACKUP to save C: as the clean baseline (SaveBaseline.ps1) or
    RESTORE to wipe C: back to it (RestoreLab.ps1). Either one reboots the PC.
#>

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Menu.ps1')

$dark = Test-Path (Join-Path $PSScriptRoot '.godark-state.json')
$status = if ($dark) { 'GoDark is active: this machine may have run malware, so RESTORE, not BACKUP.' }
          else { 'Both options reboot the PC. Save your work and shut down REMnux first.' }

$choices = [ordered]@{
    BACKUP  = 'Save the CURRENT C: as the clean baseline (only on a clean machine)'
    RESTORE = 'Wipe C: back to the clean baseline (everything since is lost)'
}
switch (Read-MenuChoice 'Lab' $status $choices) {
    'BACKUP'  { & (Join-Path $PSScriptRoot 'SaveBaseline.ps1') -Confirmed }
    'RESTORE' { & (Join-Path $PSScriptRoot 'RestoreLab.ps1') -Confirmed }
}
