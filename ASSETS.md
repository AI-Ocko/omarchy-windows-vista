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

## What is fetched (385 files)

| group | files |
|---|---|
| `account-pictures/` | 13 |
| `binaries/` | 34 |
| `cursors/` | 39 |
| `fonts/` | 8 |
| `gadgets/` | 236 |
| `sounds/` | 19 |
| `wallpapers/` | 36 |

Account pictures: Vista's User Account Pictures (`ProgramData/Microsoft/User Account
Pictures`: Default Pictures usertile2-12, user, guest; usertile7 is the chess picture
used for the logon tile and the Start menu). Binaries added in Phase 4a: pnidui.dll
(network tray icons), SndVolSSO.dll (volume tray icons), bthprops.cpl (Bluetooth),
timedate.cpl (the clock flyout: clock face PNGFILE 5000-5007, layout UIFILE 305).
Added in Phase 4c, for the dialogs' real layouts (DIALOG templates live in
the .mui files): shell32.dll.mui (Run), mmsys.cpl + .mui (Sound),
SndVol.exe + .mui (Volume Mixer), netshell.dll + .mui (connection Status and
Details), bthprops.cpl.mui (Bluetooth), desk.cpl + .mui (Display), VAN.dll +
.mui and wlanpref.dll.mui (Connect to a network).

Fonts: Vista's four Segoe UI weights (regular, bold, italic, bold italic: Light and
Semibold first shipped with Windows 7) and Consolas. Sounds are renamed (e.g.
`Windows User Account Control.wav` -> `sounds/uac.wav`).

## Derived (pinned too)

| dest | method | from | what it is |
|---|---|---|---|
| `graphics/aero` | msstyles | `binaries/aero.msstyles` | the visual style, parsed: `props.json` (all 4364 properties), `parts.txt`, `image/<id>.png` (430 PNGs), `stream/850.png` (the DWM atlas), `parts/<class>/<part>.<state>.<prop>.png` (each image property, incl. the DWMWindow atlas rects cut out) |
| `sounds/startup.wav` | wave | `binaries/imageres.dll` 5051 | the Windows Vista startup chime |
| `graphics/explorer-res` | peres | `binaries/explorer.exe` BITMAP,PNGFILE | taskbar/notification-area previews, Start menu power/lock strips (7051-7056), arrows |
| `graphics/authui` | peres | `binaries/authui.dll` BITMAP,IMAGE,UIFILE | logon screen: user tile frames (11137-11142, 11158-11163), arrow buttons (11151-11156), power buttons (11124-11136), Ease of Access (11118), boot-orb frames (IMAGE 17000-17004), its DirectUI layouts (UIFILE 11000, 14000) |
| `graphics/authui-strings` | peres | `binaries/authui.dll.mui` STRING,DIALOG | logon screen strings and dialog |
| `graphics/consent-strings` | peres | `binaries/consent.exe.mui` STRING | UAC prompt strings |
| `graphics/basebrd` | peres | `binaries/basebrd.dll` BITMAP | "Windows Vista" branding bitmaps |
| `graphics/sidebar` | peres | `binaries/sidebar.exe` BITMAP,RCDATA | Sidebar art (RCDATA) |
| `graphics/batmeter` | peres | `binaries/batmeter.dll` BITMAP | notification-area battery meter strips (BITMAP 301-303) |
| `graphics/themecpl` | peres | `binaries/themecpl.dll` UIFILE,XML,BITMAP | Window Color and Appearance: its DirectUI layout (UIFILE 1002) and art |
| `graphics/themecpl-strings` | peres | `binaries/themecpl.dll.mui` STRING | the swatch names (STRING 101-108: Default ... Frost) |
| `graphics/imageres-res` | peres | `binaries/imageres.dll` IMAGE,PNG,BITMAP | logon background in 13 resolutions (IMAGE 5031-5043, JPEG), busy-ring strips (BITMAP 5000-5013) |
| `graphics/imageres-ico` | icons | `binaries/imageres.dll` 16,32,48,256 | every imageres.dll icon group at 16/32/48/256 (256 = Vista PNG entries) |
| `graphics/shell32-ico` | icons | `binaries/shell32.dll` 16,32,48,256 | shell32.dll icons, same sizes |
| `graphics/user32-ico` | icons | `binaries/user32.dll` 16,32,48 | message-box icons |
| `graphics/explorer-ico` | icons | `binaries/explorer.exe` 16,32,48,256 | explorer.exe icons |
| `graphics/consent-ico` | icons | `binaries/consent.exe` 16,32,48,256 | UAC shield icons |
| `graphics/pnidui-ico` | icons | `binaries/pnidui.dll` 16,32,48 | network tray icons (3020-3026 wireless/disconnected, 3048 wired) |
| `graphics/sndvolsso-ico` | icons | `binaries/sndvolsso.dll` 16,32,48 | volume tray icons (120 muted, 122-124 levels) |
| `graphics/bthprops-ico` | icons | `binaries/bthprops.cpl` 16,32,48 | Bluetooth icon (151) |
| `graphics/timedate` | peres | `binaries/timedate.cpl` PNGFILE,UIFILE | clock flyout: analog clock face and glass (5000-5007), flyout layout (305) |
| `graphics/startmenu-power` | rgbastrip | `binaries/explorer.exe` BITMAP 7051-7056 | Start-menu footer segments, 6 frames each (0 X, 1 shut down, 2 shut down + updates, 3 sleep, 4 busy, 5 lock): 24 px 7051 normal / 7053 hot / 7052 pressed, 30 px 7054 / 7056 / 7055 |
| `graphics/shell32-strings` | peres | `binaries/shell32.dll.mui` STRING,DIALOG | Run dialog (DIALOG 1003) |
| `graphics/mmsys-strings` | peres | `binaries/mmsys.cpl.mui` STRING,DIALOG | Sound: Playback 110, Recording 111 |
| `graphics/mmsys-ico` | icons | `binaries/mmsys.cpl` 16,32,48 | device icons (3010 speakers, 3011 headphones, 3014 microphone, 3015 headset, 3017 display) |
| `graphics/sndvol-strings` | peres | `binaries/sndvol.exe.mui` STRING,DIALOG | Volume Mixer (DIALOG 200) |
| `graphics/sndvol-ico` | icons | `binaries/sndvol.exe` 16,32,48 | mixer window icon |
| `graphics/netshell-strings` | peres | `binaries/netshell.dll.mui` STRING,DIALOG | Status 24050/24100, Details 24300 |
| `graphics/netshell-ico` | icons | `binaries/netshell.dll` 16,32,48 | connection and activity icons |
| `graphics/bthprops-strings` | peres | `binaries/bthprops.cpl.mui` STRING,DIALOG | Bluetooth Options (135) and pages |
| `graphics/desk-strings` | peres | `binaries/desk.cpl.mui` STRING,DIALOG | Display (Background page only) |
| `graphics/desk-ico` | icons | `binaries/desk.cpl` 16,32,48 | Display icon |
| `graphics/desk-res` | peres | `binaries/desk.cpl` BITMAP,PNGFILE | desk.cpl bitmaps (reference; unused) |
| `graphics/van-res` | peres | `binaries/van.dll` BITMAP,PNGFILE,UIFILE | VAN art (reference) |
| `graphics/van-strings` | peres | `binaries/van.dll.mui` STRING,DIALOG,UIFILE | Connect to a network (DIALOG 7111) |
| `graphics/van-ico` | icons | `binaries/van.dll` 16,32,48 | network icons |
| `graphics/wlanpref-strings` | peres | `binaries/wlanpref.dll.mui` STRING,DIALOG | wireless profile dialogs |
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

## Wallpapers in each scheme

fetch-assets.sh links every official wallpaper into each scheme's
`backgrounds/` (links into `assets/wallpapers/`, named
`NN-<scheme>-<group>-imgK.jpg`), grouped as Vista's Desktop Background
picker grouped them (the group is each JPEG's XMP `dc:subject`): Aurora
(img36) first, then Black and White (img1-4), Light Auras (img25-29),
Paintings (img12-15), Textures (img5-11), Vistas (img16-23). Frost puts
Light Auras before Black and White. The two Windows Ultimate wallpapers
(below) follow the official groups. The DVD's Widescreen group (img30-36)
holds 16:10 copies of img10, 23, 5, 21, 19, 22 and 24; each replaces its
4:3 original in its group, so 29 unique wallpapers.

## Extra official wallpapers (not on the DVD)

Two wallpapers Microsoft published on its Windows Vista Ultimate team site
(windowsultimate.com, pages "(c)2007 Microsoft Corporation"), "Ultimate
Downloads" entries 166 and 169, each in its 16:10 size (the 4:3 and 30"
versions, entries 167/168/170/171, are the same designs). The files carry
XMP `dc:rights` "Microsoft Corporation 2007", keywords "Widescreen; Windows
Ultimate". Fetched from the archive.org item `windows-vista-ultimate-wallpaper`
(`Windows Vista Ultimate Wallpaper.zip`, sha256 1bc2cc85...e4cd48, members
UltimateStart_1920x1200.jpg / UltimateStrands_1920x1200.jpg), whose bytes
match the Wayback Machine's raw copies of the Microsoft site's own downloads
(the fallback URLs):

| file | sha256 | primary | Microsoft original (Wayback) |
|---|---|---|---|
| `wallpapers/windows-ultimate-start-1920x1200.jpg` | f5709f05...7c8c9e1 | archive.org zip member | web.archive.org/web/20070310162644id_/http://windowsultimate.com:80/files/folders/166/download.aspx |
| `wallpapers/windows-ultimate-strands-1920x1200.jpg` | 09610df4...0ee3 | archive.org zip member | web.archive.org/web/20070310162501id_/http://windowsultimate.com:80/files/folders/169/download.aspx |

Looked for and not used: the archive.org item
`windowsvistaultimateextraswallpaper` (img37-41: re-saved copies of the
above with altered XMP, plus a watermarked third-party photo); DreamScene
content (video only, no Microsoft stills); Microsoft launch or (PRODUCT)RED
wallpaper downloads (none found on microsoft.com captures); OEM and fan packs.

## Generated on this machine (not pinned, rebuilt from the pinned files)

Resource extractions that vista-art also writes icons beside live in
`graphics/<lib>-res` (explorer, imageres, desk, van), so the pinned trees stay
unchanged. `bin/vista-art` (run by fetch-assets.sh) cuts the pinned art into what the shell and
the title bars load: icon PNGs per library (`graphics/<lib>/<size>/<id>.png`), the
icon theme, caption art (`captions/glass|basic`), taskbar, orb and battery frames,
Start menu parts, the logon art (`logon/`: authui BITMAPs, basebrd 120 as
`brand.png`, imageres 5031-5043 backgrounds), `account-pictures/*.png`, the control
art for the widget library (`taskbar/widgets/`: Aero msstyles Button, Combobox,
Header, Progress, ScrollBar, Spin, TrackBar, Tab, Tooltip and the Basic Window
frame), and Vista icons under the XP icon names some ported windows still use.

`bin/vista-boot render` draws the Plymouth boot screen: no Microsoft bitmap is
used for the progress bar, which is reconstructed at 640x480 from
`commons-boot-screen-640.png` (outline, six blocks, row colours sampled) and
pixel-doubled; the footer is drawn with the fetched Segoe UI; the shutdown screen
uses imageres 5038 (the 16:9 logon background). Nothing is installed into
`/usr/share/plymouth` until `vista-boot install|on` is run.
