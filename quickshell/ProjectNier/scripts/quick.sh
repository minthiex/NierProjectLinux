#!/bin/sh
# usage: quick.sh state                    the Quick Settings toggles, one "key<TAB>value" line each
#        quick.sh wifi|bt|dnd|night|profile  flip one (profile: the next power profile)
# Volume and microphone are not here: QuickSettings.qml sets them through PipeWire directly.
. "$(dirname "$0")/lib.sh"
night_temp=4500

state() {
  printf 'wifi\t%s\n' "$(nmcli radio wifi 2>/dev/null | grep -q enabled && echo on || echo off)"
  p=$(bluetoothctl show 2>/dev/null | awk '/Powered:/{print $2; exit}')
  printf 'bt\t%s\n' "$( [ -z "$p" ] && echo none || { [ "$p" = yes ] && echo on || echo off; } )"
  printf 'dnd\t%s\n' "$( [ -f "$D/dnd" ] && echo on || echo off)"
  printf 'night\t%s\n' "$(pgrep -x hyprsunset >/dev/null && echo on || echo off)"
  printf 'profile\t%s\n' "$(powerprofilesctl get 2>/dev/null || echo none)"
}

case "$1" in
state) state ;;
wifi) nmcli radio wifi | grep -q enabled && nmcli radio wifi off || nmcli radio wifi on ;;
bt)
  if bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then bluetoothctl power off >/dev/null; else bluetoothctl power on >/dev/null; fi ;;
dnd) sh "$(dirname "$0")/toggle-dnd.sh" ;;
night)
  # warm screen colours (hyprsunset); off = the daemon is stopped and the screen goes back to normal
  if pgrep -x hyprsunset >/dev/null; then pkill -x hyprsunset
  else setsid hyprsunset -t "$night_temp" >/dev/null 2>&1 < /dev/null & fi ;;
profile)
  cur=$(powerprofilesctl get 2>/dev/null) || exit 0
  list=$(powerprofilesctl list 2>/dev/null | awk '/^[* ] [a-z-]+:/{gsub(/[*: ]/,""); print}')
  next=$(printf '%s\n' "$list" | awk -v c="$cur" 'NR==1{f=$0} p{print; found=1; exit} $0==c{p=1} END{if(!found) print f}')
  [ -n "$next" ] && powerprofilesctl set "$next" ;;
*) echo "usage: quick.sh state | wifi | bt | dnd | night | profile" >&2; exit 2 ;;
esac
