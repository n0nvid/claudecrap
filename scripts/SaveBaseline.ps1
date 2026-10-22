#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Saves the current C: partition as the clean baseline image.

.DESCRIPTION
    Reboots into Clonezilla, which images C: to the hidden image partition (with SHA-1
    checksums) and reboots back into Windows. Takes roughly 10-20 minutes.
    The previous baseline is kept as lab-clean.prev until the new one has saved successfully.

    Only run this on a CLEAN machine - whatever is on C: becomes what RestoreLab.ps1 restores.

.PARAMETER Force
    Save even though GoDark.ps1 appears to be active.

.PARAMETER Confirmed
    Skip the "Type SAVE" prompt (Lab.ps1 has already asked).
#>
param(
    [switch]$Force,
    [switch]$Confirmed
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'LabBoot.ps1')

if ((Test-Path (Join-Path $PSScriptRoot '.godark-state.json')) -and -not $Force) {
    Write-Host "[!] GoDark is active, so this machine may have run malware. Refusing to save it as the baseline." -ForegroundColor Red
    Write-Host "    Restore with RestoreLab.ps1 instead, or use -Force if you are sure it's clean." -ForegroundColor Red
    exit 1
}

if (-not $Confirmed) {
    Write-Host ""
    Write-Host "  This saves the CURRENT state of C: as the clean baseline.  " -BackgroundColor DarkYellow -ForegroundColor Black
    Write-Host "  Only do this on a clean machine. Save your work first; the PC will reboot.  " -BackgroundColor DarkYellow -ForegroundColor Black
    if ((Read-Host "  Type SAVE to continue") -cne 'SAVE') {
        Write-Host "[!] Cancelled." -ForegroundColor Red
        exit 1
    }
}

Invoke-LabBoot save
