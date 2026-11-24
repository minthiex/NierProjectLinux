#!/bin/bash
# prints {"<appid>": "<game name>", ...} for every installed Steam game (all library folders)
steam="$HOME/.local/share/Steam"
libs=$( { echo "$steam"; grep -oP '"path"\s+"\K[^"]+' "$steam/steamapps/libraryfolders.vdf" 2>/dev/null; } | sort -u)
for l in $libs; do
  for f in "$l"/steamapps/appmanifest_*.acf; do
    [ -e "$f" ] || continue
    id=$(grep -oP '^\s*"appid"\s+"\K[0-9]+' "$f" | head -1)
    name=$(grep -oP '^\s*"name"\s+"\K[^"]+' "$f" | head -1)
    [ -n "$id" ] && [ -n "$name" ] && jq -cn --arg k "$id" --arg v "$name" '{($k): $v}'
  done
done | jq -cs 'add // {}'
