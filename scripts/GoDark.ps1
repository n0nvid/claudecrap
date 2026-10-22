#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Cuts this machine off from every real network before detonating malware.

.DESCRIPTION
    1. Saves the Wi-Fi profiles (with passwords) to wifi-profiles.enc, encrypted with a
       passphrase you choose. GoOnline.ps1 asks for it to restore them.
    2. Deletes all saved Wi-Fi profiles so nothing can silently rejoin a network.
    3. Disables every network adapter except VMware VMnet1 (host-only, the link to REMnux).
    4. Points VMnet1's gateway and DNS at REMnux (192.168.34.2), the fake internet.
    5. Verifies: no other adapter is up, no saved profiles remain, and no route to the
       internet exists except through VMnet1.

    Exits with code 0 when dark, 1 when any check fails.
#>

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WifiVault.ps1')
$KeepPattern = 'VMnet1$'   # InterfaceDescription of the adapter that stays enabled
$RemnuxIP = '192.168.34.2'  # REMnux VM on VMnet1: gateway and DNS while dark
$StateFile = Join-Path $PSScriptRoot '.godark-state.json'
$TestTargets = '1.1.1.1', '8.8.8.8', '2606:4700:4700::1111'

function Write-Step($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Bad($msg)  { Write-Host "[!] $msg" -ForegroundColor Red }

function Get-WifiProfileNames {
    $out = netsh wlan show profiles 2>$null
    if ($LASTEXITCODE -ne 0) { return @() }
    $out | Where-Object { $_ -match 'All User Profile\s+:\s+(.+)$' } | ForEach-Object { $Matches[1].Trim() }
}

# --- 1. Save Wi-Fi profiles to the encrypted vault --------------------------------------
$profiles = @(Get-WifiProfileNames)
if ($profiles.Count -gt 0) {
    Write-Step "Saving $($profiles.Count) Wi-Fi profile(s) to the encrypted vault: $($profiles -join ', ')"
    while ($true) {
        $pass = Read-Passphrase '  Choose a passphrase'
        if ($pass.Length -lt 8) { Write-Bad "Use at least 8 characters."; continue }
        if ((Read-Passphrase '  Type it again') -ceq $pass) { break }
        Write-Bad "Passphrases didn't match."
    }
    $saved = Save-WifiVault $pass
    # Decrypt it straight back and make sure every profile is intact XML before deleting anything.
    $check = Open-WifiVault $pass
    $pass = $null
    $intact = @($check.Values | Where-Object { $_ -is [string] -and $_ -match '<\?xml' -and $_ -match '<keyMaterial>' }).Count
    if ($saved -ne $profiles.Count -or $intact -ne $profiles.Count) {
        Write-Bad "Vault check failed ($saved saved, $intact intact, $($profiles.Count) expected). Nothing else was changed."
        exit 1
    }
    Write-Ok "Saved to $VaultFile"
} elseif (Test-Path $VaultFile) {
    Write-Ok "No saved Wi-Fi profiles; keeping the existing vault $VaultFile"
}

# --- 2. Delete saved Wi-Fi profiles -----------------------------------------------------
if ($profiles.Count -gt 0) {
    Write-Step "Deleting saved Wi-Fi profiles: $($profiles -join ', ')"
    netsh wlan delete profile name=* i=* | Out-Null
}

# --- 3. Disable every adapter except VMnet1 ---------------------------------------------
$toDisable = Get-NetAdapter | Where-Object {
    $_.InterfaceDescription -notmatch $KeepPattern -and $_.Status -ne 'Disabled'
}
foreach ($a in $toDisable) {
    Write-Step "Disabling $($a.Name) ($($a.InterfaceDescription))"
    Disable-NetAdapter -Name $a.Name -Confirm:$false
}

# Remember what we disabled so GoOnline.ps1 can re-enable exactly those adapters.
$previous = @()
if (Test-Path $StateFile) { $previous = @((Get-Content $StateFile -Raw | ConvertFrom-Json).Disabled) }
$disabled = @($previous + @($toDisable | ForEach-Object Name)) | Sort-Object -Unique
@{ Disabled = $disabled; When = (Get-Date).ToString('s') } | ConvertTo-Json | Set-Content $StateFile

Start-Sleep -Seconds 2

# --- 4. Send all traffic and DNS to REMnux (the fake internet) over VMnet1 ---------------
# ActiveStore: the route disappears on reboot, so a forgotten GoOnline can't leave it behind.
$vmnet1 = Get-NetAdapter | Where-Object InterfaceDescription -match $KeepPattern
Write-Step "Routing all traffic and DNS to REMnux ($RemnuxIP) on $($vmnet1.Name)"
Remove-NetRoute -InterfaceIndex $vmnet1.ifIndex -DestinationPrefix '0.0.0.0/0' -Confirm:$false -ErrorAction SilentlyContinue
New-NetRoute -InterfaceIndex $vmnet1.ifIndex -DestinationPrefix '0.0.0.0/0' -NextHop $RemnuxIP -PolicyStore ActiveStore | Out-Null
Set-DnsClientServerAddress -InterfaceIndex $vmnet1.ifIndex -ServerAddresses $RemnuxIP

# --- 5. Verify ---------------------------------------------------------------------------
Write-Step "Verifying"
$failed = $false

$stillUp = Get-NetAdapter | Where-Object { $_.InterfaceDescription -notmatch $KeepPattern -and $_.Status -eq 'Up' }
if ($stillUp) {
    Write-Bad "Adapters still up: $(($stillUp | ForEach-Object Name) -join ', ')"
    $failed = $true
} else {
    Write-Ok "No adapters up except VMnet1"
}

$remaining = @(Get-WifiProfileNames)
if ($remaining.Count -gt 0) {
    Write-Bad "Wi-Fi profiles still saved: $($remaining -join ', ')"
    $failed = $true
} else {
    Write-Ok "No saved Wi-Fi profiles"
}

foreach ($ip in $TestTargets) {
    $route = Find-NetRoute -RemoteIPAddress $ip -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceAlias } | Select-Object -First 1
    if (-not $route) {
        Write-Ok "No route to $ip"
    } elseif ((Get-NetAdapter -InterfaceIndex $route.InterfaceIndex).InterfaceDescription -match $KeepPattern) {
        Write-Ok "$ip routes only to VMnet1 (REMnux)"
    } else {
        Write-Bad "$ip is still reachable via $($route.InterfaceAlias)"
        $failed = $true
    }
}

# REMnux being down doesn't make the machine less dark, so this only warns.
$client = New-Object System.Net.Sockets.TcpClient
try {
    if ($client.ConnectAsync($RemnuxIP, 80).Wait(2000)) { Write-Ok "REMnux fake internet is answering at $RemnuxIP" }
    else { Write-Host "[?] REMnux isn't answering at $RemnuxIP - start the VM to see network traffic" -ForegroundColor Yellow }
} catch {
    Write-Host "[?] REMnux isn't answering at $RemnuxIP - start the VM to see network traffic" -ForegroundColor Yellow
} finally { $client.Dispose() }

Write-Host ""
if ($failed) {
    Write-Host "  NOT DARK - do not detonate anything.  " -BackgroundColor Red -ForegroundColor White
    exit 1
}
Write-Host "  DARK - safe to detonate. Restore the disk image before running GoOnline.ps1.  " -BackgroundColor DarkGreen -ForegroundColor White
exit 0
