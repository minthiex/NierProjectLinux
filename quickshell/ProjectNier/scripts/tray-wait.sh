#!/bin/bash
# usage: tray-wait.sh <command...>   (login autostart of tray apps such as KeePassXC)
# Starts the command once the tray (org.kde.StatusNotifierWatcher, run by the shell) exists, at most 30 s later.
# Started before it, a "minimize to tray" app has nowhere to go and shows its window full screen instead.
for i in $(seq 60); do
  busctl --user status org.kde.StatusNotifierWatcher >/dev/null 2>&1 && break
  sleep 0.5
done
exec "$@"
