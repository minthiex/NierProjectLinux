#!/bin/bash
# usage: busy.sh pid <pid> | slug <slug>    exit 0 if Claude is working somewhere in that process tree
dir="${XDG_RUNTIME_DIR:-/tmp}/projectnier-busy"
if [ "$1" = slug ]; then
  pid=$(hyprctl clients -j | jq -r --arg t "projectnier-term:$2" '.[] | select(.title==$t) | .pid' | head -1)
else
  pid="$2"
fi
[ -n "$pid" ] || exit 1
tree() { echo "$1"; for c in $(pgrep -P "$1"); do tree "$c"; done; }
for p in $(tree "$pid"); do
  [ -e "$dir/$p" ] && [ "$(cat /proc/$p/comm 2>/dev/null)" = claude ] && exit 0
done
exit 1
