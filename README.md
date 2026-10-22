# RE / Malware-Analysis Lab — Rebuild Guide

How to rebuild this lab from a clean Windows 11 install. State as of **2026-10-22**.

The laptop is a **throwaway, bare-metal** lab. Windows itself is the victim machine:
malware runs on it while it is cut off from real networks, and a REMnux VM plays the part of
the internet. A clean disk image gets the machine back afterwards. There's no FLARE-VM: the analysis
tools (section 2) are installed directly on the laptop.

```
 Windows laptop (victim)                    REMnux VM (VMware)
 ───────────────────────                    ──────────────────────────
 Wi-Fi / Ethernet: OFF (GoDark)             Network: Host-only (VMnet1)
 VMnet1 host adapter 192.168.34.1  ◄──────► 192.168.34.2 (static)
   default gateway -> 192.168.34.2          INetSim (HTTP/S, DNS, SMTP, POP3, FTP)
   DNS             -> 192.168.34.2          every connection to any IP -> INetSim
```

## Repo layout

| Path | What it is | Lives on the machine at |
|---|---|---|
| `scripts/GoDark.ps1` | Cuts off all real networks, routes everything to REMnux | `C:\RE\scripts\` |
| `scripts/GoOnline.ps1` | Undoes GoDark and restores Wi-Fi | `C:\RE\scripts\` |
| `scripts/WifiVault.ps1` | Passphrase-encrypted Wi-Fi profile storage, shared by both | `C:\RE\scripts\` |
| `RedGlow/` | C# app: red screen-edge glow while online | source `C:\RE\dev\RedGlow`, built to `C:\RE\tools\RedGlow` |
| `remnux/setup-fakenet.sh` | Turns the REMnux VM into the fake internet | run inside REMnux |
| `scripts/SaveBaseline.ps1`, `RestoreLab.ps1`, `LabBoot.ps1` | Save or restore C: through Clonezilla | `C:\RE\scripts\` |
| `scripts/WiFi.ps1`, `Lab.ps1`, `Evidence.ps1`, `Menu.ps1` | The three desktop menus | `C:\RE\scripts\` |
| `scripts/BackupEvidence.ps1`, `RestoreEvidence.ps1`, `UsbDrive.ps1` | Copy E: to a USB drive and back | `C:\RE\scripts\` |
| `clonezilla/lab.sh` | The unattended save/restore script Clonezilla runs | `lab\lab.sh` on the CZLAB partition |
| `memory/` | Claude Code's memory files for this project | `%USERPROFILE%\.claude\projects\C--Users-n0nvid-source-repos-Claude\memory\` |
| `MEMORY.md` | Older (2026-10-20) setup handoff; this README replaces it | |

---

## 1. Host preparation

Run in an **admin** PowerShell window.

```powershell
# Free the CPU's virtualization extensions for VMware (turns off Hyper-V, VBS, Memory Integrity, WSL2)
bcdedit /set hypervisorlaunchtype off
# Also turn off Memory Integrity: Windows Security > Device security > Core isolation.
# Reboot. To undo: bcdedit /set hypervisorlaunchtype auto

# Folder layout
New-Item -ItemType Directory -Force C:\RE\tools, C:\RE\dev, C:\RE\installers, C:\RE\scripts, C:\RE\vms

