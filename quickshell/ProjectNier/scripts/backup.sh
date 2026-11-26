#!/bin/sh
# usage: backup.sh rows | now | auto
# Daily copies of the settings that live outside the dotfiles repo (System → Backups), in ~/backups/auto/<date>/:
#   apps.json (sub-function assignments), Hyprland's local.lua and hyprland-gui.lua, idle.json, ~/.config/autostart.
# Logins are never copied (mail.json, session.json, the bridge data): ~/backups is a plain folder.
# The newest 14 are kept. `auto` (the shell runs it every hour) only makes one when the newest is over 20 hours old.
. "$(dirname "$0")/lib.sh"
root="$HOME/backups/auto"
keep=14

list() { ls -1d "$root"/20* 2>/dev/null | sort; }

make() {
  dest="$root/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$dest" && chmod 700 "$root" "$dest" || exit 1
  for f in "$D/apps.json" "$HOME/.config/hypr/local.lua" "$HOME/.config/hypr/hyprland-gui.lua" "$HOME/.config/projectnier/idle.json"; do
    [ -f "$f" ] && cp -p "$f" "$dest/"
  done
  [ -d "$HOME/.config/autostart" ] && cp -rp "$HOME/.config/autostart" "$dest/autostart"
  # the oldest go once there are more than $keep
  n=$(list | wc -l)
  [ "$n" -gt "$keep" ] && list | head -n $((n - keep)) | while IFS= read -r old; do rm -rf -- "$old"; done
  printf '%s\n' "$dest"
}

case "$1" in
now) make >/dev/null && notify-send -a "Backups" -t 3000 "Settings backed up" "~/backups/auto" ;;
auto)
  last=$(list | tail -n 1)
  if [ -z "$last" ] || [ -n "$(find "$last" -maxdepth 0 -mmin +1200 2>/dev/null)" ]; then make >/dev/null; fi ;;
rows)
  n=$(list | wc -l)
  last=$(list | tail -n 1)
  row "BACKUPS" "$n kept (the newest $keep)  ·  one a day, automatically"
  row "FOLDER" "$root"
  row "HOLDS" "apps.json, local.lua, hyprland-gui.lua, idle.json, autostart"
  row "NEVER" "logins and passwords (mail.json, Messenger session)"
  blank
  [ -z "$last" ] && row "NONE YET" "the first one is made within the hour"
  list | sort -r | while IFS= read -r b; do
    s=$(basename "$b")
    when=$(printf '%s' "$s" | sed -E 's/^(....)(..)(..)-(..)(..).*/\1-\2-\3 \4:\5/')
    row "$when" "$(ls -A "$b" | tr '\n' ' ')  $(du -sh "$b" | cut -f1)" "" "dolphin $(q "$b")"
  done ;;
*) echo "usage: backup.sh rows | now | auto" >&2; exit 2 ;;
esac
