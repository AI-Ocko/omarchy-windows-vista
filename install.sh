#!/bin/bash
# install.sh [--dry-run] -- install the Windows Vista theme into this user's
# Omarchy. Re-runnable: `git pull && ./install.sh` updates in place.
#
#   --dry-run  print every action and, for each edit to one of your own files,
#              the diff it would make; change nothing (no packages, no sudo, no
#              systemd, no theme switch, no downloads).
#
# Run it as yourself. It asks for sudo only for missing packages (pacman).
# Coexists with omarchy-windows-xp: no shared paths, and each package's theme
# hooks turn the other off before turning themselves on.
set -uo pipefail
shopt -s nullglob

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PAYLOAD=$HERE/payload
CFG=$HOME/.config
VISTA=$CFG/omarchy/vista
MARKER=$VISTA/.omarchy-windows-vista
BEGIN='# >>> omarchy-windows-vista'
END='# <<< omarchy-windows-vista'
STOCK=${OMARCHY_PATH:-/usr/share/omarchy}/config
SCHEMES=(windows-vista windows-vista-graphite windows-vista-frost windows-vista-basic)
DRY=0
case ${1:-} in
  --dry-run) DRY=1 ;;
  "") ;;
  *) echo "usage: ./install.sh [--dry-run]" >&2; exit 2 ;;
esac

say() { printf '\n== %s\n' "$*"; }
warn() { printf 'install.sh: %s\n' "$*" >&2; }
die() { warn "$*"; exit 1; }
# run: print a command, and run it unless this is a dry run.
run() { printf '+ %s\n' "$*"; ((DRY)) || "$@"; }

