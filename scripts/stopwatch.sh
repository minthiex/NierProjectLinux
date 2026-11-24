#!/bin/sh
. "$(dirname "$0")/lib.sh"
case "$1" in
  start) [ -f "$D/stopwatch.start" ] || date +%s > "$D/stopwatch.start" ;;
  stop)  if [ -f "$D/stopwatch.start" ]; then e=$(( $(date +%s) - $(cat "$D/stopwatch.start") ))
           printf '%s\t%02d:%02d:%02d\n' "$(date '+%m-%d %H:%M')" $((e/3600)) $((e%3600/60)) $((e%60)) >> "$D/stopwatch.log"; rm -f "$D/stopwatch.start"; fi ;;
  reset) rm -f "$D/stopwatch.start" "$D/stopwatch.log" ;;
esac
