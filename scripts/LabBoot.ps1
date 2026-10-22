<#
    Shared by SaveBaseline.ps1 and RestoreLab.ps1: tells the Clonezilla partition (label CZLAB)
    what to do, sets a one-time boot into it and reboots. Clonezilla runs lab/lab.sh, which
    saves or restores only the C: partition and then reboots back into Windows.
#>

function Invoke-LabBoot([ValidateSet('save', 'restore')][string]$Mode) {
    $ErrorActionPreference = 'Stop'

    # The firmware boot entry pointing at Clonezilla, found by its description.
    $fw = (bcdedit /enum firmware) -join "`n"
    $m = [regex]::Match($fw, '(?ms)^identifier\s+(\{[0-9a-f-]{36}\})\s*\n(?:(?!^identifier).)*?^description\s+Lab Clonezilla\s*$')
    if (-not $m.Success) { throw "No 'Lab Clonezilla' firmware boot entry found (bcdedit /enum firmware)." }
    $bootId = $m.Groups[1].Value

    $vol = Get-Volume -FileSystemLabel CZLAB -ErrorAction SilentlyContinue
    if (-not $vol) { throw "Clonezilla partition (label CZLAB) not found." }
    $part = $vol | Get-Partition

    # Mount the partition just long enough to write the mode file.
    $part | Add-PartitionAccessPath -AssignDriveLetter
    $drive = (Get-Partition -DiskNumber $part.DiskNumber -PartitionNumber $part.PartitionNumber).DriveLetter
    try {
        [IO.File]::WriteAllText("${drive}:\lab\mode", "$Mode`n")
    } finally {
        $part | Remove-PartitionAccessPath -AccessPath "${drive}:\"
    }

    bcdedit /set '{fwbootmgr}' bootsequence $bootId | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "bcdedit could not set the one-time boot." }

    Write-Host "[+] Next boot: Clonezilla ($Mode). The machine reboots back into Windows when it's done." -ForegroundColor Green
    Write-Host "    Rebooting in 10 seconds..." -ForegroundColor Green
    Start-Sleep -Seconds 10
    Restart-Computer -Force
}
