#!/bin/sh
# fm-go.sh ADDR PATH -- make the Dolphin window ADDR show PATH (its single tab changes folder)
# Dolphin has no "change folder" D-Bus call: open PATH as a new tab, then close the tab it replaces.
pid=$(hyprctl clients -j | jq -r --arg a "0x$1" '.[] | select(.address == $a) | .pid')
[ -n "$pid" ] || exit 1
svc="org.kde.dolphin-$pid"
case "$2" in /*) url="file://$2" ;; *) url="$2" ;; esac
call() { busctl --user call "$svc" "$@" >/dev/null 2>&1; }
act() { call "/dolphin/Dolphin_1/actions/$1" org.qtproject.Qt.Action trigger; }
open=$(busctl --user call "$svc" /dolphin/Dolphin_1 org.kde.dolphin.MainWindow isUrlOpen s "$url" 2>/dev/null)
call /dolphin/Dolphin_1 org.kde.dolphin.MainWindow openDirectories asb 1 "$url" false
case "$open" in *true*) exit 0 ;; esac
sleep 0.2
act activate_prev_tab; act file_close
