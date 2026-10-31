# Assets

Microsoft's files are **not** in this repository. `payload/omarchy/vista/fetch-assets.sh`
downloads them on your machine, for your personal use, into
`~/.config/omarchy/vista/assets/` (and installs fonts, GTK theme, pointers and icons
under `~/.local/share`). They are Microsoft's copyrighted originals; this repository
holds only their URLs and sha256 pins. Nothing downloaded is ever executed: PE files
are parsed as bytes by `vistatool.py`.

## Source

Windows Vista **Business SP2**, build 6.0.6002.18005: the MSDN x86 DVD
(`en_windows_vista_sp2_x86_dvd_342266.iso`, 3 243 413 504 bytes, sha1
`25ad9a776503e6a583bec07879dbcc5dfd20cd6e`, the published MSDN value). The archive.org item
`en_windows_vista_sp2_x86_dvd_342266.zip` holds that DVD with `sources/install.wim`
already unpacked, and archive.org serves single members of it:

`https://archive.org/download/en_windows_vista_sp2_x86_dvd_342266.zip/en_windows_vista_sp2_x86_dvd.zip/sources%2Finstall%2F<path, URL-encoded>`

So only the files below are downloaded, about 90 MB. `--iso PATH` takes the same
files from a DVD image you have, `--from-iso` downloads the image (asks first,
resumable, verified against its sha1, deleted afterwards unless `--keep-iso`);
either way the same sha256 pins apply. (The ISO route needs `7zip` and `wimlib`; it
was implemented but not exercised, because it means a 3.2 GB download.)

### Checks that these are genuine Vista files

- PE FileVersion: explorer.exe, authui.dll, aero.msstyles, sidebar.exe are
  6.0.6002.18005 (lh_sp2rtm.090410-1830); batmeter.dll and imageres.dll 6.0.6000.16386
  (vista_rtm). `aero.theme`: `Wallpaper=img24.jpg`, `ColorizationColor=0x45409efe`.
- 18 of 19 sounds and the wallpapers checked are byte-identical (md5) to two
  independent archive.org uploads (`Microsoft_Windows-Vista-Default-sounds`,
  `windows-vista-wallpapers_202207`). The exception is `Windows Startup.wav` (38 KB),
  which is not the startup chime: Vista plays that from imageres.dll `WAVE/5051`,
  extracted here as `sounds/startup.wav` (880 684 bytes, 16-bit stereo 44.1 kHz).
- 43 files were pinned twice, independently (research run and pin run): identical.

## What is fetched (355 files)

| group | files |
|---|---|
| `binaries/` | 17 |
| `cursors/` | 39 |
| `fonts/` | 8 |
| `gadgets/` | 236 |
| `sounds/` | 19 |
| `wallpapers/` | 36 |

Fonts: Vista's four Segoe UI weights (regular, bold, italic, bold italic: Light and
Semibold first shipped with Windows 7) and Consolas. Sounds are renamed (e.g.
`Windows User Account Control.wav` -> `sounds/uac.wav`).

## Derived (pinned too)

