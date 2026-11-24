#!/bin/bash
# usage: kill-tree.sh <pid>   ends a process and everything it started (TERM first, then KILL)
pid="$1"
case "$pid" in ''|*[!0-9]*) exit 1;; esac
name=$(ps -o comm= -p "$pid" 2>/dev/null)
case "$name" in Hyprland|systemd|sddm*|qs|quickshell|dbus*|pipewire*|wireplumber) echo "refusing to kill $name" >&2; exit 2;; esac

tree() { echo "$1"; for c in $(pgrep -P "$1"); do tree "$c"; done; }
pids=$(tree "$pid")
for p in $pids; do kill -TERM "$p" 2>/dev/null; done
for i in 1 2 3 4 5 6; do
  sleep 0.25
  alive=0
  for p in $pids; do kill -0 "$p" 2>/dev/null && alive=1; done
  [ "$alive" = 0 ] && exit 0
done
for p in $pids; do kill -KILL "$p" 2>/dev/null; done
