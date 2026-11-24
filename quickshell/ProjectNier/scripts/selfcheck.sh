#!/bin/sh
# usage: selfcheck.sh   health check of the ProjectNier shell; prints rows (see lib.sh): CHECK <TAB> OK | FAIL: why
# Shown by System → Self Check, or run it from a terminal after an edit.
. "$(dirname "$0")/lib.sh"
[ -n "$PROJECTNIER_SELFCHECK" ] && exit 0      # never run inside itself
export PROJECTNIER_SELFCHECK=1
C="$(cd "$(dirname "$0")/.." && pwd)"
S="$C/scripts"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fails=0
ok()   { row "$1" "OK"; }
bad()  { row "$1" "FAIL: $2"; fails=$((fails+1)); }

# ---- every pane script / topic that Panes.qml uses runs and knows its topic
# (the exit code means nothing: these scripts often end on a false test. Broken = unknown topic or no output at all;
# a script that needs longer than 12 s, e.g. updates.sh asking the network, is only noted as slow.)
grep -oE 'script: "[a-z.-]+"(, args: \["[a-z-]+")?' "$C/Panes.qml" | sed -E 's/script: "([^"]+)"(, args: \["([^"]+)")?/\1 \3/' \
  | sed -E 's/^info\.sh $/info.sh apps Shell|sh|cli/' | grep -v "^selfcheck\.sh" | sort -u > "$tmp/topics"     # info.sh with args: apps([...])
i=0
while read -r sc tp; do
  i=$((i+1))
  [ "$tp" = dir ] && tp="dir $HOME"            # dirSpec: any folder will do
  ( timeout 12 sh "$S/$sc" $tp > "$tmp/out.$i" 2>/dev/null; echo $? > "$tmp/rc.$i"; echo "$sc $tp" > "$tmp/name.$i" ) &
