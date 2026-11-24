#!/bin/sh
# usage: info.sh <topic> [arg]   prints rows (see lib.sh)
. "$(dirname "$0")/lib.sh"
topic="$1"; arg="$2"
now=$(date +%s)
opt() { hyprctl getoption "$1" 2>/dev/null | sed -n '1s/^[a-z0-9 ]*: //p'; }
human() { awk -v s="$1" 'BEGIN{split("B KiB MiB GiB TiB",u," ");i=1;while(s>=1024&&i<5){s/=1024;i++}printf "%.1f %s",s,u[i]}'; }
timers() { # $1 = kind
  [ -f "$D/timers.txt" ] || return 0
  awk -F'\t' -v now="$now" -v k="$1" '$1>now && $2==k {r=$1-now; printf "%s\t%02d:%02d remaining\t\t\n", $3, int(r/60), r%60}' "$D/timers.txt"
}
case "$topic" in
# ----------------------------------------------------------- ENTERTAINMENT
apps)
  shift
  for a in "$@"; do
    label=${a%%|*}; rest=${a#*|}; cmd=${rest%%|*}; kind=${rest#*|}; bin=${cmd%% *}
    if command -v "$bin" >/dev/null 2>&1; then
      row "$label" "INSTALLED"      # not clickable: apps are only started from the "Open <app>" buttons
    else row "$label" "not installed"; fi
  done
  ;;
nowplaying)
  p=$(playerctl -l 2>/dev/null | head -1)
  if [ -n "$p" ]; then
    row "PLAYER" "$p"
    row "STATUS" "$(playerctl status 2>/dev/null)"
    row "TITLE" "$(playerctl metadata title 2>/dev/null)"
    row "ARTIST" "$(playerctl metadata artist 2>/dev/null)"
    row "ALBUM" "$(playerctl metadata album 2>/dev/null)"
  else row "NOTHING PLAYING" ""; fi
  ;;
gamelib)
  n=0
  dir=$(readlink -f "$HOME/.local/share/Steam/steamapps" 2>/dev/null)
  [ -d "$dir" ] || dir=$(readlink -f "$HOME/.steam/steam/steamapps" 2>/dev/null)
  [ -d "$dir" ] && for f in "$dir"/appmanifest_*.acf; do
    [ -f "$f" ] || continue
    name=$(grep -m1 '"name"' "$f" | sed 's/.*"name"[^"]*"\(.*\)".*/\1/')
    case "$name" in Proton*|Steam\ Linux\ Runtime*|Steamworks*) continue ;; esac
    id=$(basename "$f" .acf); id=${id#appmanifest_}
    row "$name" "Steam" "" "steam steam://rungameid/$id"; n=$((n+1))
  done
  [ -d "$HOME/Games" ] && for g in "$HOME/Games"/*; do [ -e "$g" ] && { row "$(basename "$g")" "Games folder" "" "xdg-open $(q "$g")"; n=$((n+1)); }; done
  [ "$n" = 0 ] && { row "NO GAMES FOUND" ""; row "LOOKED IN" "Steam library, ~/Games"; }
  ;;
record)
  if pgrep -x wf-recorder >/dev/null; then row "STATE" "RECORDING"; else row "STATE" "idle"; fi
  row "FOLDER" "$HOME/Videos/Recordings"
  mkdir -p "$HOME/Videos/Recordings"
  blank
  ls -t "$HOME/Videos/Recordings" 2>/dev/null | head -8 | while IFS= read -r f; do row "$f" "$(du -sh "$HOME/Videos/Recordings/$f" | cut -f1)" "" "xdg-open $(q "$HOME/Videos/Recordings/$f")"; done
  ;;
# ---------------------------------------------------------------- MISSIONS
todo)
  [ -f "$D/todo.txt" ] || : > "$D/todo.txt"
  n=0; open=0
  while IFS= read -r l; do
    n=$((n+1))
    case "$l" in "[x] "*) st="DONE";; *) st="OPEN"; open=$((open+1));; esac
    row "${l#??? }" "$st" "" "sh $(q "$(dirname "$0")/todo.sh") toggle $n"
  done < "$D/todo.txt"
  [ "$n" = 0 ] && row "NO ACTIVE TASKS" ""
  ;;
history)
  [ -f "$D/todo.txt" ] && grep '^\[x\] ' "$D/todo.txt" | sed 's/^\[x\] //' | awk '{printf "%s\tCOMPLETED\t\t\n",$0}'
  [ -f "$D/done.log" ] && tail -15 "$D/done.log" | tac | awk -F'\t' '{printf "%s\t%s\t\t\n",$3,$1}'
  [ -s "$D/todo.txt" ] || [ -s "$D/done.log" ] || row "NO RECORDS" ""
  ;;
calendar)
  row "TODAY" "$(date '+%A %d %B %Y')"
  row "WEEK / DAY" "$(date +%V) / $(date +%j)"
  blank
  cal | sed 's/^ *//' | awk 'NR>0 && length($0)>0 {printf "%s\t\t\t\n",$0}'
  ;;
reminders)
  [ -f "$D/timers.txt" ] && awk -F'\t' -v now="$now" '$1>now && $2=="remind" {r=$1-now; printf "%s\tin %dh %02dm\t\t\n",$3,int(r/3600),int((r%3600)/60)}' "$D/timers.txt"
  [ -f "$D/timers.txt" ] && awk -F'\t' -v now="$now" '$1>now && $2=="remind"' "$D/timers.txt" | grep -q . || row "NO SCHEDULED REMINDERS" ""
  ;;