# ------------------------------------------------------------------ pre-flight
say "Pre-flight"
((EUID != 0)) || die "run this as yourself, not root; it asks for sudo itself"
command -v omarchy >/dev/null && [[ -d ${OMARCHY_PATH:-/usr/share/omarchy} ]] || die "Omarchy not found"
[[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && command -v hyprctl >/dev/null || die "run this inside a Hyprland session"
command -v foot >/dev/null || die "foot (Omarchy's terminal) not found"
echo "Omarchy $(omarchy version 2>/dev/null || echo '?'), $(hyprctl version -j | jq -r '"Hyprland " + .tag')"
if [[ -e $CFG/omarchy/xp/.omarchy-windows-xp ]]; then
  echo "omarchy-windows-xp is installed too: fine, the two take turns."
fi

plugins=("$PAYLOAD"/omarchy/plugins/ocko.vista-*)
if ((${#plugins[@]})); then
  echo "Compatibility of each Vista part with this Omarchy (failing parts fall back to stock):"
  python3 "$PAYLOAD/omarchy/vista/bin/vista-compat-test" --plugins "$PAYLOAD/omarchy/plugins" | sed 's/^/  /'
fi

# Every path this package installs. A path that already exists must be ours
# from an earlier run (the marker), or the install refuses to touch it.
targets=("$VISTA" "$CFG/systemd/user/vista-sizes.path" "$CFG/systemd/user/vista-sizes.service")
for d in "$PAYLOAD"/omarchy/themes/* "${plugins[@]}"; do targets+=("$CFG/omarchy/${d#"$PAYLOAD"/omarchy/}"); done
while IFS= read -r f; do targets+=("$CFG/omarchy/${f#"$PAYLOAD"/omarchy/}"); done < <(find "$PAYLOAD/omarchy/hooks" -type f)
foreign=()
for t in "${targets[@]}"; do
  [[ -e $t || -L $t ]] || continue
  if [[ ! -e $MARKER ]]; then
    foreign+=("$t")
  elif [[ $t == "$CFG"/omarchy/plugins/* ]] &&
    [[ $(jq -r '.id + " " + .author' "$t/manifest.json" 2>/dev/null) != "${t##*/} ocko" ]]; then
    foreign+=("$t (manifest is not this package's ${t##*/})")
  fi
done
if ((${#foreign[@]})); then
  printf '  not from this package: %s\n' "${foreign[@]}" >&2
  die "refusing to overwrite the files above; move them aside and re-run"
fi
echo "Install targets: ${#targets[@]}, none foreign."

# ------------------------------------------------------------------- packages
say "Packages"
PKGS=(jq python imagemagick curl libarchive fontconfig)
# sudo only for what is missing, so a re-run with everything present needs no
# password (and works from a session without a terminal).
mapfile -t missing < <(pacman -T "${PKGS[@]}")
if ((${#missing[@]} == 0)); then
  echo "all present: ${PKGS[*]}"
elif ((!DRY)) && [[ ! -t 0 ]] && ! sudo -n true 2>/dev/null; then
  die "packages to install (${missing[*]}) need sudo, and there is no terminal to ask for the password: run ./install.sh from a terminal"
else
  run sudo pacman -S --needed "${missing[@]}" || die "pacman failed"
fi

# ---------------------------------------------------------------------- files
say "Files"
# omarchy/vista and the themes are overlaid, so what was generated there
# (theme backgrounds/) survives an update. Plugin directories are replaced
# whole, so a file dropped upstream goes too.
run mkdir -p "$CFG/omarchy/themes" "$CFG/omarchy/plugins" "$CFG/systemd/user"
run cp -a "$PAYLOAD/omarchy/vista/." "$VISTA/"
for d in "$PAYLOAD"/omarchy/themes/*; do run mkdir -p "$CFG/omarchy/themes/${d##*/}"; run cp -a "$d/." "$CFG/omarchy/themes/${d##*/}/"; done
for d in "${plugins[@]}"; do run rm -rf "$CFG/omarchy/plugins/${d##*/}"; run cp -a "$d" "$CFG/omarchy/plugins/"; done
while IFS= read -r f; do
  rel=${f#"$PAYLOAD"/omarchy/}
  run mkdir -p "$(dirname "$CFG/omarchy/$rel")"
  run cp -a "$f" "$CFG/omarchy/$rel"
done < <(find "$PAYLOAD/omarchy/hooks" -type f)
run cp -a "$PAYLOAD/systemd/user/vista-sizes.path" "$PAYLOAD/systemd/user/vista-sizes.service" "$CFG/systemd/user/"
printf '+ write %s\n' "$MARKER"
((DRY)) || head -1 "$HERE/VERSION" >"$MARKER"
run systemctl --user daemon-reload
run systemctl --user enable --now vista-sizes.path

# A plain Aero-blue gradient as each scheme's wallpaper until Vista's own
# (img24) is fetched: generated here, never shipped.
for s in "${SCHEMES[@]}"; do
  bg=$CFG/omarchy/themes/$s/backgrounds
  [[ -n $(find "$bg" -maxdepth 1 -type f 2>/dev/null) ]] && continue
  run mkdir -p "$bg"
  run magick -size 1920x1200 gradient:'#1E5A9C'-'#0B2546' "$bg/placeholder.png"
done

# ------------------------------------------------------- assets and binaries
say "Microsoft's files (downloaded here, never shipped) and derived art"
# About 90 MB the first time (archive.org); reruns verify and skip. Also
# installs the fonts, the GTK theme, the pointers and the icon theme under
# ~/.local/share, and gives every scheme Vista's wallpapers.
run "$VISTA/fetch-assets.sh" || die "fetch-assets.sh failed (see above); nothing switched to Vista yet. Re-run ./install.sh to retry."

# ----------------------------------------------------------------- host edits
# Three of your own files get one marked block each, after a .pre-vista
# backup. A file that already has the block is left alone.
say "Edits to your own files"
# host_edit <file> <stock copy if the file is missing> <block> [<where>...]
#   where: after:<ERE> or before:<ERE>, tried in order; the block goes after /
#   before the first line matching ERE, and at the end if none matches.
# The block always gets exactly one blank line above it, which is what lets
# uninstall.sh take out "blank line + block" and restore the file exactly.
host_edit() {
  local file=$1 stock=$2 block=$3 tmp src w placed=0
  shift 3
  if [[ -e $file ]] && grep -qF "$BEGIN" "$file"; then
    echo "$file: already has the block, left alone"
    return 0
  fi
  src=$file
  if [[ ! -e $file ]]; then
    [[ -r $stock ]] || { warn "$file missing and no stock copy at $stock; skipped"; return 1; }
    src=$stock
    echo "$file: missing, created from $stock"
  fi
  tmp=$(mktemp)
  for w in "$@"; do
    grep -qE "${w#*:}" "$src" || continue
    # ENVIRON, not -v: awk -v would eat the backslashes in RE.
    RE=${w#*:} BLK=$block WHERE=${w%%:*} awk '
      !done && $0 ~ ENVIRON["RE"] {
        if (ENVIRON["WHERE"] == "after") print
        print ""; print ENVIRON["BLK"]; done = 1
        if (ENVIRON["WHERE"] == "after") next
      }
      { print }' "$src" >"$tmp"
    placed=1
    break
  done
  if ((!placed)); then
    (($#)) && warn "$file: no line matching ${*#*:}; block appended at the end"
    { cat "$src"; printf '\n%s\n' "$block"; } >"$tmp"
  fi
  diff -u --label "$file (now)" --label "$file (with Vista)" "$src" "$tmp"
  if ((DRY)); then
    rm -f "$tmp"
    return 0
  fi
  mkdir -p "$(dirname "$file")"
  [[ -e $file && ! -e $file.pre-vista ]] && cp -a "$file" "$file.pre-vista"
  cat "$tmp" >"$file" && rm -f "$tmp"
}

host_edit "$CFG/foot/foot.ini" "$STOCK/foot/foot.ini" "$BEGIN
# The theme's foot.ini again, last: later keys win, so the Windows Vista
# themes can set the font, cursor and title. Other themes only set colours,
# which nothing above sets, so they look exactly as before.
[main]
include=~/.local/state/omarchy/current/theme/foot.ini
$END"

# Interactive shells only, and above Omarchy's bash init: right after the
# interactive guard, else just above the rc source.
host_edit "$HOME/.bashrc" /etc/skel/.bashrc "$BEGIN
# Windows Vista theme: cmd.exe banner (a no-op under other themes).
[[ -r ~/.config/omarchy/vista/bashrc ]] && source ~/.config/omarchy/vista/bashrc
$END" 'after:^\[\[ \$- != \*i\* \]\] && return' 'before:^[[:space:]]*source .*default/bash/rc'

host_edit "$CFG/tmux/tmux.conf" "$STOCK/tmux/tmux.conf" "$BEGIN
# A theme may restyle the status bar with its own tmux.conf (the Windows
# Vista themes do). Sourced last so it wins; -q makes a theme without one a
# no-op.
source-file -q ~/.local/state/omarchy/current/theme/tmux.conf
$END"

# ------------------------------------------------------------------- activate
say "Switch to Windows Vista"
cur=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null)
scheme=windows-vista
[[ $cur == windows-vista-* ]] && scheme=$cur
run omarchy theme set "$scheme"

# ---------------------------------------------------------------- post-check
say "Check"
if ((DRY)); then
  echo "(dry run) would print: vista-mode status, hyprctl configerrors, the live Vista terminal font line"
  exit 0
fi
"$VISTA/bin/vista-mode" status
echo "hyprctl configerrors: $(hyprctl configerrors | tr -s '\n' ' ')"
grep -m1 '^font=' "$HOME/.local/state/omarchy/current/theme/foot.ini"
cat <<'MSG'

Done. Open a new terminal to see the Vista console (running ones keep their font).
MSG
