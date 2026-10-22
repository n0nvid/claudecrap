#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Restores C: to the clean baseline image.

.DESCRIPTION
    Reboots into Clonezilla, which checks the baseline's SHA-1 checksums, restores it over
    the C: partition and reboots back into Windows. Takes roughly 10-20 minutes.

    EVERYTHING written to C: since the baseline was saved is lost, including your own files.
    Push or copy off anything you want to keep first.
#>

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'LabBoot.ps1')

Write-Host ""
Write-Host "  This wipes C: back to the clean baseline.  " -BackgroundColor Red -ForegroundColor White
Write-Host "  Everything changed on C: since the baseline is lost. The PC will reboot.  " -BackgroundColor Red -ForegroundColor White
if ((Read-Host "  Type RESTORE to continue") -cne 'RESTORE') {
    Write-Host "[!] Cancelled." -ForegroundColor Red
    exit 1
}

Invoke-LabBoot restore