notes)
  dir="$HOME/Notes"; mkdir -p "$dir"
  row "FOLDER" "$dir"
  row "FILES" "$(find "$dir" -maxdepth 2 -type f | wc -l)"
  blank
  ls -t "$dir" | head -14 | while IFS= read -r f; do row "$f" "$(date -r "$dir/$f" '+%Y-%m-%d %H:%M')" "" "term:micro $(q "$dir/$f")"; done
  ;;
memo)
  [ -f "$D/memo.txt" ] || : > "$D/memo.txt"
  row "MEMOS" "$(wc -l < "$D/memo.txt")"
  blank
  tail -14 "$D/memo.txt" | tac | awk -F'\t' '{printf "%s\t%s\t\t\n",$2,$1}'
  ;;
focus)
  if [ -f "$D/dnd" ]; then row "DO NOT DISTURB" "ON"; else row "DO NOT DISTURB" "OFF"; fi
  row "NOTIFICATIONS" "this screen draws them (top middle)"
  row "WHILE ON" "only critical notices are shown"
  ;;
timer-focus)
  r=$(timers focus); [ -n "$r" ] && printf '%s\n' "$r" || row "NO ACTIVE SESSION" ""
  row "COMPLETED TODAY" "$( [ -f "$D/done.log" ] && grep -c "^$(date +%F).*	focus	" "$D/done.log" || echo 0)"
  ;;
timer-countdown)
  r=$(timers countdown); [ -n "$r" ] && printf '%s\n' "$r" || row "NO ACTIVE COUNTDOWN" ""
  ;;
stopwatch)
  if [ -f "$D/stopwatch.start" ]; then
    s=$(cat "$D/stopwatch.start"); e=$((now-s))
    row "RUNNING" "$(printf '%02d:%02d:%02d' $((e/3600)) $((e%3600/60)) $((e%60)))"
  else row "STOPPED" ""; fi
  [ -f "$D/stopwatch.log" ] && { blank; row "LAST RESULTS" ""; tail -8 "$D/stopwatch.log" | tac | awk -F'\t' '{printf "%s\t%s\t\t\n",$1,$2}'; }
  ;;
