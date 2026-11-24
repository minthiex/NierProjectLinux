#!/bin/bash
# SUPER+C: close the focused window, unless Claude Code is working in it.
# Then the first press only warns; a second press within 5 s closes it anyway.
win=$(hyprctl activewindow -j)
pid=$(jq -r '.pid // empty' <<<"$win"); addr=$(jq -r '.address // empty' <<<"$win")
[ -n "$addr" ] || exit 0
arm="${XDG_RUNTIME_DIR:-/tmp}/projectnier-busy/force-$addr"
if [ -n "$pid" ] && bash "$(dirname "$0")/busy.sh" pid "$pid"; then
  if [ ! -e "$arm" ] || [ $(( $(date +%s) - $(stat -c %Y "$arm") )) -gt 5 ]; then
    mkdir -p "${arm%/*}"; touch "$arm"
    notify-send -a ProjectNier -i dialog-warning "Claude is still working" "Press SUPER+C again within 5 seconds to close it anyway."
    exit 0
  fi
fi
rm -f "$arm"
hyprctl dispatch "hl.dsp.window.close({ window = \"address:$addr\" })" >/dev/null 2>&1
