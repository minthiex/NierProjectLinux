#!/bin/bash
# usage: close-term.sh <slug>
# Closes a content window AND everything running in it (every tab, even programs that
# ignore a normal hang-up): ask nicely first, then force whatever is left.
slug="$1"
pid=$(hyprctl clients -j | jq -r --arg t "projectnier-term:$slug" '.[] | select(.title==$t) | .pid' | head -1)

tree() { # prints pid and all its descendants
  local p="$1"
  echo "$p"
  for c in $(pgrep -P "$p"); do tree "$c"; done
}

if [ -n "$pid" ]; then
  pids=$(tree "$pid")
  hyprctl dispatch "hl.dsp.window.close({ window = \"title:^projectnier-term:$slug\$\" })" >/dev/null 2>&1
  for p in $pids; do kill -TERM "$p" 2>/dev/null; done
  for i in 1 2 3 4 5 6; do
    sleep 0.25
    alive=0
    for p in $pids; do kill -0 "$p" 2>/dev/null && alive=1; done
    [ "$alive" = 0 ] && break
  done
  for p in $pids; do kill -KILL "$p" 2>/dev/null; done
else
  hyprctl dispatch "hl.dsp.window.close({ window = \"title:^projectnier-term:$slug\$\" })" >/dev/null 2>&1
fi
rm -f "${XDG_RUNTIME_DIR:-/tmp}/projectnier-term-$slug.sock"
