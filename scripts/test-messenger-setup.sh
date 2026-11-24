#!/usr/bin/env bash
# usage: test-messenger-setup.sh [--keep]
# Tests a from-scratch Messenger setup the way a new install would run it, without touching the real one:
# a throwaway copy of the bridge recipe (own container names, port 18008, empty HOME) is set up with
# messenger-setup.py, the bot is asked for its login steps, then everything is removed again.
# --keep leaves the test bridge running (remove it later with: docker compose -p nier-messenger-test down -v).
# The compose PROJECT NAME is fixed to nier-messenger-test for every compose call: compose otherwise names a project
# after its folder, and a test folder named like the real one ("bridge") made the test replace and then remove the
# real containers (2026-11-24).
set -euo pipefail
export COMPOSE_PROJECT_NAME=nier-messenger-test
REAL="$HOME/.local/share/fbtui-src/bridge"
SETUP="$(dirname "$(readlink -f "$0")")/messenger-setup.py"
PORT=18008
W=$(mktemp -d "${TMPDIR:-/tmp}/nier-messenger-test.XXXXXX")
B="$W/nier-test-bridge"; H="$W/home"; mkdir -p "$B" "$H"
keep=0; [ "${1:-}" = "--keep" ] && keep=1

cleanup() {
  if [ "$keep" = 0 ]; then
    echo ":: cleaning up"
    (cd "$B" && docker compose -p "$COMPOSE_PROJECT_NAME" down -v >/dev/null 2>&1) || true
    rm -rf "$W"
  else
    echo ":: kept: $W  (bridge on 127.0.0.1:$PORT; remove: docker compose -p $COMPOSE_PROJECT_NAME down -v; rm -rf $W)"
  fi
}
trap cleanup EXIT

for f in docker-compose.yml patch_configs.py setup.sh; do cp "$REAL/$f" "$B/"; done
sed -i "s/container_name: fbtui-synapse/container_name: nier-test-synapse/; s/container_name: fbtui-meta/container_name: nier-test-meta/; s/\"127.0.0.1:8008:8008\"/\"127.0.0.1:$PORT:8008\"/" "$B/docker-compose.yml"
if docker ps -a --format '{{.Names}}' | grep -q '^nier-test-'; then echo "!! old test containers exist: docker rm -f nier-test-synapse nier-test-meta"; exit 1; fi

real_before=$(docker inspect -f '{{.Id}} {{.State.StartedAt}}' fbtui-synapse fbtui-meta 2>/dev/null || true)
user="test$RANDOM"; pass=$(head -c 18 /dev/urandom | base64 | tr -d '/+=')
echo ":: fresh setup as @$user:localhost (test bridge on port $PORT)"
start=$(date +%s)
out=$(SETUP_PAYLOAD="{\"username\":\"$user\",\"password\":\"$pass\"}" HOME="$H" PROJECTNIER_BRIDGE_DIR="$B" \
      PROJECTNIER_MATRIX_URL="http://127.0.0.1:$PORT" python3 -I "$SETUP" | while IFS= read -r l; do
        printf '   +%ss %s\n' "$(( $(date +%s) - start ))" "$l" >&2; printf '%s\n' "$l"; done)
last=$(printf '%s\n' "$out" | tail -n 1)
printf '%s' "$last" | grep -q '"ok": true' || { echo "!! setup failed"; exit 1; }

room=$(printf '%s' "$last" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["bot_room"])')
token=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["access_token"])' "$H/.config/fbtui/session.json")
api="http://127.0.0.1:$PORT/_matrix/client/v3/rooms/$(python3 -I -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$room")"
# the bot only sees messages sent after it joined the chat: wait for its greeting first (as a person would)
echo ":: waiting for the bridge bot to join"
for _ in $(seq 1 30); do
  curl -s -H @- "$api/messages?dir=b&limit=3" <<<"Authorization: Bearer $token" | grep -q '"sender":"@facebookbot' && break
  sleep 1
done
echo ":: asking the bridge bot:  login"
curl -s -X PUT -H @- -H 'Content-Type: application/json' "$api/send/m.room.message/t$(date +%s)" -d '{"msgtype":"m.text","body":"login"}' <<<"Authorization: Bearer $token" >/dev/null
# the bot answers "login" with its login flows; on a first start it can take a while
answered=0
for _ in $(seq 1 15); do
  sleep 2
  msgs=$(curl -s -H @- "$api/messages?dir=b&limit=6" <<<"Authorization: Bearer $token")
  if printf '%s' "$msgs" | python3 -I -c '
import json, sys
ev = [e for e in json.load(sys.stdin).get("chunk", []) if e["type"] == "m.room.message"]
# the real answer to "login" lists the login flows (the greeting that comes first does not count)
sys.exit(0 if any(e["sender"].startswith("@facebookbot") and "flow" in e["content"].get("body", "") for e in ev) else 1)'; then
    answered=1; break
  fi
done
printf '%s' "$msgs" | python3 -I -c '
import json, sys
for e in reversed(json.load(sys.stdin).get("chunk", [])):
    if e["type"] == "m.room.message":
        print("   " + e["sender"] + ": " + e["content"].get("body", "").replace("\n", " ")[:150])'

errs=$(docker logs nier-test-meta 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -cE ' (ERR|FTL) ' || true)
echo ":: bridge errors in its log: $errs"
mode=$(stat -c %a "$H/.config/fbtui/session.json"); echo ":: session.json mode: $mode"
untouched=0
[ "$real_before" = "$(docker inspect -f '{{.Id}} {{.State.StartedAt}}' fbtui-synapse fbtui-meta 2>/dev/null || true)" ] && untouched=1
[ "$untouched" = 1 ] && echo ":: your real bridge: untouched" || echo "!! your real bridge was changed: cd $REAL && docker compose up -d"
[ "$answered" = 1 ] && echo ":: the bot answered" || echo "!! the bot did not answer within 30 s"
[ "$errs" = 0 ] && [ "$mode" = 600 ] && [ "$answered" = 1 ] && [ "$untouched" = 1 ] && echo ":: PASS" || { echo ":: FAIL"; exit 1; }