daily)
  f="$D/daily-$(date +%F).txt"; [ -f "$f" ] || : > "$f"
  n=0
  while IFS= read -r l; do
    n=$((n+1))
    case "$l" in "[x] "*) st="DONE";; *) st="OPEN";; esac
    row "${l#??? }" "$st" "" "sh $(q "$(dirname "$0")/todo.sh") toggle-daily $n"
  done < "$f"
  [ "$n" = 0 ] && row "NO OBJECTIVES FOR TODAY" ""
  ;;
report)
  t=0; dn=0
  [ -f "$D/todo.txt" ] && { t=$(grep -c '^\[ \] ' "$D/todo.txt"); dn=$(grep -c '^\[x\] ' "$D/todo.txt"); }
  tot=$((t+dn)); p=0; [ "$tot" -gt 0 ] && p=$((dn*100/tot))
  row "TASKS" "$dn done / $tot total" "$p"
  row "MEMOS" "$( [ -f "$D/memo.txt" ] && wc -l < "$D/memo.txt" || echo 0)"
  row "NOTE FILES" "$(find "$HOME/Notes" -type f 2>/dev/null | wc -l)"
  row "FOCUS SESSIONS" "$( [ -f "$D/done.log" ] && grep -c '	focus	' "$D/done.log" || echo 0)"
  row "FOCUS TODAY" "$( [ -f "$D/done.log" ] && grep -c "^$(date +%F).*	focus	" "$D/done.log" || echo 0)"
  f="$D/daily-$(date +%F).txt"
  if [ -s "$f" ]; then a=$(grep -c . "$f"); b=$(grep -c '^\[x\] ' "$f"); row "DAILY OBJECTIVES" "$b / $a" "$((b*100/a))"; fi
  ;;
# ---------------------------------------------------------- COMMUNICATION
contacts)
  [ -f "$D/contacts.txt" ] || : > "$D/contacts.txt"
  [ -s "$D/contacts.txt" ] && awk -F'\t' '{printf "%s\t%s\t\t\n",$1,$2}' "$D/contacts.txt" || row "NO CONTACTS" ""
  ;;
calls) [ -s "$D/calls.txt" ] && tail -14 "$D/calls.txt" | tac | awk -F'\t' '{printf "%s\t%s\t\t\n",$2,$1}' || { row "NO CALL RECORDS" ""; row "NOTE" "calls are made in Discord; it keeps its own history"; } ;;
notifications)
  if busctl --user status org.freedesktop.Notifications >/dev/null 2>&1; then row "DAEMON" "running (this screen)"; else row "DAEMON" "not running"; fi
  row "DO NOT DISTURB" "$( [ -f "$D/dnd" ] && echo ON || echo OFF)"
  row "WHERE" "top middle, above windows"
  row "KINDS" "apps, Messenger, notify-send"
  ;;
signal)
  g=$(ip route | awk '/default/{print $3; exit}')
  l=$(ping -c1 -W2 ${g:-127.0.0.1} 2>/dev/null | awk -F'time=' '/time=/{print $2}')
  w=$(ping -c1 -W2 1.1.1.1 2>/dev/null | awk -F'time=' '/time=/{print $2}')
  row "GATEWAY" "${g:-none}"
  row "GATEWAY PING" "${l:-unreachable}"
  row "INTERNET PING" "${w:-unreachable}"
  d=$(getent hosts discord.com | head -1 | awk '{print $1}'); row "DISCORD DNS" "${d:-unresolved}"
  ;;
share)
  p="$HOME/Public"; mkdir -p "$p"
  row "SHARE FOLDER" "$p"
  row "FILES" "$(find "$p" -type f | wc -l)"
  row "LOCAL ADDRESS" "$(ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1 | head -1):8000"
  blank
  ls -t "$p" | head -10 | while IFS= read -r f; do row "$f" "$(du -sh "$p/$f" | cut -f1)" "" "xdg-open $(q "$p/$f")"; done
  ;;
