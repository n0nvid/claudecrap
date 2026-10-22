#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Runs a malware sample under instrumentation and collects the evidence to E:\cases.

.DESCRIPTION
    Unattended detonation helper for the bare-metal victim. It:
      1. Refuses unless the machine is DARK (GoDark active) - never detonates online.
      2. Takes a BEFORE snapshot of the system (autoruns, processes, services, tasks, hosts, drops).
      3. Starts captures: Procmon + Sysmon on the host, and tcpdump on REMnux (outside the malware's reach).
      4. STOPS and hands off to you - it does NOT run the sample. You launch it yourself when ready.
      5. When you press Enter (or after -Minutes, if given), stops the captures, takes an AFTER snapshot, diffs.
      6. Collects everything, plus INetSim's logs from REMnux, into E:\cases\<name>_<timestamp>\.

    The sample stays where it is (e.g. E:\samples) and is run from there - nothing is copied to C:.
    A record copy (sample.bin) is saved into the case folder, but that copy is not what you execute.

    TRUST NOTE: this script and its host-side output (Procmon, Sysmon, the snapshots) run on the infected
    machine, so capable malware can see or tamper with them. The REMnux-side pcap and INetSim logs
    are captured outside the victim and are the more trustworthy record. RestoreLab afterwards.

.PARAMETER Sample
    Path to the sample. Defaults to picking from E:\samples.

.PARAMETER Minutes
    Optional automatic stop after N minutes. Default 0 = capture until you press Enter.

.PARAMETER Name
    Case name (default: the sample's base name).

.PARAMETER Force
    Proceed even though GoDark doesn't appear to be active (NOT recommended).

.EXAMPLE
    .\Detonate.ps1
    .\Detonate.ps1 -Sample E:\samples\nasty.exe -Minutes 5
#>
param(
    [string]$Sample,
    [int]$Minutes = 0,
    [string]$Name,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$RemnuxIP  = '192.168.34.2'
$Vmx       = 'C:\RE\vms\REMnux\REMnux.vmx'
$Vmrun     = 'C:\Program Files\VMware\VMware Workstation\vmrun.exe'
$GuestUser = 'remnux'; $GuestPass = 'malware'
$Sys       = 'C:\RE\tools\Sysinternals'
$ShareRoot = 'E:\remnux'   # host side of the REMnux shared folder (/mnt/evidence in the guest)

function Step($m) { Write-Host "[*] $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[+] $m" -ForegroundColor Green }
function Bad($m)  { Write-Host "[!] $m" -ForegroundColor Red }
function Warn($m) { Write-Host "[?] $m" -ForegroundColor Yellow }
function Guest   { param([string]$Cmd) & $Vmrun -T ws -gu $GuestUser -gp $GuestPass runProgramInGuest $Vmx /bin/bash -c $Cmd 2>&1 }

# --- 1. Safety pre-flight ----------------------------------------------------------------
$isDark = Test-Path (Join-Path $PSScriptRoot '.godark-state.json')
if (-not $isDark -and -not $Force) {
    Bad "GoDark is NOT active. Refusing to detonate - run WiFi -> DARK first (or -Force to override)."
    exit 1
}
if ($isDark) { Ok "Machine is dark." }
else { Warn "GoDark NOT detected, but -Force given - proceeding WITHOUT isolation. This is dangerous unless you know the machine is offline." }
if (-not (Get-NetFirewallRule -DisplayName 'LabDark allow outbound on VMnet1' -ErrorAction SilentlyContinue)) {
    Warn "The VMnet1 outbound-allow rule is missing - the sample's traffic may not reach REMnux (re-run GoDark)."
}
$def = (Get-MpComputerStatus -ErrorAction SilentlyContinue).RealTimeProtectionEnabled
if ($def) { Warn "Defender real-time protection is ON - it may quarantine the sample. Exclude E:\samples or disable it first if the sample vanishes." }

# --- Pick the sample ---------------------------------------------------------------------
if (-not $Sample) {
    $cands = @(Get-ChildItem E:\samples -File -Recurse -ErrorAction SilentlyContinue)
    if (-not $cands) { Bad "No files in E:\samples. Pass -Sample <path>."; exit 1 }
    for ($i=0; $i -lt $cands.Count; $i++) { Write-Host ("  [{0}] {1}  ({2:N0} KB)" -f ($i+1), $cands[$i].FullName, ($cands[$i].Length/1KB)) }
    $pick = Read-Host "  Which sample? (number)"; $n=0
    if (-not [int]::TryParse($pick,[ref]$n) -or $n -lt 1 -or $n -gt $cands.Count) { Bad "Not a listed number."; exit 1 }
    $Sample = $cands[$n-1].FullName
}
if (-not (Test-Path -LiteralPath $Sample)) { Bad "Sample not found: $Sample"; exit 1 }
$sampleItem = Get-Item -LiteralPath $Sample
if (-not $Name) { $Name = $sampleItem.BaseName }

# --- Case folders ------------------------------------------------------------------------
$stamp   = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$caseId  = "${Name}_$stamp"
$case    = Join-Path 'E:\cases' $caseId
$before  = Join-Path $case 'before'
$after   = Join-Path $case 'after'
$netDir  = Join-Path $case 'network'
$share   = Join-Path $ShareRoot $caseId          # host side; guest sees /mnt/evidence/<caseId>
$guestEv = "/mnt/evidence/$caseId"
$null = New-Item -ItemType Directory -Force $case,$before,$after,$netDir,$share

Write-Host ""
Write-Host "  DETONATION: $caseId  " -BackgroundColor DarkRed -ForegroundColor White
Write-Host "  Sample : $Sample"
Write-Host "  Stop   : $(if($Minutes -gt 0){"Enter, or after $Minutes min"}else{'when you press Enter'})"
Write-Host "  Output : $case"
Write-Host ""
Write-Host "  This only sets up the capture - YOU launch the sample afterward." -ForegroundColor DarkGray
if ((Read-Host "  Type GO to start the capture") -cne 'GO') { Bad "Cancelled."; Remove-Item $case,$share -Recurse -Force -EA SilentlyContinue; exit 1 }

# Record the sample's identity (and copy it into the case, with a .bin suffix so it won't run by accident).
Step "Hashing the sample"
# .NET rather than Get-FileHash: no module dependency, works the same in PowerShell 5.1 and 7.
$sha = [System.Security.Cryptography.SHA256]::Create()
$fs  = [IO.File]::OpenRead($Sample)
try { $hash = ([BitConverter]::ToString($sha.ComputeHash($fs)) -replace '-','') } finally { $fs.Dispose(); $sha.Dispose() }
@(
    "name        : $($sampleItem.Name)"
    "path        : $Sample"
    "size        : $($sampleItem.Length) bytes"
    "sha256      : $hash"
    "detonated   : $(Get-Date -Format s)"
    "run_minutes : $Minutes"
) | Set-Content (Join-Path $case 'sample.txt')
Copy-Item -LiteralPath $Sample (Join-Path $case "sample.bin") -Force

# --- Snapshot function -------------------------------------------------------------------
function Take-Snapshot([string]$dir) {
    try { & "$Sys\autorunsc64.exe" -accepteula -nobanner -a * -c -h 2>$null | Out-File (Join-Path $dir 'autoruns.csv') -Encoding utf8 } catch { Warn "autoruns failed: $_" }
    try { Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine | Sort-Object ProcessId | Export-Csv (Join-Path $dir 'processes.csv') -NoTypeInformation } catch {}
    try { Get-CimInstance Win32_Service | Select-Object Name,State,StartMode,PathName | Sort-Object Name | Export-Csv (Join-Path $dir 'services.csv') -NoTypeInformation } catch {}
    try { Get-ScheduledTask | Select-Object TaskPath,TaskName,State | Sort-Object TaskPath,TaskName | Export-Csv (Join-Path $dir 'tasks.csv') -NoTypeInformation } catch {}
    try { Get-NetTCPConnection | Where-Object State -ne 'Listen' | Select-Object LocalAddress,LocalPort,RemoteAddress,RemotePort,State,OwningProcess | Export-Csv (Join-Path $dir 'connections.csv') -NoTypeInformation } catch {}
    try { Copy-Item "$env:SystemRoot\System32\drivers\etc\hosts" (Join-Path $dir 'hosts.txt') -Force } catch {}
    try {
        $runKeys = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
                   'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
        $runKeys | ForEach-Object { if (Test-Path $_) { "### $_"; (Get-ItemProperty $_).PSObject.Properties | Where-Object Name -notmatch '^PS' | ForEach-Object { "  $($_.Name) = $($_.Value)" } } } | Out-File (Join-Path $dir 'run_keys.txt') -Encoding utf8
    } catch {}
    # File listings of common drop locations (path/size/mtime; cheap, no hashing)
    $drops = $env:TEMP, $env:APPDATA, $env:LOCALAPPDATA, $env:ProgramData, "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup", "$env:SystemRoot\System32\Tasks"
    foreach ($d in $drops) {
        if (Test-Path $d) {
            $safe = ($d -replace '[:\\ ]','_')
            try { Get-ChildItem $d -Recurse -File -Force -ErrorAction SilentlyContinue | Select-Object FullName,Length,LastWriteTime | Export-Csv (Join-Path $dir "drops_$safe.csv") -NoTypeInformation } catch {}
        }
    }
}

Step "BEFORE snapshot"
Take-Snapshot $before
Ok "Snapshot saved."

# --- Start captures ----------------------------------------------------------------------
$remnuxUp = (New-Object System.Net.Sockets.TcpClient).ConnectAsync($RemnuxIP,80).Wait(2000)
if ($remnuxUp) {
    Step "Starting tcpdump on REMnux (ens33 -> $guestEv/capture.pcap)"
    Guest "mkdir -p $guestEv && echo $GuestPass | sudo -S -p '' nohup tcpdump -i ens33 -w $guestEv/capture.pcap >/dev/null 2>&1 &" | Out-Null
    Start-Sleep 2
} else {
    Warn "REMnux not answering - no network capture. Start the REMnux VM for pcap + INetSim logs."
}

$pml = Join-Path $case 'procmon.pml'
Step "Starting Procmon (host activity -> procmon.pml)"
& "$Sys\Procmon64.exe" /AcceptEula /Quiet /Minimized /BackingFile $pml
Start-Sleep 3

# Mark the start time so we can pull just this run's Sysmon events afterward.
$runStart = Get-Date

# --- Hand off to you: the script never launches the sample -------------------------------
# Captures are running. YOU launch the sample when ready, and press Enter to stop collecting.
Write-Host ""
Write-Host "  PREP COMPLETE - captures are running (Procmon, Sysmon, REMnux tcpdump).  " -BackgroundColor DarkRed -ForegroundColor White
Write-Host ""
Write-Host "  >> Launch the sample yourself now:" -ForegroundColor Yellow
Write-Host "       $Sample" -ForegroundColor White
Write-Host "     (double-click it, or run it the way you intend - .exe directly, rundll32 for a .dll," -ForegroundColor DarkGray
Write-Host "      open a document in its app, etc. It stays on E: - nothing was copied to C:.)" -ForegroundColor DarkGray
Write-Host ""

if ($Minutes -gt 0) {
    Write-Host "  Capturing until you press Enter, or $Minutes min - whichever comes first." -ForegroundColor Cyan
    $deadline = (Get-Date).AddMinutes($Minutes)
    while ((Get-Date) -lt $deadline) {
        try { if ([Console]::KeyAvailable -and [Console]::ReadKey($true).Key -eq 'Enter') { break } } catch {}
        $left = [int]($deadline - (Get-Date)).TotalSeconds
        Write-Host ("`r  capturing... {0,4}s left (Enter to stop now) " -f $left) -NoNewline -ForegroundColor DarkGray
        Start-Sleep -Milliseconds 500
    }
    Write-Host ""
} else {
    Read-Host "  Capturing. Run the sample, then press Enter here to STOP and collect"
}

# --- Stop captures -----------------------------------------------------------------------
Step "Stopping Procmon"
& "$Sys\Procmon64.exe" /Terminate | Out-Null
Start-Sleep 2

# Sysmon runs all the time, so there's a record even if Procmon missed something. Export this run's.
$SysmonLog = 'Microsoft-Windows-Sysmon/Operational'
if (Get-Service Sysmon64 -ErrorAction SilentlyContinue) {
    Step "Exporting Sysmon events"
    try { & wevtutil epl $SysmonLog (Join-Path $case 'sysmon.evtx') /ow:true } catch { Warn "sysmon.evtx export failed: $_" }
    try {
        Get-WinEvent -FilterHashtable @{ LogName = $SysmonLog; StartTime = $runStart } -ErrorAction SilentlyContinue |
            Select-Object TimeCreated, Id, @{n='Event';e={($_.Message -split "`n")[0].TrimEnd(':')}}, Message |
            Export-Csv (Join-Path $case 'sysmon_window.csv') -NoTypeInformation
    } catch { Warn "sysmon window CSV failed: $_" }
}

if ($remnuxUp) {
    Step "Stopping tcpdump and collecting INetSim logs on REMnux"
    Guest "echo $GuestPass | sudo -S -p '' pkill -INT tcpdump; sleep 2; mkdir -p $guestEv/inetsim && echo $GuestPass | sudo -S -p '' cp -r /var/log/inetsim/. $guestEv/inetsim/ 2>/dev/null; echo $GuestPass | sudo -S -p '' chmod -R a+r $guestEv" | Out-Null
    Start-Sleep 2
    # Move the share contents (pcap + inetsim logs) into the case's network folder
    try { Get-ChildItem $share -Force -ErrorAction SilentlyContinue | Move-Item -Destination $netDir -Force; Ok "Network artifacts in $netDir" } catch { Warn "Could not move network artifacts: $_" }
}
Remove-Item $share -Recurse -Force -ErrorAction SilentlyContinue

Step "AFTER snapshot"
Take-Snapshot $after
Ok "Snapshot saved."

# --- Diff before/after -------------------------------------------------------------------
Step "Diffing before/after"
$sum = Join-Path $case 'summary.txt'
"DETONATION SUMMARY - $caseId" | Set-Content $sum
"sample sha256: $hash" | Add-Content $sum
"" | Add-Content $sum

function Diff-Lines([string]$label, [string]$file) {
    $b = Join-Path $before $file; $a = Join-Path $after $file
    if (-not (Test-Path $a)) { return }
    $bl = if (Test-Path $b) { Get-Content $b } else { @() }
    $al = Get-Content $a
    $new = Compare-Object $bl $al | Where-Object SideIndicator -eq '=>' | ForEach-Object { $_.InputObject }
    "== NEW in $label ($($new.Count)) ==" | Add-Content $sum
    if ($new) { $new | Add-Content $sum } else { "  (none)" | Add-Content $sum }
    "" | Add-Content $sum
}
Diff-Lines 'autoruns (autostart entries)' 'autoruns.csv'
Diff-Lines 'run keys'                     'run_keys.txt'
Diff-Lines 'hosts file'                   'hosts.txt'
foreach ($f in (Get-ChildItem $before -Filter 'drops_*.csv' -EA SilentlyContinue).Name + (Get-ChildItem $after -Filter 'drops_*.csv' -EA SilentlyContinue).Name | Select-Object -Unique) {
    Diff-Lines "files ($($f -replace 'drops_|\.csv',''))" $f
}
# services / tasks / processes by name
foreach ($pair in @(@('services','services.csv'),@('scheduled tasks','tasks.csv'),@('processes','processes.csv'))) {
    Diff-Lines $pair[0] $pair[1]
}
# Sysmon event-type counts for this run (high-signal: 1=proc, 3=net, 11=file, 13=reg, 22=DNS)
$swin = Join-Path $case 'sysmon_window.csv'
if (Test-Path $swin) {
    $names = @{1='ProcessCreate';3='NetworkConnect';5='ProcessTerminate';7='ImageLoad';8='CreateRemoteThread';
               11='FileCreate';12='RegKey';13='RegValue';15='FileStream';22='DnsQuery';23='FileDelete';25='ProcessTampering'}
    "== Sysmon events this run (by type) ==" | Add-Content $sum
    Import-Csv $swin | Group-Object Id | Sort-Object { [int]$_.Name } | ForEach-Object {
        "  id $($_.Name) $($names[[int]$_.Name]) : $($_.Count)" | Add-Content $sum
    }
    "" | Add-Content $sum
}

# INetSim-observed destinations, if we captured them
$inetReport = Get-ChildItem (Join-Path $netDir 'inetsim\report') -Filter '*.txt' -EA SilentlyContinue | Select-Object -First 1
if ($inetReport) {
    "== INetSim report ($($inetReport.Name)) ==" | Add-Content $sum
    Get-Content $inetReport.FullName | Add-Content $sum
}

Write-Host ""
Write-Host "  DONE - $caseId  " -BackgroundColor DarkGreen -ForegroundColor White
Write-Host "  Case folder : $case"
Write-Host "  Summary     : $sum"
Write-Host "  Procmon log : $pml  (open in Procmon to filter by the sample)"
if (Test-Path (Join-Path $case 'sysmon.evtx')) { Write-Host "  Sysmon      : sysmon.evtx + sysmon_window.csv" }
if ($remnuxUp) { Write-Host "  Network     : $netDir  (capture.pcap + inetsim\)" }
Write-Host ""
Warn "When finished: back up anything you need (Evidence -> BACKUP), then Lab -> RESTORE before going online."