| dest | method | from | what it is |
|---|---|---|---|
| `graphics/aero` | msstyles | `binaries/aero.msstyles` | the visual style, parsed: `props.json` (all 4364 properties), `parts.txt`, `image/<id>.png` (430 PNGs), `stream/850.png` (the DWM atlas), `parts/<class>/<part>.<state>.<prop>.png` (each image property, incl. the DWMWindow atlas rects cut out) |
| `sounds/startup.wav` | wave | `binaries/imageres.dll` 5051 | the Windows Vista startup chime |
| `graphics/explorer` | peres | `binaries/explorer.exe` BITMAP,PNGFILE | taskbar/notification-area previews, Start menu power/lock strips (7051-7056), arrows |
| `graphics/authui` | peres | `binaries/authui.dll` BITMAP,IMAGE,UIFILE | logon screen: user tile frames (11137-11142, 11158-11163), arrow buttons (11151-11156), power buttons (11124-11136), Ease of Access (11118), boot-orb frames (IMAGE 17000-17004), its DirectUI layouts (UIFILE 11000, 14000) |
| `graphics/authui-strings` | peres | `binaries/authui.dll.mui` STRING,DIALOG | logon screen strings and dialog |
| `graphics/consent-strings` | peres | `binaries/consent.exe.mui` STRING | UAC prompt strings |
| `graphics/basebrd` | peres | `binaries/basebrd.dll` BITMAP | "Windows Vista" branding bitmaps |
| `graphics/sidebar` | peres | `binaries/sidebar.exe` BITMAP,RCDATA | Sidebar art (RCDATA) |
| `graphics/batmeter` | peres | `binaries/batmeter.dll` BITMAP | notification-area battery meter strips (BITMAP 301-303) |
| `graphics/themecpl` | peres | `binaries/themecpl.dll` UIFILE,XML,BITMAP | Window Color and Appearance: its DirectUI layout (UIFILE 1002) and art |
| `graphics/themecpl-strings` | peres | `binaries/themecpl.dll.mui` STRING | the swatch names (STRING 101-108: Default ... Frost) |
| `graphics/imageres` | peres | `binaries/imageres.dll` IMAGE,PNG,BITMAP | logon background in 13 resolutions (IMAGE 5031-5043, JPEG), busy-ring strips (BITMAP 5000-5013) |
| `graphics/imageres-ico` | icons | `binaries/imageres.dll` 16,32,48,256 | every imageres.dll icon group at 16/32/48/256 (256 = Vista PNG entries) |
| `graphics/shell32-ico` | icons | `binaries/shell32.dll` 16,32,48,256 | shell32.dll icons, same sizes |
| `graphics/user32-ico` | icons | `binaries/user32.dll` 16,32,48 | message-box icons |
| `graphics/explorer-ico` | icons | `binaries/explorer.exe` 16,32,48,256 | explorer.exe icons |
| `graphics/consent-ico` | icons | `binaries/consent.exe` 16,32,48,256 | UAC shield icons |
| `icons/windows-vista-cursors` | xcursor | `cursors` | Xcursor theme: the Aero scheme (aero_*.cur/.ani at 24/36/48 nominal from 32/48/64 px art, animations at Vista's frame rates) plus user32's I-beam and crosshair (GROUP_CURSOR 101, 103), as in Vista's own scheme |
| `gtk/Windows-Vista` | gtk | `-` Windows-Vista-719b12bdb6f6dd352f7ca26ac2fd78ddc10efb8c | B00merang-Project/Windows-Vista @ 719b12bdb6f6 (GPL-3.0), tarball sha256 `6b08f59b9d39…`; installed as GTK theme "Windows Vista" |

`bin/vista-art` then converts the `.ico` trees to PNG and builds the `windows-vista`
icon theme from imageres.dll groups, ids identified on a contact sheet of the 48 px
icons: 3 folder, 4 folder-open, 2 unknown, 102 text, 90 document, 131/132/133
audio/image/video, 15 executable, 109 computer, 120 network, 25 server, 32 hard disk,
35 removable, 30 optical drive, 61 disc, 54/55 recycle bin empty/full, 51 printer,
95 scanner, 57 camera, 47 phone, 182 keyboard, 81/84/98/99 information/warning/error/
question, 106/107/105 security high/medium/low, 59 lock, 177 search, 88 users,
112/113/108/189/184 Documents/Pictures/Music/Videos/Downloads folders. Anything else
falls back to Adwaita.

## The msstyles format (Vista)

See the comment in `vistatool.py`. In short: CMAP = UTF-16 class names padded to 8
bytes; VARIANT `NORMAL` = records of an 8 x int32 header `<name type class part state
ref reserved size>` followed by `size` bytes padded to 8, except when `ref` is
non-zero (then the value is the reference: an IMAGE id for FILENAME properties, a MUI
string id for FONT ones) and nothing follows. Verified by parsing Vista SP2's
aero.msstyles end to end (4364 records, ending exactly on the last byte).
DWMWindow (the Aero glass frame and caption buttons) uses a single PNG atlas
(DISKSTREAM -> STREAM 850, 1199x774) with ATLASRECT (TMT 8002) per part.

## Scheme colours: sources

- **Aero (Default):** `aero.theme` ColorizationColor `0x45409EFE` (alpha 0x45);
  uDWM.dll falls back to the same value (`mov esi, 0x45409efe`).
- **Graphite / Frost:** not yet located in a file. themecpl.dll (the Window Color
  page) names the eight swatches (STRING 101-108) and lays them out (UIFILE 1002), but
  their values are not stored as data next to those ids; they are probably built in
  code. Interim source: a real Vista screenshot of the page
  (`.shots/refs/cxp-window-color-appearance.jpg`, CentrumXP 2007), each swatch sampled
  below its gloss (9x9 median): Default `#D7E9FF`, Graphite `#666666`, Blue `#6793EB`,
  Teal `#8ECCD6`, Red `#DF5D61`, Orange `#FFA556`, Pink `#FDBCF8`, Frost `#E9F1F3`.
  These are the swatches as drawn over white, not the stored ARGB, so they are
  approximate until the values are found in themecpl's code, or the sample is
  calibrated against Default, whose true value is known.
- **Vista Basic:** the opaque `Window` class parts of the same aero.msstyles.