# Defender stays ON; exclude only your own source code folder
Add-MpPreference -ExclusionPath C:\RE\dev
```

Explorer: turn on **file name extensions** and **hidden items**.

## 2. Toolchain and RE tools

- **Dev:** Git, Python 3.12, .NET SDK 10 (and 8), Go, Rust (stable), OpenJDK 21, VS Code, 7-Zip.
- **RE tools** (in `C:\RE\tools`): Ghidra, IDA Free, x64dbg, dnSpy (dnSpyEx), PE-bear, CFF Explorer,
  pestudio, Detect It Easy, HxD, YARA, capa, FLOSS (standalone exe), Sysinternals Suite (on PATH),
  Wireshark.
- **Python RE venv:** `python -m venv C:\RE\tools\revenv`, then
  `C:\RE\tools\revenv\Scripts\pip install pefile capstone yara-python oletools`.

## 3. VMware Workstation Pro

Install VMware Workstation Pro (26.x, free for personal use). It creates **VMnet1 (host-only)**
and **VMnet8 (NAT)**. On this machine VMnet1 is `192.168.34.0/24` with the host at `.1`. If a new
install picks a different subnet, change `$RemnuxIP` in `GoDark.ps1` and `IP=` in `setup-fakenet.sh` to match.

## 4. Outbound firewall: Windows Firewall Control (Malwarebytes)

- Download `wfc6setup.exe` from binisoft.org and run the **GUI installer**.
  **Don't install it with `winget --silent`**: that put it in a relative folder and broke the service.
- Set the profile to **Medium** (block all outbound without a rule) and notifications to **Display**.
  Unknown programs are blocked first; you answer the popup afterwards.
- WFC rules are ordinary Windows Firewall rules. To back them up and restore them:
  ```powershell
  netsh advfirewall export "$env:USERPROFILE\Documents\FirewallBackup\firewall-<date>.wfw"
  netsh advfirewall import "<that file>"
  ```
- WFC blocks `curl.exe` and `git` until you allow them; `pwsh` downloads are allowed.

## 5. GoDark / GoOnline

Copy `scripts\*.ps1` to `C:\RE\scripts\` (keep all three together). Both scripts need admin.

**GoDark.ps1**
1. Saves every Wi-Fi profile, with its password, to `wifi-profiles.enc`, encrypted with a passphrase
   you type (PBKDF2-SHA256 → AES-256-CBC + HMAC-SHA256). It decrypts the file straight back to check it
   before deleting anything.
2. Deletes the saved Wi-Fi profiles so nothing can silently rejoin a network.
3. Disables every network adapter except VMnet1, and records which ones in `.godark-state.json`.
4. Sets VMnet1's default gateway (ActiveStore, so it's gone after a reboot) and DNS to REMnux, 192.168.34.2,
   and adds one firewall rule allowing outbound **only on the VMnet1 interface** ("LabDark allow outbound on VMnet1").
   WFC is block-first, which would otherwise drop the sample's connections before INetSim sees them; this lets them
   reach REMnux while every other interface stays blocked (and they're disabled anyway). GoOnline removes the rule.
5. Checks: no other adapter is up, no Wi-Fi profiles are left, and 1.1.1.1, 8.8.8.8 and a Cloudflare IPv6 address only
   route through VMnet1. Prints **DARK** or **NOT DARK** (exit code 1).

**GoOnline.ps1**: asks you to type `YES` to confirm the disk image has been restored, removes the REMnux
gateway and DNS, re-enables the adapters, asks for the passphrase and restores Wi-Fi, then waits for internet.

### Desktop: three menus

Each desktop shortcut opens a menu where you type a word **in capitals**. Lowercase is refused on purpose, so you
have to stop and think. The word is the confirmation, so the script underneath doesn't ask again. They share `Menu.ps1` and run in Windows PowerShell 5.1, so test changes in 5.1.

| Shortcut | Admin | Type | Runs |
|---|---|---|---|
| **WiFi** (`WiFi.ps1`) | yes | `DARK` / `ONLINE` | `GoDark.ps1` / `GoOnline.ps1`. The menu shows whether you're dark right now |
| **Lab** (`Lab.ps1`) | yes | `BACKUP` / `RESTORE` | `SaveBaseline.ps1 -Confirmed` / `RestoreLab.ps1 -Confirmed` (section 9). Both reboot |
| **Evidence** (`Evidence.ps1`) | no | `BACKUP` / `RESTORE` | `BackupEvidence.ps1` / `RestoreEvidence.ps1` (E: to USB and back) |
| **REMnux** | no | | opens and starts the REMnux VM (section 7) |

```powershell
$desk = [Environment]::GetFolderPath('Desktop'); $ws = New-Object -ComObject WScript.Shell
# Icons: copy icons\*.ico (Wireless, Petri dish, Fingerprint; see icons/README.md) to C:\RE\tools\icons\ first
foreach ($i in @(@{N='WiFi'; I='WiFi'; A=$true}, @{N='Lab'; I='PetriDish'; A=$true}, @{N='Evidence'; I='Fingerprint'; A=$false})) {
    $p = Join-Path $desk "$($i.N).lnk"; $l = $ws.CreateShortcut($p)
    $l.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $l.Arguments = "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"C:\RE\scripts\$($i.N).ps1`""
    $l.WorkingDirectory = 'C:\RE\scripts'; $l.IconLocation = "C:\RE\tools\icons\$($i.I).ico,0"; $l.Save()
    if ($i.A) { $b = [IO.File]::ReadAllBytes($p); $b[0x15] = $b[0x15] -bor 0x20; [IO.File]::WriteAllBytes($p, $b) }  # "Run as administrator"
}
```

## 6. RedGlow (red screen edge while online)

A click-through, always-on-top overlay on every monitor. It shows whenever any adapter that isn't a VMware adapter
has a default gateway, meaning you are **not** dark. The tray icon (shield) shows the status and has an Exit item.
FLARE-VM does **not** have this feature; it was written for this lab.

```powershell
Copy-Item -Recurse RedGlow C:\RE\dev\RedGlow
dotnet publish C:\RE\dev\RedGlow -c Release -o C:\RE\tools\RedGlow
# Start at login
$ws = New-Object -ComObject WScript.Shell
$l = $ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Startup')) 'RedGlow.lnk'))
$l.TargetPath = 'C:\RE\tools\RedGlow\RedGlow.exe'; $l.WorkingDirectory = 'C:\RE\tools\RedGlow'; $l.Save()
```

To change the strength or colour, edit `MaxAlpha` and `Red/Green/Blue` in `GlowWindow.cs`, exit RedGlow
from the tray, and publish again.

## 7. REMnux fake internet

1. **Download** the VMware OVA from <https://docs.remnux.org/install-distro/get-virtual-appliance>
   (used: `202610b/remnux-noble-amd64.ova`, SHA-256
   `060acb0087c7ae6d138d7a994f5a1daf957fe3f9d0fdf72012b2c43e88876ef9`). It's about 8 GB. Use
   `Invoke-WebRequest ... -Resume` if the connection drops.
2. **Import:**
   ```powershell
   & 'C:\Program Files\VMware\VMware Workstation\OVFTool\ovftool.exe' --acceptAllEulas --name=REMnux --lax `
       C:\RE\installers\remnux\remnux-noble-amd64.ova C:\RE\vms\
   ```
3. **Fix the .vmx** (`C:\RE\vms\REMnux\REMnux.vmx`):
   - `virtualhw.version = "99"` → `"21"`. The import writes 99, and VMware refuses to boot it.
   - `ethernet0.connectionType = "nat"` → `"hostonly"`. **REMnux must never have a real network.**
4. **Start it and run the setup script** (default login `remnux` / `malware`):
   ```powershell
   $vr = 'C:\Program Files\VMware\VMware Workstation\vmrun.exe'; $v = 'C:\RE\vms\REMnux\REMnux.vmx'
   & $vr -T ws start $v nogui
   $g = '-T','ws','-gu','remnux','-gp','malware'
   & $vr @g CopyFileFromHostToGuest $v .\remnux\setup-fakenet.sh /tmp/setup-fakenet.sh   # must have LF line endings
   & $vr @g runProgramInGuest $v /bin/bash /tmp/setup-fakenet.sh
   & $vr @g CopyFileFromGuestToHost $v /tmp/setup.log .\setup.log; Get-Content .\setup.log
   ```
   The script sets the static IP 192.168.34.2 (and stops cloud-init from rewriting it), points INetSim at that address with
   DNS enabled (the original config is saved as `/etc/inetsim/inetsim.conf.orig`), and installs the
   **`lab-fakenet.service`**. That service adds an iptables `REDIRECT` for all traffic arriving on `ens33`, then runs INetSim, at every boot.
5. **Take a snapshot:** `& $vr -T ws snapshot $v 'Clean fakenet'`
   Desktop shortcut **REMnux**: `"C:\Program Files\VMware\VMware Workstation\vmware.exe" -x "C:\RE\vms\REMnux\REMnux.vmx"`
   (opens VMware and powers the VM on).
6. **Test from Windows** (works while still online):
   ```powershell
   Resolve-DnsName anything-fake.xyz -Server 192.168.34.2 -DnsOnly   # -> 192.168.34.2
   Invoke-WebRequest http://192.168.34.2/payload.exe                 # -> 200, "INetSim HTTP Server"
   ```

## 8. Detonation workflow

1. Online: write code, push it off the machine.
2. Start REMnux (**REMnux** shortcut), then **WiFi** → `DARK`. Wait for **DARK** and check the red glow has gone.
3. Run the sample. Capture traffic on REMnux (Wireshark/tcpdump on `ens33`); INetSim logs are in
   `/var/log/inetsim/`. WFC will still block unknown programs, so allow them or lower WFC's
   profile while dark if you want to see their traffic.
4. Put anything you want to keep on E:, then **Lab** → `RESTORE`.
5. **WiFi** → `ONLINE`. Never go online after a detonation without restoring first.

## 9. On-disk recovery image (Clonezilla)

Disk layout (954 GB NVMe, GPT). Windows numbers partitions by position on disk, so numbers can change; the scripts find
partitions by label (`CZLAB`) and GPT partition GUID, never by number.

| # | Partition | Size | Notes |
|---|---|---|---|
| 1 | EFI system | 0.2 GB | |
| 2 | MSR | 16 MB | |
| 3 | **C:** | 426 GB | the only partition that gets saved or restored |
| 7 | **E: Evidence** | 50 GB | NTFS. Never restored: `samples\`, `cases\`, `remnux\` (shared into REMnux at `/mnt/evidence`) |
| 4 | **CZLAB** | 2 GB | FAT32, no drive letter. Clonezilla Live 3.3.3-37 + `lab/lab.sh` + `lab/mode` |
| 5 | **Images** | 475 GB | Linux partition type, ext4 (formatted by the first save). Windows can't mount it |
| 6 | Windows Recovery | 0.9 GB | |

**Desktop: Lab** (run as admin):
- **Lab → `BACKUP`** (`SaveBaseline.ps1`; typing `SAVE` when run directly). Reboots into Clonezilla, which images C: to `lab-clean` (with SHA-1 checksums) and reboots back
  into Windows. The new image is saved as `lab-clean.new` and only replaces `lab-clean` once it succeeds; the old one is kept as `lab-clean.prev`.
  It refuses to run while GoDark is active.
- **Lab → `RESTORE`** (`RestoreLab.ps1`). Reboots into Clonezilla, which checks the checksums, restores `lab-clean` over C:, and reboots
  back into Windows. **Everything on C: since the baseline is lost**, including `C:\RE\dev`, so push your work first.

**How it works:**
- `LabBoot.ps1` writes `save` or `restore` to `lab/mode` on CZLAB (mounting it briefly), then sets a **one-time** firmware boot
  (`bcdedit /set {fwbootmgr} bootsequence <id>`) to the "Lab Clonezilla" entry and reboots. Windows stays first in the normal boot order.
- The CZLAB GRUB menu defaults to the `lab-auto` entry (5-second timeout). That entry boots Clonezilla with
  `ocs_live_batch="yes" ocs_live_run="bash /run/live/medium/lab/lab.sh"`.
- `lab.sh` finds the partitions by GPT partition GUID, runs `ocs-sr -b ... saveparts` or `ocs-sr -b -cs ... restoreparts`
  on C: only, sets the mode back to `restore` after a save, and reboots. If anything fails, it says so on screen and reboots after 10 minutes.

**To rebuild it:**
1. Shrink C: (`Resize-Partition -DriveLetter C -Size 476GB`). Create a 2 GB basic-data partition, format it
   FAT32 with the label `CZLAB`, and run `Set-Partition -NoDefaultDriveLetter $true`. Create the remaining space with
   `-GptType '{0fc63daf-8483-4772-8e79-3d69d8477de4}'` (Linux) and leave it unformatted.
2. Extract `clonezilla-live-3.3.3-37-amd64.zip` (SHA-256
   `bbb02b409708cf37774debe00f96c642c59c48ebb216f7349dc2252f705ff10e`) onto CZLAB. Copy `clonezilla/lab.sh` to
   `lab\lab.sh` with LF line endings, **after updating the two partition GUIDs** from `Get-Partition`. Create `lab\mode`
   containing `restore`.
3. In `boot\grub\grub.cfg`: copy the `live-default` entry as `--id lab-auto` with the parameters above
   (`locales=en_US.UTF-8 keyboard-layouts=us`), put it first, and set `default="lab-auto"` and `timeout="5"`.
4. Add the firmware entry: back up first (`bcdedit /export`), then
   `bcdedit /copy {bootmgr} /d "Lab Clonezilla"` → `bcdedit /set <id> device partition=<CZLAB letter>:` →
   `bcdedit /set <id> path \EFI\boot\bootx64.efi` → `bcdedit /set {fwbootmgr} displayorder <id> /addlast`.
   Secure Boot is off on this machine. If it's on, the firmware has to trust the Microsoft 3rd-party UEFI CA.
5. Copy `scripts\LabBoot.ps1`, `SaveBaseline.ps1` and `RestoreLab.ps1` to `C:\RE\scripts\` along with `Lab.ps1` and `Menu.ps1`, and create the shortcuts as in section 5.

### Evidence partition (E:)

RestoreLab rolls back all of C:, and that includes the REMnux VM in `C:\RE\vms`. That's deliberate: REMnux comes back
clean too. Anything you want to **keep** from a detonation goes on **E:**, which restores never touch:
- `E:\samples\`: samples waiting to be run. Defender will quarantine them unless you exclude the folder or turn Defender off while dark.
- `E:\cases\<name>\`: Procmon logs, dropped files, notes, and so on.
- `E:\remnux\`: shared into REMnux as `/mnt/evidence` (VMware shared folder `evidence`, mounted at boot through
  `/etc/fstab` with `fuse.vmhgfs-fuse`). Save pcaps and INetSim logs there.

Malware running on Windows *can* reach E:, so it can tamper with evidence. It can't reach the clean image.

**Backing E: up to a USB drive** (desktop **Evidence** menu, no admin needed):
- **Evidence → `BACKUP`** (`scripts\BackupEvidence.ps1 [-Drive F]`): copies all of E: to `<USB>:\EvidenceBackup\yyyy-MM-dd_HHmm`,
  keeping folders, timestamps and attributes. Every run is a new dated folder, so older copies are never overwritten. It checks
  that every file arrived with the same size; the log goes to `EvidenceBackup\backup-log.txt`.
- **Evidence → `RESTORE`** (`scripts\RestoreEvidence.ps1`): pick a backup (newest first), then **EXACT** (E: becomes identical,
  extra files on E: are deleted) or **MERGE** (copy the backup over E:, keep everything else). It checks every file afterwards.
- Both refuse while GoDark is active (`-Force` overrides), and both share `UsbDrive.ps1`.
- Defender, here or on another PC, may quarantine malware samples during a copy. The scripts then report those files as failed.

To rebuild it: `Resize-Partition -DriveLetter C -Size 426GB`, then
`New-Partition -DiskNumber 0 -UseMaximumSize -DriveLetter E` and format it NTFS with the label `Evidence`. Then
`vmrun enableSharedFolders` + `vmrun addSharedFolder <vmx> evidence E:\remnux`, run `remnux/evidence-share.sh`
inside REMnux, and **run SaveBaseline**: an image of the old, larger C: can't be restored into a smaller partition.

Same-disk caveat: malware with admin rights can still wipe or encrypt the image partition (or CZLAB). A USB copy is only
exposed if it's plugged in while infected Windows is running. Plugging it in only while booted into
Clonezilla keeps it out of reach; a drive with a hardware write-protect switch is better still.

## Gotchas

- `ovftool` import → `virtualhw.version = "99"` → "hardware version not supported". Set it to 21.
- WFC blocks `curl.exe`/`git` by default; allow them in WFC when you need them.
- Scripts run by the desktop shortcuts use **Windows PowerShell 5.1**. In 5.1, `Get-Content -Raw` strings
  serialize through `ConvertTo-Json` as objects, not plain strings. That broke the Wi-Fi vault once;
  `WifiVault.ps1` uses `[IO.File]::ReadAllText`.
- Scripts copied into REMnux need **LF** line endings.
- `netsh wlan show interfaces` needs Location permission; `netsh wlan show profiles` doesn't.
