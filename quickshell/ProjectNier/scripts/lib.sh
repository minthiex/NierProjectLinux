# shared helpers: rows are  key <TAB> value [<TAB> percent [<TAB> click-command]]
export LC_ALL=C
D="$HOME/.local/share/ProjectNier"
# the Messenger bridge recipe + data: $PROJECTNIER_BRIDGE_DIR, else the original fbtui location if it exists, else
# where install.sh puts it (same order as messenger-setup.py)
bridge_dir() {
  if [ -n "${PROJECTNIER_BRIDGE_DIR:-}" ]; then printf '%s' "$PROJECTNIER_BRIDGE_DIR"
  elif [ -f "$HOME/.local/share/fbtui-src/bridge/docker-compose.yml" ]; then printf '%s' "$HOME/.local/share/fbtui-src/bridge"
  else printf '%s' "$HOME/.local/share/projectnier/messenger-bridge"; fi
}
mkdir -p "$D"
row() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "${3:-}" "${4:-}"; }
blank() { printf '\t\t\t\n'; }
# q <text>: the text as one single-quoted shell word (safe to put in a click command that runs with sh -c)
q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