# ---------------------------------------------------------------- ARCHIVE
dir)
  p="$arg"; [ -d "$p" ] || mkdir -p "$p"
  row "FOLDER" "$p"
  row "ITEMS" "$(ls -A "$p" | wc -l)"
  row "SIZE" "$(du -sh "$p" 2>/dev/null | cut -f1)"
  blank
  ls -At "$p" | head -12 | while IFS= read -r f; do
    # a folder opens in the file manager at that folder, an image in the viewer, anything else is selected in its folder
    case "$(file -b --mime-type "$p/$f")" in
      inode/directory) c="dolphin $(q "$p/$f")" ;;
      image/*) c="gwenview $(q "$p/$f")" ;;
      *) c="dolphin --select $(q "$p/$f")" ;;
    esac
    row "$f" "$(date -r "$p/$f" '+%Y-%m-%d')" "" "$c"
  done
  ;;
recent)
  find "$HOME" -xdev -type f -not -path '*/.*' -not -path "$HOME/backups/*" -printf '%T@\t%p\n' 2>/dev/null | sort -rn | head -14 | while IFS="$(printf '\t')" read -r t f; do
    row "$(basename "$f")" "$(date -d "@${t%.*}" '+%m-%d %H:%M')" "" "dolphin --select $(q "$f")"; done
  ;;
places)
  for d in Desktop Documents Downloads Music Pictures Videos Projects Notes Public Templates; do
    [ -d "$HOME/$d" ] && row "$d" "$(ls -A "$HOME/$d" | wc -l) items" "" "dolphin $(q "$HOME/$d")"
  done
  ;;
external)
  lsblk -rno NAME,SIZE,RM,MOUNTPOINT,FSTYPE | awk '$4 ~ /^\/(run\/media|mnt|media)/ || ($3==1 && $5!="") {printf "%s\t%s %s %s\t\t\n",$1,$2,$5,$4}' | head -12 | grep . || row "NO EXTERNAL STORAGE" ""
  ;;
trash)
  t="$HOME/.local/share/Trash/files"; mkdir -p "$t"
  row "ITEMS" "$(ls -A "$t" | wc -l)"
  row "SIZE" "$(du -sh "$t" 2>/dev/null | cut -f1)"
  blank
  ls -At "$t" | head -12 | while IFS= read -r f; do row "$f" "$(du -sh "$t/$f" | cut -f1)"; done
  ;;
compressed)
  find "$HOME/Downloads" "$HOME/Documents" "$HOME/Desktop" -maxdepth 2 -type f \( -name '*.zip' -o -name '*.tar*' -o -name '*.7z' -o -name '*.gz' -o -name '*.xz' -o -name '*.zst' -o -name '*.rar' \) -printf '%T@\t%s\t%p\n' 2>/dev/null | sort -rn | head -14 | while IFS="$(printf '\t')" read -r t s f; do
    row "$(basename "$f")" "$(human "$s")" "" "dolphin --select $(q "$f")"; done | grep . || row "NO ARCHIVES FOUND" ""
  ;;
# ---------------------------------------------------------------- NETWORK
wifi)
  row "RADIO" "$(nmcli radio wifi)"
  # --rescan no: read NetworkManager's cached list (it rescans in the background); a list older than 30 s would
  # otherwise make nmcli wait ~11 s for a fresh scan on every refresh. "Rescan Networks" scans on demand.
  c=$(nmcli -t -f ACTIVE,SSID dev wifi list --rescan no 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}')
  row "CONNECTED TO" "${c:-none}"
  blank
  # SSID goes last (it may contain colons); clicking a row connects, asking for the password in the themed terminal if needed
  nmcli --escape no -t -f SIGNAL,SECURITY,SSID dev wifi list --rescan no 2>/dev/null | awk -F: '{ssid=$3; for(i=4;i<=NF;i++) ssid=ssid":"$i; if(ssid=="") next; if(seen[ssid]++) next
    q=ssid; gsub(/\047/,"\047\\\047\047",q)
    printf "%s\t%s\t%s\tterm:nmcli --ask dev wifi connect \047%s\047; echo; printf \"press Enter\"; read -r _\n",ssid,$2==""?"open":$2,$1,q}' | head -12
  ;;
