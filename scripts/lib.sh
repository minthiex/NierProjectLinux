# shared helpers: rows are  key <TAB> value [<TAB> percent [<TAB> click-command]]
export LC_ALL=C
D="$HOME/.local/share/ProjectNier"
mkdir -p "$D"
row() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "${3:-}" "${4:-}"; }
blank() { printf '\t\t\t\n'; }
# q <text>: the text as one single-quoted shell word (safe to put in a click command that runs with sh -c)
q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
