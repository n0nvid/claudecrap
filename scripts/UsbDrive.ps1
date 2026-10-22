<#
    Shared by BackupEvidence.ps1 and RestoreEvidence.ps1: finds the USB drive to use and
    refuses to run while GoDark is active.
#>

function Write-Step($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Bad($msg)  { Write-Host "[!] $msg" -ForegroundColor Red }

# While GoDark is active the machine may be running malware that could reach the USB drive.
function Assert-NotDark([switch]$Force) {
    if ((Test-Path (Join-Path $PSScriptRoot '.godark-state.json')) -and -not $Force) {
        Write-Bad "GoDark is active, so this machine may be running malware that could reach the USB drive."
        Write-Bad "Do this after RestoreLab + GoOnline instead, or use -Force."
        exit 1
    }
}

# Returns the USB volume to use: the one named by $Drive, the only one plugged in, or the one you pick.
function Select-UsbDrive([string]$Drive) {
    $usb = @(Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter } | Sort-Object DriveLetter)
    if ($Drive) {
        $usb = @($usb | Where-Object DriveLetter -eq $Drive.TrimEnd(':', '\')[0])
        if (-not $usb) { Write-Bad "$Drive is not a USB (removable) drive."; exit 1 }
    } elseif ($usb.Count -eq 0) {
        Write-Bad "No USB drive found. Plug one in and run this again."
        exit 1
    } elseif ($usb.Count -gt 1) {
        $usb | ForEach-Object { Write-Host ("  {0}:  {1,-20} {2,8:N1} GB free" -f $_.DriveLetter, $_.FileSystemLabel, ($_.SizeRemaining / 1GB)) }
        $pick = Read-Host "  Which drive letter?"
        $usb = @($usb | Where-Object DriveLetter -eq $pick.TrimEnd(':', '\')[0])
        if (-not $usb) { Write-Bad "Not one of the listed drives."; exit 1 }
    }
    return $usb[0]
}

# robocopy excludes for the Windows-managed folders at the root of a drive.
function Get-SystemFolderExcludes([string]$Root) {
    @("$Root`$RECYCLE.BIN", "${Root}System Volume Information")
}
