#!/bin/sh
# usage: clip.sh rows | copy <id> | wipe
# Clipboard history (Archive → Clipboard): cliphist keeps what was copied (the shell runs `wl-paste --watch cliphist
# store`, see shell.qml). Copies a password manager marks as secret (KeePassXC) are never stored: wl-paste reports
# them as CLIPBOARD_STATE=sensitive and cliphist skips those.
. "$(dirname "$0")/lib.sh"
self="sh $(q "$0")"
case "$1" in
rows)
  if ! command -v cliphist >/dev/null 2>&1; then row "CLIPHIST" "not installed: sudo pacman -S cliphist"; exit 0; fi
  n=$(cliphist list 2>/dev/null | wc -l)
  w=$(pgrep -x -f "wl-paste --watch cliphist store" >/dev/null && echo "recording" || echo "NOT RECORDING (restart the screen)")
  row "HISTORY" "$n entries  ·  $w"
  row "CLICK" "an entry to copy it again"
  blank
  cliphist list 2>/dev/null | head -40 | while IFS="$TAB" read -r id text; do
    case "$id" in *[!0-9]*|"") continue ;; esac
    t=$(printf '%s' "$text" | cut -c1-90)
    case "$text" in "[[ binary data"*) v="picture" ;; *) v="" ;; esac
    row "$t" "$v" "" "$self copy $id"
  done
  ;;
copy)
  case "$2" in *[!0-9]*|"") exit 1 ;; esac
  f=$(mktemp); trap 'rm -f "$f"' EXIT
  # decoded to a file first: a failed decode must not empty the clipboard
  cliphist decode "$2" > "$f" && [ -s "$f" ] && wl-copy < "$f" && notify-send -a "Clipboard" -t 1500 "Copied" "back on the clipboard"
  ;;
wipe)
  cliphist wipe
  ;;
*) echo "usage: clip.sh rows | copy <id> | wipe" >&2; exit 2 ;;
esac
