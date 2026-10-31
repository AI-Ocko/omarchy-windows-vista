#!/bin/bash
# uninstall.sh [--dry-run] -- remove everything install.sh added, from this
# user's account. Packages and the boot splash need sudo, so for those it only
# prints the commands to run yourself.
#
#   --dry-run  print every action and the edit to each of your own files;
#              change nothing.
set -uo pipefail
shopt -s nullglob

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PAYLOAD=$HERE/payload
CFG=$HOME/.config
VISTA=$CFG/omarchy/vista
MARKER=$VISTA/.omarchy-windows-vista
BEGIN='# >>> omarchy-windows-vista'
END='# <<< omarchy-windows-vista'
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
DRY=0
case ${1:-} in
  --dry-run) DRY=1 ;;
  "") ;;
  *) echo "usage: ./uninstall.sh [--dry-run]" >&2; exit 2 ;;
esac

say() { printf '\n== %s\n' "$*"; }
warn() { printf 'uninstall.sh: %s\n' "$*" >&2; }
run() { printf '+ %s\n' "$*"; ((DRY)) || "$@"; }
# remove: rm -rf each path that exists; list the absent ones too.
remove() {
  local p
  for p in "$@"; do
    if [[ -e $p || -L $p ]]; then run rm -rf -- "$p"; else printf '  (absent) %s\n' "$p"; fi
  done
}

((EUID != 0)) || { warn "run this as yourself, not root"; exit 1; }
if [[ ! -e $MARKER ]]; then
  ((DRY)) || { warn "no $MARKER: this package is not installed here (or this is a source checkout); nothing removed"; exit 1; }
  warn "no $MARKER: a real run would stop here; listing what it would do anyway"
fi

# 1. Leave Vista the normal way first: a non-Vista theme runs `vista-mode off`, which
#    restores gsettings, shell.json (bar, plugins, disabledPlugins: the Vista
#    lock and polkit go, your own come back), the swapped files (and removes
#    a ~/.config/gtk-4.0 it created) and the Hyprland toggle.
say "Theme"
cur=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null)
# Leave Vista for Omarchy's default theme.
leave=tokyo-night
if [[ $cur == windows-vista || $cur == windows-vista-* ]]; then
  run omarchy theme set "$leave"
else
  echo "current theme is ${cur:-unknown}, not Vista: nothing to switch"
fi

say "Systemd user units"
run systemctl --user disable --now vista-sizes.path
remove "$CFG/systemd/user/vista-sizes.path" "$CFG/systemd/user/vista-sizes.service"
run systemctl --user daemon-reload

# 2. The marked blocks. The .pre-vista backup is deleted only when the file is
#    back to exactly what it was; otherwise it is kept and named.
say "Edits to your own files"
strip_block() {
  local file=$1 tmp
  [[ -e $file ]] && grep -qF "$BEGIN" "$file" || { echo "$file: no Vista block"; return 0; }
  tmp=$(mktemp)
  # install.sh put exactly one blank line above the block; drop that too.
  awk -v b="$BEGIN" -v e="$END" '
    { line[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) if (line[i] == b) { s = i; break }
      for (t = s; t <= NR && line[t] != e; t++);
      if (s > 1 && line[s - 1] == "") s--
      for (i = 1; i <= NR; i++) if (i < s || i > t) print line[i]
    }' "$file" >"$tmp"
  diff -u --label "$file (now)" --label "$file (without Vista)" "$file" "$tmp"
  if ((DRY)); then
    rm -f "$tmp"
    return 0
  fi
  cat "$tmp" >"$file" && rm -f "$tmp"
  if [[ -e $file.pre-vista ]]; then
    if cmp -s "$file" "$file.pre-vista"; then rm -f "$file.pre-vista"; else echo "$file differs from $file.pre-vista (edited since install); kept the backup"; fi
  fi
}
strip_block "$CFG/foot/foot.ini"
strip_block "$HOME/.bashrc"
strip_block "$CFG/tmux/tmux.conf"

# 3. The payload (the same list install.sh writes) and the user-level installs.
say "Files"
targets=()
for d in "$PAYLOAD"/omarchy/themes/* "$PAYLOAD"/omarchy/plugins/*; do targets+=("$CFG/omarchy/${d#"$PAYLOAD"/omarchy/}"); done
while IFS= read -r f; do targets+=("$CFG/omarchy/${f#"$PAYLOAD"/omarchy/}"); done < <(find "$PAYLOAD/omarchy/hooks" -type f)
remove "${targets[@]}"
# omarchy/vista last: it holds the marker, and Microsoft's downloaded files (assets/).
remove "$VISTA"
remove "$DATA/fonts/vista" "$DATA/themes/Windows Vista" "$DATA/icons/windows-vista" \
  "$DATA/icons/windows-vista-cursors" "${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-windows-vista" \
  "$HOME/.local/lib/hyprbars-vista" "$HOME/.local/state/omarchy/vista" \
  "$HOME/.local/state/omarchy/toggles/hypr/windows-vista.lua"
run fc-cache -f


say "Left for you"
echo "Nothing: this package installed no system packages of its own."

