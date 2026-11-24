#!/bin/sh
# usage: timer.sh <kind> <seconds> <message> [kitty options...]
# records the timer, then pops a small window when it ends
. "$(dirname "$0")/lib.sh"
kind="$1"; secs="$2"; msg="$3"; shift 3
due=$(( $(date +%s) + secs ))
printf '%s\t%s\t%s\n' "$due" "$kind" "$msg" >> "$D/timers.txt"
(
  sleep "$secs"
  printf '%s\t%s\t%s\n' "$(date '+%F %H:%M')" "$kind" "$msg" >> "$D/done.log"
  bash "$(dirname "$0")/term.sh" "popup-$kind" "$msg" "$#" "$@" sh -c 'clear; printf "\n  %s\n\n  press Enter to close" "$1"; read -r _' sh "$msg" >/dev/null 2>&1
  command -v notify-send >/dev/null && notify-send "$msg" >/dev/null 2>&1
) >/dev/null 2>&1 &
