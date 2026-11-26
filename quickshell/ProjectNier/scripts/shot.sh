#!/bin/sh
# usage: shot.sh area | window | screen
# Screenshot (Archive → Screenshots): saved to ~/Pictures/Screenshots and put on the clipboard as a picture.
#   area    drag a rectangle (slurp)
#   window  click one of the windows on screen (slurp offers their outlines)
#   screen  the whole monitor the pointer is on
. "$(dirname "$0")/lib.sh"
dir="$HOME/Pictures/Screenshots"
mkdir -p "$dir"
file="$dir/Screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"
# the colours of the selection, from Theme.qml (no hex literals in the QML; this script reads them like theme-*.py do)
theme="$(dirname "$0")/../Theme.qml"
col() { sed -n "s/.*property color $1: \"#\([0-9a-fA-F]\{6\}\)\".*/\1/p" "$theme" | head -1; }
ink=$(col ink); paper=$(col paper)
sl() {
  if [ -n "$ink" ] && [ -n "$paper" ]; then slurp -d -b "${paper}55" -c "${ink}ff" -s "${ink}22" -w 2 "$@"
  else slurp -d "$@"; fi
}

case "$1" in
area)   g=$(sl) || exit 0 ;;
window)
  # visible windows of the shown workspaces (not the hidden special ones), as "x,y wxh"
  # (workspaces by name: this Hyprland has no workspace id in its JSON; a special one counts while it is shown)
  boxes=$(hyprctl -j monitors | jq -r '[.[] | .activeWorkspace.name, .specialWorkspace.name | select(. != "")] | @json' | {
        read -r ws
        hyprctl -j clients | jq -r --argjson ws "$ws" '.[] | select(.hidden != true and (.workspace.name as $w | $ws | index($w)))
                                                        | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"'
      })
  # no window on screen (the content window may be hidden): drag an area instead
  if [ -n "$boxes" ]; then g=$(printf '%s\n' "$boxes" | sl -r) || exit 0; else g=$(sl) || exit 0; fi ;;
screen)
  mon=$(hyprctl -j monitors | jq -r '.[] | select(.focused) | .name')
  sleep 0.2 ;;
*) echo "usage: shot.sh area | window | screen" >&2; exit 2 ;;
esac

if [ "$1" = screen ]; then grim -o "$mon" "$file"; else grim -g "$g" "$file"; fi || { notify-send -a "Screenshot" "Screenshot failed"; exit 1; }
wl-copy --type image/png < "$file"
notify-send -a "Screenshot" -i "$file" "Screenshot saved" "$(basename "$file")  ·  also on the clipboard"
