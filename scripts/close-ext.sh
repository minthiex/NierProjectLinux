#!/bin/bash
# usage: close-ext.sh <address without 0x>...   closes content-window apps and ends their processes
# Chat apps that live in the tray (Discord, KeePassXC, Steam ...) only lose their window: the process keeps running.
keep='^(discord|vesktop|legcord|telegram-desktop|org\.telegram\.desktop|signal|signal-desktop|element|org\.keepassxc\.keepassxc|keepassxc|steam)$'
for a in "$@"; do
  addr="0x$a"
  info=$(hyprctl clients -j | jq -r --arg x "$addr" '.[] | select(.address==$x) | "\(.pid) \(.class)"')
  pid=${info%% *}; cls=${info#* }
  [ -z "$pid" ] && continue
  n=$(hyprctl clients -j | jq --argjson p "$pid" '[.[] | select(.pid==$p)] | length')
  hyprctl dispatch "hl.dsp.window.close({ window = \"address:$addr\" })" >/dev/null 2>&1
  if [[ "${cls,,}" =~ $keep ]]; then continue; fi
  if [ "$n" = 1 ]; then ( sleep 0.4; bash "$(dirname "$0")/kill-tree.sh" "$pid" ) >/dev/null 2>&1 & fi
done
