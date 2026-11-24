#!/bin/sh
# Screen recording via wf-recorder.  record.sh toggle|start|stop|area|status
. "$(dirname "$0")/lib.sh"
OUT="$HOME/Videos/Recordings"; PID="$D/record.pid"; CUR="$D/record.file"
running() { [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; }
note() { notify-send -a ProjectNier -u low "Screen Recording" "$1" 2>/dev/null; }
start() {
  running && return
  mkdir -p "$OUT"
  f="$OUT/$(date +%Y%m%d-%H%M%S).mp4"
  if [ "$1" = area ]; then g=$(slurp) || exit 0; set -- -g "$g"; else set --; fi
  echo "$f" > "$CUR"
  # system audio = monitor of the default output (music, videos ...)
  mon=$(pactl get-default-sink 2>/dev/null)
  [ -n "$mon" ] && set -- "$@" "--audio=$mon.monitor"
  wf-recorder "$@" -f "$f" >/dev/null 2>&1 &
  echo $! > "$PID"; date +%s > "$D/record.start"
  note "Recording started"
}
stop() {
  running || { rm -f "$PID"; return; }
  p=$(cat "$PID")
  kill -INT "$p"
  # wf-recorder finishes the file on SIGINT; if it hangs, end it after 5 s (and force it after 7 s)
  i=0
  while kill -0 "$p" 2>/dev/null; do
    sleep 0.1; i=$((i+1))
    [ "$i" = 50 ] && kill -TERM "$p" 2>/dev/null
    [ "$i" -ge 70 ] && { kill -KILL "$p" 2>/dev/null; break; }
  done
  rm -f "$PID" "$D/record.start"
  note "Saved $(basename "$(cat "$CUR")")"
}
case "$1" in
  start) start ;;
  area) start area ;;
  stop) stop ;;
  toggle) if running; then stop; else start; fi ;;
  status)
    if running; then e=$(( $(date +%s) - $(cat "$D/record.start") ))
      row "STATUS" "RECORDING"; row "ELAPSED" "$(printf '%02d:%02d:%02d' $((e/3600)) $((e%3600/60)) $((e%60)))"
    else row "STATUS" "IDLE"; fi
    row "FOLDER" "$OUT"
    blank
    mkdir -p "$OUT"
    ls -t "$OUT" | head -10 | while IFS= read -r f; do row "$f" "$(du -h "$OUT/$f" | cut -f1)" ; done
    ;;
esac
