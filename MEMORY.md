# RE / Malware-Analysis Lab — Setup State

_Last updated: 2026-10-20. **Outdated:** see `README.md` for the current setup (bare-metal victim + REMnux)._

## What this machine is
Dedicated bare-metal box for **reverse engineering + malware-delivery-technique development** (no live payloads). **Live malware is only ever detonated inside VMs**, never on the host. Host stays clean, Defender ON (except the `C:\RE\dev` exclusion below).

## Host — DONE & verified ✅ (post-reboot)
- **Virtualization freed for VMware:** `HypervisorPresent=False`, `hypervisorlaunchtype=off`, VBS/HVCI/Credential Guard disabled. Reverse with `bcdedit /set hypervisorlaunchtype auto` + re-enable Memory Integrity, reboot. (WSL2 is OFF as a result.)
- **Defender:** RealTime + Tamper ON. **Exclusion added: `C:\RE\dev`** (keep only inert, self-authored code there — do not drop internet-sourced samples in it).
- **Explorer:** show file extensions + show hidden files enabled.
- **Windows Terminal:** updated 1.24 → 1.25 (fixed Shift+Enter). Claude Code `shift+enter`→newline binding in `~/.claude/keybindings.json`.

### Dev toolchain
Git 2.55 · Python 3.12.10 · .NET SDK 10 (+8) · Go 1.27 · Rust 1.99.1 (stable) · OpenJDK 21 · VS Code

### RE / analysis tools (in `C:\RE\tools`, key ones on PATH)
- Ghidra 12.1.4 → `C:\RE\tools\ghidra_12.1.4_PUBLIC\ghidraRun.bat`
- capa 10.0.0 (PATH) · FLOSS 3.2.0 → `C:\RE\tools\floss\floss.exe` (PATH)
- Sysinternals Suite (151 tools, PATH, EULAs accepted) → `C:\RE\tools\Sysinternals`
- x64dbg · PE-bear · HxD · Detect It Easy (`diec`) · YARA 4.5.5 · dnSpy (dnSpyEx) · Wireshark · 7-Zip · pestudio 9.61 (`C:\RE\tools\pestudio\pestudio\pestudio.exe`, SHA256-verified)
- **Python RE venv** `C:\RE\tools\revenv`: pefile, capstone, yara-python, oletools
  (FLOSS is standalone, not pip — `binary2strings` won't build without a C++ compiler)

### Layout
`C:\RE\tools` (tools) · `C:\RE\dev` (your projects, Defender-excluded) · `C:\RE\installers`

## VMware — DONE ✅
- **VMware Workstation Pro 26.0.0** (build 25388281) silent-installed (free personal use, telemetry/auto-update off). Services running (VMnetDHCP, NAT); adapters **VMnet1 = host-only** (use for isolated detonation net), **VMnet8 = NAT**. Shortcut in Desktop\RE Tools.

## Outbound firewall — DONE ✅ (Malwarebytes Windows Firewall Control)
- **Portmaster was tried and REMOVED** — too complex; caused DNS outages, invisible prompts, and a 127.0.0.1 captive-portal redirect on HTTPS. Uninstalled (kext gone). PortmasterCore service entry clears on reboot.
- **Windows Firewall Control (WFC) 6.36** (BiniSoft/Malwarebytes, free) installed and WORKING. Sits on Windows Firewall; gives the simple block-all + Allow/Block popup the user wanted.
  - Profile = **Medium** (blocks all outbound without a rule). Notifications = Display (per-app Allow/Block modal). Rules reviewable in WFC → Rules panel. Pause prompts = set profile to Low; resume = Medium.
  - ⚠️ **Install gotcha:** do NOT install WFC via `winget --silent` — it runs the setup with the current dir as CWD and dumps the app into `.\-update\` with a RELATIVE service path (broke, polluted the repo). Install by running `wfc6setup.exe` GUI (from binisoft.org; Malwarebytes-signed) → installs correctly to `C:\Program Files\Malwarebytes\Windows Firewall Control`.
  - pwsh.exe downloads: WFC will prompt for them; allow if needed.

## Optional tools — DONE ✅
- **CFF Explorer** (Explorer Suite, ntcore) → `C:\Program Files\NTCore\Explorer Suite\CFF Explorer.exe` (unsigned installer — normal for ntcore; SHA256 94F4348EC573B05990B1E19542986E46DC30A87870739F5D5430B60072D5144D).
- **IDA Free** — user installed manually. · **pestudio 9.61** — installed.
- Note: user ran **WinUtil** to disable Windows notifications; re-enabled toasts (ToastEnabled=1 + NOC_GLOBAL_SETTING_TOASTS_ENABLED=1) since Portmaster prompts depend on them. pwsh.exe allowed outbound in Portmaster for tool fetches.

## TODO — VM build (PARKED at user's request; do NOT start FLARE-VM yet)
After VMware install: FLARE-VM Windows guest + REMnux → isolated host-only network → clean baseline snapshots before any detonation.
