#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Desktop "WiFi" menu: type DARK to run GoDark.ps1 or ONLINE to run GoOnline.ps1.
#>

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Menu.ps1')

$dark = Test-Path (Join-Path $PSScriptRoot '.godark-state.json')
$status = if ($dark) { 'Right now: DARK (GoDark is active)' } else { 'Right now: ONLINE' }

$choices = [ordered]@{
    DARK   = 'Save Wi-Fi, cut every real network, route everything to REMnux'
    ONLINE = 'Reconnect and restore Wi-Fi (only after RestoreLab if anything was run)'
}
switch (Read-MenuChoice 'WiFi' $status $choices) {
    'DARK'   { & (Join-Path $PSScriptRoot 'GoDark.ps1') }
    'ONLINE' { & (Join-Path $PSScriptRoot 'GoOnline.ps1') }
}