bluetooth)
  p=$(bluetoothctl show 2>/dev/null | awk '/Powered:/{print $2}')
  row "POWER" "${p:-unavailable}"
  row "DISCOVERABLE" "$(bluetoothctl show 2>/dev/null | awk '/Discoverable:/{print $2}')"
  blank
  bluetoothctl devices 2>/dev/null | while read -r _ mac name; do
    st=$(bluetoothctl info "$mac" 2>/dev/null | awk '/Connected:/{print $2}')
    if [ "$st" = yes ]; then row "$name" "CONNECTED" "" "bluetoothctl disconnect $mac"; else row "$name" "paired" "" "bluetoothctl connect $mac"; fi
  done
  ;;
ethernet)
  nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev status | awk -F: '$2=="ethernet" && $3!~/unmanaged/ {printf "%s\t%s %s\t\t\n",$1,$3,$4}'
  for i in $(ls /sys/class/net); do [ "$(cat /sys/class/net/$i/type 2>/dev/null)" = 1 ] && [ -d /sys/class/net/$i/device ] && [ ! -d /sys/class/net/$i/wireless ] && row "$i SPEED" "$(cat /sys/class/net/$i/speed 2>/dev/null) Mb/s"; done
  ;;
vpn)
  v=$(nmcli -t -f NAME,TYPE,DEVICE con show --active | awk -F: '$2~/vpn|wireguard/ {printf "%s\t%s\t\t\n",$1,$2}')
  [ -n "$v" ] && printf '%s\n' "$v" || row "NO ACTIVE VPN" ""
  blank; row "SAVED PROFILES" "$(nmcli -t -f TYPE con show | grep -cE 'vpn|wireguard')"
  ;;
netmon)
  # the rate since the last refresh (state in the runtime dir), instead of sleeping a second every time;
  # only the first look (or one after a long pause) takes a 1 s sample
  st="${XDG_RUNTIME_DIR:-/tmp}/projectnier-netmon"
  cnt() { awk '/:/ && $1!~/lo:|docker|br-|veth/ {rx+=$2; tx+=$10} END{print rx, tx}' /proc/net/dev; }
  now=$(date +%s%N); b=$(cnt)
  prev=$(cat "$st" 2>/dev/null)
  set -- $prev
  if [ $# -ne 3 ] || [ $(( (now - $1) / 1000000 )) -gt 10000 ] || [ $(( (now - $1) / 1000000 )) -lt 200 ]; then
    a=$(cnt); t0=$(date +%s%N); sleep 1; now=$(date +%s%N); b=$(cnt)
  else
    t0=$1; a="$2 $3"
  fi
  printf '%s %s\n' "$now" "$b" > "$st"
  ms=$(( (now - t0) / 1000000 )); [ "$ms" -lt 1 ] && ms=1
  set -- $a $b
  row "DOWNLOAD" "$(human $(( ($3 - $1) * 1000 / ms )))/s"
  row "UPLOAD" "$(human $(( ($4 - $2) * 1000 / ms )))/s"
  row "TOTAL DOWN" "$(human $3)"
  row "TOTAL UP" "$(human $4)"
  ;;
connstatus)
  row "STATE" "$(nmcli -t -f STATE general)"
  row "CONNECTIVITY" "$(nmcli -t -f CONNECTIVITY general)"
  nmcli -t -f NAME,DEVICE,TYPE con show --active | grep -v -E 'docker|br-|lo$' | awk -F: '{printf "%s\t%s (%s)\t\t\n",$1,$2,$3}'
  row "GATEWAY" "$(ip route | awk '/default/{print $3; exit}')"
  ;;
ip)
  ip -4 -br addr | grep -v -E '^(lo|docker|br-|veth)' | awk '{printf "%s\t%s\t\t\n",$1,$3}'
  row "PUBLIC" "$(curl -s --max-time 4 https://api.ipify.org || echo unavailable)"
  row "GATEWAY" "$(ip route | awk '/default/{print $3; exit}')"
  ;;
