#!/bin/bash
# usage: block-window.sh <window address without 0x>
# Closes a window that opened outside the content window and prints one JSON line about the program behind it:
# {"cmd": command to start it again, "name": app name, "title": window title}  (see app-info.py)
# A process that owns other windows is left alone (only this window is closed).
addr="0x$1"
win=$(hyprctl clients -j | jq -c --arg a "$addr" '.[] | select(.address==$a) | {pid, class, title}')
pid=$(printf '%s' "$win" | jq -r '.pid // empty')
[ -z "$pid" ] && exit 0
n=$(hyprctl clients -j | jq --argjson p "$pid" '[.[] | select(.pid==$p)] | length')
cls=$(printf '%s' "$win" | jq -r '.class')
python3 -I "$(dirname "$0")/app-info.py" "$pid" "$cls" 2>/dev/null | jq -c --arg t "$(printf '%s' "$win" | jq -r '.title')" '. + {title: $t}'

hyprctl dispatch "hl.dsp.window.close({ window = \"address:$addr\" })" >/dev/null 2>&1
if [ "$n" = 1 ]; then
  ( sleep 0.4; bash "$(dirname "$0")/kill-tree.sh" "$pid" ) >/dev/null 2>&1 &
fi
