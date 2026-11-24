#!/usr/bin/env bash
# One-time setup of Messenger for the NieR screen: local Matrix server (Synapse) + Facebook bridge (mautrix-meta).
# Easiest: open Communication → Messages and press SET UP MESSENGER. This does the same from a terminal:
#   ./setup.sh <username>        (asks for a password for that local account; it never leaves this computer)
# Both run ~/.config/quickshell/ProjectNier/scripts/messenger-setup.py. Afterwards send "login" to the bridge bot
# in Messenger to connect Facebook. Needs docker + docker compose (no Python packages: the config patcher runs
# inside the Synapse image).
set -euo pipefail
cd "$(dirname "$0")"
# the copy inside the dotfiles repo is only the recipe: its database and logins must not end up in git
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "run the copy that install.sh made instead: ~/.local/share/projectnier/messenger-bridge/setup.sh"; exit 1
fi
USERNAME="$(printf %s "${1:-}" | tr A-Z a-z)"
[ -n "$USERNAME" ] || { echo "usage: ./setup.sh <username>"; exit 1; }
SETUP="$HOME/.config/quickshell/ProjectNier/scripts/messenger-setup.py"
[ -f "$SETUP" ] || { echo "missing $SETUP (the ProjectNier shell)"; exit 1; }
read -rsp "password for @$USERNAME:localhost (8+ characters): " PW; echo
# the password goes in through the environment, never on a command line
SETUP_PAYLOAD="$(PW="$PW" python3 -I -c 'import json,os,sys; print(json.dumps({"username": sys.argv[1], "password": os.environ["PW"]}))' "$USERNAME")" \
PROJECTNIER_BRIDGE_DIR="$PWD" python3 -I "$SETUP" | python3 -I -c '
import json, sys
for line in sys.stdin:
    d = json.loads(line)
    if "step" in d: print(":: " + d["step"])
    elif "error" in d: print("!! " + d["error"]); sys.exit(1)
    elif d.get("ok"): print(":: done: " + d["user_id"] + ". Open Messenger on the NieR screen and send  login  to the bridge bot.")'
