#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Reconnects this machine to real networks after GoDark.ps1.

.DESCRIPTION
    Only run this on a CLEAN machine: restore the disk image first if anything was
    detonated since GoDark.ps1. An infected machine that goes online can reach your
    home network and the internet.

    1. Asks you to confirm the machine is clean (skip with -Force).
    2. Removes the REMnux gateway and DNS from VMnet1 and re-enables the adapters
       GoDark.ps1 disabled.
    3. Restores the Wi-Fi profiles from wifi-profiles.enc (asks for the passphrase).
    4. Waits up to 30 seconds for an internet connection and reports the result.

.PARAMETER Force
    Skip the "is this machine clean?" confirmation.
#>
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WifiVault.ps1')
$StateFile = Join-Path $PSScriptRoot '.godark-state.json'

function Write-Step($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Bad($msg)  { Write-Host "[!] $msg" -ForegroundColor Red }

# --- 1. Confirm the machine is clean ----------------------------------------------------
if (-not $Force) {
    Write-Host ""
    Write-Host "  Has the clean disk image been restored since the last detonation?  " -BackgroundColor DarkYellow -ForegroundColor Black
    $answer = Read-Host "  Type YES to go online"
    if ($answer -cne 'YES') {
        Write-Bad "Staying dark."
        exit 1
    }
}

# --- 2. Stop sending traffic to REMnux --------------------------------------------------
$vmnet1 = Get-NetAdapter | Where-Object InterfaceDescription -match 'VMnet1$'
if ($vmnet1) {
    Write-Step "Removing the REMnux route and DNS from $($vmnet1.Name)"
    Remove-NetRoute -InterfaceIndex $vmnet1.ifIndex -DestinationPrefix '0.0.0.0/0' -Confirm:$false -ErrorAction SilentlyContinue
    Set-DnsClientServerAddress -InterfaceIndex $vmnet1.ifIndex -ResetServerAddresses
}

# --- 3. Re-enable adapters --------------------------------------------------------------
if (Test-Path $StateFile) {
    $names = @((Get-Content $StateFile -Raw | ConvertFrom-Json).Disabled)
} else {
    Write-Step "No GoDark state file found; enabling every disabled adapter"
    $names = @(Get-NetAdapter | Where-Object Status -eq 'Disabled' | ForEach-Object Name)
}
foreach ($name in $names) {
    if (Get-NetAdapter -Name $name -ErrorAction SilentlyContinue) {
        Write-Step "Enabling $name"
        Enable-NetAdapter -Name $name -Confirm:$false
    }
}
Remove-Item $StateFile -ErrorAction SilentlyContinue

# --- 4. Restore Wi-Fi profiles from the vault -------------------------------------------
if (Test-Path $VaultFile) {
    $profiles = $null
    for ($try = 1; $try -le 3 -and -not $profiles; $try++) {
        $profiles = Open-WifiVault (Read-Passphrase '  Wi-Fi vault passphrase')
        if (-not $profiles) { Write-Bad "Wrong passphrase." }
    }
    if ($profiles) {
        # The Wi-Fi adapter was only just enabled; give WLAN AutoConfig a moment to see it.
        for ($i = 0; $i -lt 10; $i++) { netsh wlan show profiles | Out-Null; if ($LASTEXITCODE -eq 0) { break }; Start-Sleep -Seconds 1 }
        if ((Restore-WifiProfiles $profiles) -eq 0) {
            Remove-Item $VaultFile
            Write-Ok "Wi-Fi profiles restored; vault deleted"
        } else {
            Write-Bad "Vault left in place so you can try again."
        }
    } else {
        Write-Bad "Vault left in place. Run GoOnline.ps1 again, or connect from the Wi-Fi menu."
    }
} else {
    Write-Step "No Wi-Fi vault found (a restored disk image already has its own saved networks)"
}

# --- 5. Wait for internet ---------------------------------------------------------------
Write-Step "Waiting for an internet connection"
$deadline = (Get-Date).AddSeconds(30)
$online = $false
while ((Get-Date) -lt $deadline -and -not $online) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $online = $client.ConnectAsync('1.1.1.1', 443).Wait(2000)
    } catch {
        Start-Sleep -Seconds 2
    } finally {
        $client.Dispose()
    }
}

Write-Host ""
if ($online) {
    Write-Host "  ONLINE  " -BackgroundColor DarkGreen -ForegroundColor White
    exit 0
}
Write-Bad "Adapters are enabled but there is no internet yet. Connect from the Wi-Fi menu if needed."
exit 1
