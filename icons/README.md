# Desktop icons

Multi-size `.ico` files (16-256 px). On the machine they live in `C:\RE\tools\icons\`.

| Icon | Emoji | Source |
|---|---|---|
| `Fingerprint.ico` (Evidence) | 🫆 Fingerprint | Windows' Segoe UI Emoji font (the emoji-picker version), rendered with headless Edge on a transparent background |
| `Lab.ico` | ⚗️ Alembic | Fluent Emoji 3D |
| `WiFi.ico` | 🛜 Wireless | Fluent Emoji 3D |

Fluent Emoji 3D: https://github.com/microsoft/fluentui-emoji (MIT licence, Copyright (c) Microsoft Corporation).
The Fingerprint emoji (Unicode 16) isn't in the Fluent 3D set yet. To re-render it: put `&#x1FAC6;` in a 512x512
`div` with `font: 440px 'Segoe UI Emoji'`, run
`msedge --headless=new --window-size=512,512 --default-background-color=00000000 --screenshot=out.png page.html`,
then crop to the glyph and convert to `.ico`.

Windows caches shortcut icons by file path: to change an icon, give the new one a **new file name** (overwriting the
old file keeps showing the old picture), then refresh with `SHChangeNotify(SHCNE_ASSOCCHANGED)` or sign out and back in.