dns)
  resolvectl status 2>/dev/null | awk '/Current DNS Server:/{print "CURRENT\t"$4"\t\t"} /DNS Servers:/{sub(/.*DNS Servers: /,""); print "SERVERS\t"$0"\t\t"} /DNS Domain:/{sub(/.*DNS Domain: /,""); print "DOMAIN\t"$0"\t\t"}' | awk '!s[$0]++' | head -8
  grep -m3 nameserver /etc/resolv.conf | awk '{printf "RESOLV.CONF\t%s\t\t\n",$2}'
  ;;
firewall)
  row "UFW SERVICE" "$(systemctl is-active ufw 2>/dev/null)"
  row "NFTABLES SERVICE" "$(systemctl is-active nftables 2>/dev/null)"
  ;;
nearby)
  ip -4 neigh | grep -v -E 'FAILED|docker' | awk '{printf "%s\t%s %s\t\t\n",$1,$5,$6}' | head -14 | grep . || row "NO DEVICES SEEN" ""
  ;;
datausage)
  awk '/:/ && $1!~/lo:/ {gsub(":","",$1); printf "%s %s %s\n",$1,$2,$10}' /proc/net/dev | while read -r i rx tx; do [ "$rx" -gt 0 ] && row "$i" "down $(human $rx)  up $(human $tx)"; done
  ;;
# ---------------------------------------------------------- CONFIGURATION
wallpaper)
  row "SCREEN" "NieR paper (drawn by the shell)"
  row "FOLDER" "$HOME/Pictures/Wallpaper"
  blank
  ls -t "$HOME/Pictures/Wallpaper" 2>/dev/null | head -10 | while IFS= read -r f; do row "$f" "" "" "gwenview $(q "$HOME/Pictures/Wallpaper/$f")"; done
  ;;
theme)
  row "COLOR SCHEME" "$(gsettings get org.gnome.desktop.interface color-scheme | tr -d "'")"
  row "GTK THEME" "$(gsettings get org.gnome.desktop.interface gtk-theme | tr -d "'")"
  ;;
icon)
  row "ICON THEME" "$(gsettings get org.gnome.desktop.interface icon-theme | tr -d "'")"
  blank
  ls /usr/share/icons "$HOME/.local/share/icons" 2>/dev/null | grep -v -E '^$|:$|^default$|^hicolor$' | sort -u | head -12 | awk '{printf "%s\t\t\t\n",$0}'
  ;;
cursor)
  row "CURSOR THEME" "$(gsettings get org.gnome.desktop.interface cursor-theme | tr -d "'")"
  row "CURSOR SIZE" "$(gsettings get org.gnome.desktop.interface cursor-size)"
  ;;
fonts)
  row "UI FONT" "$(gsettings get org.gnome.desktop.interface font-name | tr -d "'")"
  row "MONO FONT" "$(gsettings get org.gnome.desktop.interface monospace-font-name | tr -d "'")"
  row "SHELL FONT" "JetBrainsMono Nerd Font"
  row "FAMILIES INSTALLED" "$(fc-list : family | sort -u | wc -l)"
  ;;
shellcfg)
  row "SHELL" "Quickshell, config ProjectNier"
  row "FOLDER" "$HOME/.config/quickshell/ProjectNier"
  row "PROCESS" "$(pgrep -x qs >/dev/null && echo running || echo stopped)"
  blank
  ls "$HOME/.config/quickshell/ProjectNier" | grep -E '\.qml$' | awk '{printf "%s\t\t\t\n",$0}'
  ;;
