#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Dumps the current Sysmon event log to E:\cases (survives RestoreLab).

.DESCRIPTION
    Detonate.ps1 already captures Sysmon per run. Use this for an ad-hoc export - e.g. after
    poking at something by hand without a full detonation. Writes a complete .evtx plus a CSV.

.PARAMETER Name
    Label for the output folder (default: "sysmon").

.PARAMETER SinceMinutes
    Only include events from the last N minutes in the CSV (default: all).
#>
param(
    [string]$Name = 'sysmon',
    [int]$SinceMinutes = 0
)

$ErrorActionPreference = 'Stop'
$log = 'Microsoft-Windows-Sysmon/Operational'
if (-not (Get-Service Sysmon64 -ErrorAction SilentlyContinue)) { Write-Host "[!] Sysmon isn't installed." -ForegroundColor Red; exit 1 }

$dir = Join-Path 'E:\cases' ("{0}_{1}" -f $Name, (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
New-Item -ItemType Directory -Force $dir | Out-Null

Write-Host "[*] Exporting full Sysmon log to sysmon.evtx" -ForegroundColor Cyan
& wevtutil epl $log (Join-Path $dir 'sysmon.evtx') /ow:true

$filter = @{ LogName = $log }
if ($SinceMinutes -gt 0) { $filter.StartTime = (Get-Date).AddMinutes(-$SinceMinutes) }
Write-Host "[*] Writing sysmon.csv" -ForegroundColor Cyan
Get-WinEvent -FilterHashtable $filter -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, @{n='Event';e={($_.Message -split "`n")[0].TrimEnd(':')}}, Message |
    Export-Csv (Join-Path $dir 'sysmon.csv') -NoTypeInformation

Write-Host "[+] Exported to $dir" -ForegroundColor Green
