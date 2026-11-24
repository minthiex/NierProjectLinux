#!/bin/sh
# usage: idle.sh <lock|sleep> <delta-minutes|off|on>   edits ~/.config/projectnier/idle.json (0 = never)
f="$HOME/.config/projectnier/idle.json"
mkdir -p "$(dirname "$f")"
[ -f "$f" ] || echo '{"lock":10,"sleep":30}' > "$f"
k="$1"; v="$2"
cur=$(jq -r ".$k // 0" "$f")
case "$v" in
  off) new=0 ;;
  on) new=$([ "$k" = lock ] && echo 10 || echo 30) ;;
  *) new=$((cur + v)); [ "$new" -lt 1 ] && new=1; [ "$new" -gt 480 ] && new=480 ;;
esac
tmp=$(mktemp); jq ".$k = $new" "$f" > "$tmp" && mv "$tmp" "$f"