hyprland)
  row "VERSION" "$(hyprctl version -j 2>/dev/null | sed -n 's/.*"tag": "\([^"]*\)".*/\1/p' | head -1)"
  row "MONITOR" "$(hyprctl monitors | awk '/^Monitor/{print $2}' | head -1)"
  row "CONFIG ERRORS" "$(hyprctl configerrors | grep -c .)"
  row "WINDOWS" "$(hyprctl clients | grep -c '^Window')"
  ;;
animations)
  row "ANIMATIONS" "$( [ "$(opt animations:enabled)" = true ] && echo ON || echo OFF)"
  row "WINDOW BORDER" "$(opt general:border_size) px"
  ;;
winrules)
  grep -E '^\s*name\s*=' "$HOME/.config/hypr/hyprland.lua" | sed 's/.*"\(.*\)".*/\1/' | awk '{printf "%s\t\t\t\n",$0}' | head -14
  ;;
binds)
  grep -E '^\s*(local [a-zA-Z]+ = )?hl\.bind\(' "$HOME/.config/hypr/hyprland.lua" | sed -E 's/^\s*(local [a-zA-Z]+ = )?hl\.bind\(//' | sed -E 's/mainMod \.\. " \+ /SUPER+/; s/^"//; s/", hl\.dsp\.(.*)$/\t\1/' | awk -F'\t' '{x=$2; sub(/\)$/,"",x); printf "%s\t%s\t\t\n",$1,substr(x,1,40)}' | grep -v -E 'XF86|mouse' | head -16
  ;;
notifstyle)
  row "DAEMON" "$(busctl --user status org.freedesktop.Notifications >/dev/null 2>&1 && echo running || echo not running)"
  row "STYLE" "NieR: dark title bar, paper body"
  row "SHOWN" "up to 4 at once, top middle"
  row "CRITICAL" "accent red, stays until closed"
  ;;
lockscreen)
  row "LOCKER" "ProjectNier session lock (Lock.qml)"
  row "AUTH" "PAM (login)"
  row "LOCKED NOW" "$(LC_ALL=C.UTF-8 qs -c ProjectNier ipc call lock isLocked 2>/dev/null | tail -1)"
  ;;
transparency)
  row "BLUR" "$( [ "$(opt decoration:blur:enabled)" = true ] && echo ON || echo OFF)"
  row "BLUR SIZE" "$(opt decoration:blur:size)"
  row "BLUR PASSES" "$(opt decoration:blur:passes)"
  row "ACTIVE OPACITY" "$(opt decoration:active_opacity)"
  row "INACTIVE OPACITY" "$(opt decoration:inactive_opacity)"
  ;;
layout)
  row "GAPS IN" "$(opt general:gaps_in)"
  row "GAPS OUT" "$(opt general:gaps_out)"
  row "BORDER SIZE" "$(opt general:border_size)"
  row "ROUNDING" "$(opt decoration:rounding)"
  row "LAYOUT" "$(opt general:layout)"
  ;;
# ---------------------------------------------------------------- SYSTEM
display)
  hyprctl monitors | awk '/^Monitor/{n=$2} /at [0-9]+x[0-9]+$/{print n"\t"$1"\t\t"} /scale:/{print "SCALE\t"$2"\t\t"} /description:/{sub(/^[ \t]*description: /,""); print "MODEL\t"$0"\t\t"}'
  ;;
brightness)
  b=$(brightnessctl -m 2>/dev/null | grep -v -E 'leds|capslock|numlock|scrolllock' | head -1)
  if [ -n "$b" ]; then p=$(echo "$b" | cut -d, -f4 | tr -d %); row "BRIGHTNESS" "${p}%" "$p"; else row "BRIGHTNESS" "no controllable backlight"; row "NOTE" "this monitor is not on a backlight device"; fi
  ;;
audio)
  v=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
  if [ -n "$v" ]; then p=$(echo "$v" | awk '{printf "%d",$2*100}'); row "VOLUME" "${p}%$(echo "$v" | grep -q MUTED && echo ' (muted)')" "$p"; else row "VOLUME" "no default output"; fi
  row "OUTPUT" "$(pactl get-default-sink 2>/dev/null)"
  blank
  pactl list short sinks 2>/dev/null | awk '{print $2}' | while IFS= read -r k; do row "$k" "" "" "pactl set-default-sink $(q "$k")"; done
  ;;
