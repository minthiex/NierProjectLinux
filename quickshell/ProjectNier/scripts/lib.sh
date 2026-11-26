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
# a TAB or newline in a shown text (a file name from an archive ...) would shift the columns and put part of the name
# in the click column, where it runs as a command: the shown texts lose them
TAB=$(printf '\t')
NL='
'
row() {
  k=$1 v=$2
  case "$k$v${3:-}" in *"$TAB"*|*"$NL"*)
    k=$(printf '%s' "$k" | tr '\t\n' '  '); v=$(printf '%s' "$v" | tr '\t\n' '  ')
    set -- "$k" "$v" "$(printf '%s' "${3:-}" | tr -d '\t\n')" "${4:-}" ;;
  esac
  printf '%s\t%s\t%s\t%s\n' "$k" "$v" "${3:-}" "${4:-}"
}
blank() { printf '\t\t\t\n'; }
# q <text>: the text as one single-quoted shell word (safe to put in a click command that runs with sh -c)
q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