done < "$tmp/topics"
wait
n=0; broken=""; slow=""
for f in "$tmp"/name.*; do
  [ -f "$f" ] || continue
  k=${f##*.}; n=$((n+1)); nm=$(sed 's/^info\.sh //; s/ .*//' "$f")
  if [ "$(cat "$tmp/rc.$k")" = 124 ]; then slow="$slow $nm"
  elif grep -q '^UNKNOWN TOPIC' "$tmp/out.$k" || [ ! -s "$tmp/out.$k" ]; then broken="$broken $nm"; fi
done
[ -z "$broken" ] && ok "PANE TOPICS ($n)" || bad "PANE TOPICS ($n)" "$broken"
[ -n "$slow" ] && row "SLOW (over 12 s)" "$slow"

# ---- every built-in sub-function in Pages.qml has a spec in Panes.qml
awk '/label: "/{match($0,/label: "[^"]+"/); t=substr($0,RSTART+8,RLENGTH-9)} /name: "/{match($0,/name: "[^"]+"/); print t"/"substr($0,RSTART+7,RLENGTH-8)}' "$C/Pages.qml" | grep -v '/Restore Functions$' > "$tmp/subs"
missing=""
while IFS= read -r k; do grep -qF "\"$k\":" "$C/Panes.qml" || missing="$missing [$k]"; done < "$tmp/subs"
[ -z "$missing" ] && ok "SUB-FUNCTION SPECS ($(wc -l < "$tmp/subs"))" || bad "SUB-FUNCTION SPECS" "$missing"

# ---- script syntax
e=""
for f in "$S"/*.sh; do bash -n "$f" 2>/dev/null || e="$e $(basename "$f")"; done
for f in "$S"/*.py; do python3 -I -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$f" 2>/dev/null || e="$e $(basename "$f")"; done
[ -z "$e" ] && ok "SCRIPT SYNTAX" || bad "SCRIPT SYNTAX" "$e"

# ---- colours only come from Theme.qml
h=$(grep -lE '"#[0-9a-fA-F]{3,8}"' "$C"/*.qml | grep -v '/Theme\.qml$' | xargs -r -n1 basename | tr '\n' ' ')
[ -z "$h" ] && ok "THEME COLOURS" || bad "THEME COLOURS" "hex literal in $h"

# ---- shell process and its log since the last (re)load, minus known harmless noise
if pgrep -x qs >/dev/null; then
  cnt=$(qs list --all 2>/dev/null | grep -c 'Config path: .*/ProjectNier/')
  [ "$cnt" = 1 ] && ok "SHELL INSTANCE" || bad "SHELL INSTANCE" "$cnt instances running"
  qs -c ProjectNier log 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' > "$tmp/log"
  last=$(grep -n 'Configuration Loaded' "$tmp/log" | tail -1 | cut -d: -f1)
  noise='qt\.qpa\.wayland\.textinput|quickshell\.dbus\.properties|QDBusError|MatrixClient: .* (timed out|-> 0)'
  # a reload after unlocking the boot lock screen: Quickshell complains about the old lock object. Only noise while
  # the screen really is unlocked.
  [ "$(LC_ALL=C.UTF-8 qs -c ProjectNier ipc call lock isLocked 2>/dev/null | tail -n 1)" = false ] && noise="$noise|Session lock object was destroyed|Component\.onDestruction may be used"
  w=$(tail -n +"${last:-1}" "$tmp/log" | grep -E 'WARN|ERROR' | grep -vE "$noise" | sort -u)
  if [ -z "$w" ]; then ok "SHELL LOG"; else bad "SHELL LOG" "$(printf '%s\n' "$w" | wc -l | tr -d ' ') warning(s)"; printf '%s\n' "$w" | head -4 | while IFS= read -r l; do row "" "$(printf '%s' "$l" | cut -c1-90)"; done; fi
  # the Messenger's own state (MatrixClient.qml); an older shell without that IPC call: judge by the log
  ms=$(LC_ALL=C.UTF-8 qs -c ProjectNier ipc call messenger status 2>/dev/null | tail -n 1)
  if [ -n "$ms" ] && ! printf '%s' "$ms" | grep -qi 'no.*function\|not found\|error'; then
    case "$ms" in CONNECTED|CONNECTING) ok "MESSENGER CLIENT" ;; *) bad "MESSENGER CLIENT" "$ms" ;; esac
  else
    mf=$(tail -n +"${last:-1}" "$tmp/log" | grep -cE 'MatrixClient: .* (timed out|-> 0)')
    [ "$mf" -lt 5 ] && ok "MESSENGER CLIENT" || bad "MESSENGER CLIENT" "$mf failed requests since the last load"
  fi
  # the health light at the top right (Health.qml): what it shows right now
  hl=$(LC_ALL=C.UTF-8 qs -c ProjectNier ipc call health status 2>/dev/null | tail -n 1)
  case "$hl" in OK) ok "HEALTH LIGHT" ;; "") row "HEALTH LIGHT" "no answer (shell older than Health.qml?)" ;; *) bad "HEALTH LIGHT" "$hl" ;; esac
else
  bad "SHELL INSTANCE" "qs is not running"
fi

# ---- Messenger bridge
if command -v docker >/dev/null; then
  for c in fbtui-synapse fbtui-meta; do
    st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null)
    [ "$st" = running ] && ok "CONTAINER $c" || bad "CONTAINER $c" "${st:-not found}"
  done
  # the address the shell uses (MatrixClient.qml turns localhost into 127.0.0.1)
  code=$(curl -s -m 4 -o /dev/null -w '%{http_code}' http://127.0.0.1:8008/_matrix/client/versions)
  [ "$code" = 200 ] && ok "SYNAPSE ANSWERS" || bad "SYNAPSE ANSWERS" "http ${code:-none} on 127.0.0.1:8008"
fi

# ---- logins stay private
for f in "$HOME/.config/projectnier/mail.json" "$HOME/.config/fbtui/session.json"; do
  [ -e "$f" ] || continue
  m=$(stat -c %a "$f")
  [ "$m" = 600 ] && ok "MODE $(basename "$f")" || bad "MODE $(basename "$f")" "$m (should be 600)"
done

# ---- the last REPAIR (scripts/repair.sh)
[ -s "$D/repair.log" ] && row "LAST REPAIR" "$(head -n 1 "$D/repair.log" | tr '\t' ' ' | cut -c1-110)"

blank
[ "$fails" = 0 ] && row "RESULT" "ALL CHECKS PASSED" || row "RESULT" "$fails PROBLEM(S)"