mic)
  p=$(pactl get-source-volume @DEFAULT_SOURCE@ 2>/dev/null | grep -o '[0-9]*%' | head -1 | tr -d %)
  if [ -n "$p" ]; then m=$(pactl get-source-mute @DEFAULT_SOURCE@ | awk '{print $2}'); row "INPUT VOLUME" "${p}%$([ "$m" = yes ] && echo ' (muted)')" "$p"; else row "INPUT" "no input device"; fi
  row "DEVICE" "$(pactl get-default-source 2>/dev/null)"
  ;;
power)
  row "PROFILE" "$(powerprofilesctl get 2>/dev/null)"
  powerprofilesctl list 2>/dev/null | awk '/^[* ] [a-z-]+:/{gsub(/[*:]/,""); printf "AVAILABLE\t%s\t\t\n",$1}'
  row "CPU GOVERNOR" "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
  ;;
battery)
  b=$(upower -e 2>/dev/null | grep -i battery | head -1)
  if [ -n "$b" ]; then upower -i "$b" | awk '/state:|percentage:|time to|capacity:/{sub(/^ +/,""); sub(/: +/,"\t"); print $0"\t\t"}'; else row "BATTERY" "none (desktop machine)"; row "AC POWER" "online"; fi
  ;;
input)
  hyprctl devices | awk '/(Mouse|Keyboard) at /{t=($0 ~ /Mouse/)?"MOUSE":"KEYBOARD"; getline; gsub(/^[ \t]+/,""); print t"\t"$0"\t\t"}' | grep -v -i -E 'virtual|power-button|video-bus|consumer|system control' | head -10
  ;;
printers)
  if command -v lpstat >/dev/null; then lpstat -p 2>/dev/null | awk '{printf "%s\t%s\t\t\n",$2,$3}' | grep . || row "NO PRINTERS" ""; else row "PRINTING" "CUPS is not installed"; fi
  ;;
usb)
  lsusb | sed 's/Bus \([0-9]*\) Device \([0-9]*\): ID \([0-9a-f:]*\) /\1:\2\t\3  /' | awk -F'\t' '{printf "%s\t%s\t\t\n",$1,$2}' | head -14
  ;;
language)
  localectl status 2>/dev/null | sed 's/^ *//' | awk -F': ' 'NF>1 {printf "%s\t%s\t\t\n",toupper($1),$2}'
  ;;
datetime)
  timedatectl 2>/dev/null | sed 's/^ *//' | awk -F': ' 'NF>1 {printf "%s\t%s\t\t\n",toupper($1),$2}' | head -9
  ;;
idle)
  f="$HOME/.config/projectnier/idle.json"
  l=$(jq -r '.lock // 10' "$f" 2>/dev/null || echo 10); s=$(jq -r '.sleep // 30' "$f" 2>/dev/null || echo 30)
  if [ "$l" -gt 0 ]; then row "LOCK SCREEN" "after $l min idle"; else row "LOCK SCREEN" "never"; fi
  if [ "$s" -gt 0 ]; then row "SLEEP" "after $s min idle (locks first)"; else row "SLEEP" "never"; fi
  [ "$l" -gt 0 ] && [ "$s" -gt 0 ] && [ "$s" -le "$l" ] && row "NOTE" "sleep comes before the lock timer"
  ;;
session)
  loginctl list-sessions --no-legend 2>/dev/null | awk '{printf "SESSION %s\t%s %s %s\t\t\n",$1,$3,$4,$5}'
  row "THIS SESSION" "${XDG_SESSION_ID:-$(loginctl | awk 'NR==2{print $1}')} / ${XDG_SESSION_TYPE:-wayland}"
  row "DESKTOP" "${XDG_CURRENT_DESKTOP:-Hyprland}"
  row "DISPLAY MANAGER" "$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" .service)"
  ;;
*) row "UNKNOWN TOPIC" "$topic" ;;
esac
