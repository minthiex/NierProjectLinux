#!/bin/bash
# usage: term.sh <slug> <tab title> <number of kitty options> <option>... [command...]
# Every sub-function has its own themed kitty window (title "projectnier-term:<slug>").
# If it already exists, a command opens as a new tab in it (a plain terminal request
# just leaves it where it is).
slug="$1"; title="$2"; n="$3"; shift 3
opts=("${@:1:$n}")
cmd=("${@:$((n+1))}")
sock="${XDG_RUNTIME_DIR:-/tmp}/projectnier-term-$slug.sock"

if kitty @ --to "unix:$sock" ls >/dev/null 2>&1; then
  if [ ${#cmd[@]} -gt 0 ]; then
    kitty @ --to "unix:$sock" launch --type=tab --tab-title "$title" "${cmd[@]}" >/dev/null 2>&1
  fi
  exit 0
fi

rm -f "$sock"
base=(kitty --class projectnier-term --listen-on "unix:$sock" -o allow_remote_control=socket-only -o inactive_text_alpha=1 -o dim_opacity=1 --title "projectnier-term:$slug")
if [ ${#cmd[@]} -gt 0 ]; then
  exec "${base[@]}" "${opts[@]}" -e "${cmd[@]}" >/dev/null 2>&1
else
  exec "${base[@]}" "${opts[@]}" >/dev/null 2>&1
fi
