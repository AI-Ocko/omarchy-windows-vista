# Windows Vista for Omarchy

The Windows Vista look for [Omarchy](https://omarchy.org) 4 (Quattro), in four
colour schemes: Aero (the default glass), Aero Graphite, Aero Frost and Vista
Basic (opaque, no blur: the battery-friendly one). It changes nothing else
about your desktop, and any non-Vista theme puts the previous look back
exactly.

> **Status: work in progress.** This version installs the four schemes, the
> cmd.exe console, the Vista window geometry, the apply/revert machinery, and
> downloads Vista's own files (visual style, fonts, sounds, wallpapers,
> pointers, icons, logon and Sidebar art). The Vista look built from them
> (Aero frames, taskbar, Start menu, logon screen) comes in later versions.

## Install

From a terminal in your Omarchy session, as yourself (not root):

```sh
./install.sh            # or: ./install.sh --dry-run  to see every step first
```

It asks for sudo only if a package it needs is missing, downloads
Microsoft's files (below, about 90 MB the first time), and ends on
`omarchy theme set windows-vista`. Open a new terminal afterwards.

Switch schemes like any Omarchy theme: `windows-vista`,
`windows-vista-graphite`, `windows-vista-frost`, `windows-vista-basic`.

**Update:** `git pull && ./install.sh` (safe to re-run).

**Uninstall:** `./uninstall.sh` switches to Omarchy's default theme, then
removes everything it installed in your account.

## Windows XP side by side

[omarchy-windows-xp](https://github.com/AI-Ocko/omarchy-windows-xp) can be
installed at the same time. The two share no files. Each one's theme hooks
undo it first when you leave it (`00-windows-*-off`) and apply it last when
you enter it (`zz-windows-*-on`), and each `on` turns the other off if it is
still on, so switching XP <-> Vista <-> anything else always restores the
right state. Uninstalling either leaves the other working.

## What it changes outside its own folders

- `~/.config/foot/foot.ini`, `~/.bashrc`, `~/.config/tmux/tmux.conf`: one
  marked block each (`# >>> omarchy-windows-vista`), with a `.pre-vista`
  backup.
- While a Vista theme is on: gsettings fonts (Segoe UI / Consolas at your
  current sizes), `~/.config/gtk-3.0/gtk.css` moved aside,
  `~/.config/gtk-4.0/gtk.css` linked to the scheme's palette (the folder is
  created if missing and removed again), a Hyprland toggle file with the
  Vista window geometry, and the tmux status bar. Leaving Vista puts every
  one of them back exactly (`~/.local/state/omarchy/vista/saved-state.json`).
- `~/.local/share/{fonts/vista, themes/Windows Vista, icons/windows-vista,
  icons/windows-vista-cursors}`.
- A `vista-sizes.path` systemd user unit that keeps the console font in step
  with `omarchy display text size`.

## Microsoft's files are not in this repository

`~/.config/omarchy/vista/fetch-assets.sh` (run by the installer) downloads
them on your machine, for your personal use, into
`~/.config/omarchy/vista/assets/`: individual files of a Windows Vista SP2
DVD from **archive.org** (or, with `--iso PATH`, from a DVD image you have),
and the B00merang Windows Vista GTK theme (GPL-3.0) from **GitHub**. They
are Microsoft's copyrighted originals pulled from a third-party archive.
Every download is pinned by sha256; a changed file fails the run instead of
being used, and nothing downloaded is ever executed. None of it is ever
committed here. Details: `ASSETS.md`.

## Licence

MIT (see `LICENSE`), including code copied from Omarchy (MIT) and from
omarchy-windows-xp (MIT). See `NOTICE.md`.
