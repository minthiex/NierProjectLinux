#!/bin/sh
# usage: repair.sh   the standard fixes for what the health light watches (System → Self Check → REPAIR); prints rows
# 1. start a stopped Messenger bridge container   2. restart Synapse if it runs but does not answer
# 3. reconnect the Messenger and check mail now. Never touches logins (session.json, mail.json) or the compose setup.
# The report also goes to ~/.local/share/ProjectNier/repair.log (Self Check shows its first line as LAST REPAIR).
. "$(dirname "$0")/lib.sh"
log="$D/repair.log"
out=$(mktemp); trap 'rm -f "$out"' EXIT
r() { row "$1" "$2" >> "$out"; }
api="http://127.0.0.1:8008/_matrix/client/versions"
answers() { [ "$(curl -s -m 4 -o /dev/null -w '%{http_code}' "$api")" = 200 ]; }
ipc() { LC_ALL=C.UTF-8 qs -c ProjectNier ipc call "$@" 2>/dev/null | tail -n 1; }
did=0

if ! command -v docker >/dev/null 2>&1; then
  r "BRIDGE" "docker is not installed: skipped"
elif ! docker info >/dev/null 2>&1; then
  r "BRIDGE" "the Docker service is not running: start it (systemctl start docker), then repair again"
else
  for c in fbtui-synapse fbtui-meta; do
    st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null)
    if [ -z "$st" ]; then r "$c" "missing: rebuild it with SET UP MESSENGER (bridge: $(bridge_dir))"
    elif [ "$st" != running ]; then
      if docker start "$c" >/dev/null 2>&1; then r "$c" "was $st: started"; else r "$c" "was $st: could not start"; fi
      did=1
    fi
  done
  if [ "$did" = 1 ] || ! answers; then
    if [ "$did" = 0 ]; then
      docker restart fbtui-synapse >/dev/null 2>&1 && r "fbtui-synapse" "did not answer: restarted"; did=1
    fi
    i=0; while [ $i -lt 15 ] && ! answers; do sleep 2; i=$((i+1)); done
    answers && r "SYNAPSE" "answers" || r "SYNAPSE" "still not answering after 30 s: see docker logs fbtui-synapse"
  fi
fi

before=$(ipc messenger status)
if [ "$did" = 1 ] || [ "$before" != CONNECTED ]; then
  ipc messenger reconnect >/dev/null; did=1
  i=0; while [ $i -lt 10 ]; do sleep 1; now=$(ipc messenger status); [ "$now" = CONNECTED ] && break; i=$((i+1)); done
  r "MESSENGER" "${before:-?} -> reconnected: ${now:-?}"
fi
m=$(ipc mail status)
case "$m" in
  CONNECTED|"NO LOGIN"|"") ;;
  *) ipc mail check >/dev/null; did=1; r "MAIL" "$m: checking again (the result shows within a minute)" ;;
esac
[ "$did" = 0 ] && r "RESULT" "nothing needed fixing"

{ printf '%s\t' "$(date '+%Y-%m-%d %H:%M')"; cut -f1,2 "$out" | sed 's/\t/: /' | paste -sd ';' | sed 's/;/; /g'; cat "$out"; } > "$log.tmp" && mv "$log.tmp" "$log"
cat "$out"
