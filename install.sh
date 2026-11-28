#!/usr/bin/env bash
# ProjectNier dotfiles installer.   usage: ./install.sh [--dry-run] [--uninstall]
# Links the shell and the shared Hyprland settings into ~/.config, gives this machine its own hyprland.lua and
# local.lua, and copies the Messenger bridge recipe to ~/.local/share/projectnier/messenger-bridge.
# Never deletes anything: a file or folder already in the way is moved aside as <name>.pre-projectnier-<time>.
# Running it again changes nothing that is already in place. It does not install packages: it lists what is missing.
# --uninstall undoes the links and copies (see the block below); it never deletes your data, logins or local.lua.
set -euo pipefail
REPO="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DRY=0; UNINSTALL=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --uninstall) UNINSTALL=1 ;;
    *) printf 'usage: %s [--dry-run] [--uninstall]\n' "$0" >&2; exit 2 ;;
  esac
done
STAMP=$(date +%Y%m%d-%H%M%S)
say() { printf '%s\n' "$*"; }
do_() { if [ "$DRY" = 1 ]; then say "   would: $*"; else "$@"; fi; }
done_() { [ "$DRY" = 1 ] || say "$*"; }          # report a change only when it was really made

# ---- uninstall -------------------------------------------------------------------------------------------------
if [ "$UNINSTALL" = 1 ]; then
  newest_backup() { ls -d "$1".pre-projectnier-* 2>/dev/null | sort | tail -n 1 || true; }   # newest first-run backup of a path
  restore() {                                   # put back what install.sh moved aside, if anything
    local b; b="$(newest_backup "$1")"
    if [ -n "$b" ] && [ ! -e "$1" ] && [ ! -L "$1" ]; then do_ mv "$b" "$1"; done_ "   restored $1 (from $b)"; fi
  }
  # unlink <target in repo> <path in home>: removes the link only if it points into this repo
  unlink_() {
    local src="$1" dst="$2"
    if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
      do_ rm "$dst"; done_ "   removed  $dst"
    elif [ -e "$dst" ] || [ -L "$dst" ]; then say "   kept     $dst (not a link to this repo)"
    else say "   absent   $dst"; fi
    restore "$dst"
  }
  say ":: stopping the shell"
  if [ "$DRY" = 1 ]; then say "   would: qs kill -c ProjectNier"; else qs kill -c ProjectNier >/dev/null 2>&1 || true; fi

  say ":: shell"
  unlink_ "$REPO/quickshell/ProjectNier" "$HOME/.config/quickshell/ProjectNier"

  say ":: hyprland"
  unlink_ "$REPO/hypr/projectnier.lua" "$HOME/.config/hypr/projectnier.lua"
  H="$HOME/.config/hypr/hyprland.lua"
  if [ -f "$H" ] && grep -q 'require("projectnier")' "$H"; then
    b="$(newest_backup "$H")"
    if [ -n "$b" ]; then
      do_ mv "$H" "$H.projectnier-removed-$STAMP"; done_ "   moved    $H -> $H.projectnier-removed-$STAMP"
      do_ mv "$b" "$H"; done_ "   restored $H (from $b)"
    elif cmp -s "$REPO/hypr/hyprland.lua" "$H"; then
      do_ rm "$H"; done_ "   removed  $H (you had none before: Hyprland falls back to its defaults)"
    else
      say "   kept     $H (you edited it and there is no earlier one): remove its require(\"projectnier\") line yourself"
    fi
  else say "   kept     $H (does not load projectnier)"; fi
  [ -f "$HOME/.config/hypr/local.lua" ] && say "   kept     ~/.config/hypr/local.lua (yours)"

  say ":: messenger bridge recipe"
  B="$HOME/.local/share/projectnier/messenger-bridge"
  for f in docker-compose.yml patch_configs.py setup.sh .gitignore; do
    if [ -f "$B/$f" ] && cmp -s "$REPO/messenger-bridge/$f" "$B/$f"; then do_ rm "$B/$f"; done_ "   removed  $B/$f"
    elif [ -e "$B/$f" ]; then say "   kept     $B/$f (changed by you)"; fi
  done
  if [ "$DRY" != 1 ]; then rmdir "$B" "$(dirname "$B")" 2>/dev/null || true; fi
  [ -d "$B/synapse" ] || [ -d "$B/meta" ] && \
    say "   kept     $B (the bridge's data); containers fbtui-synapse / fbtui-meta are not touched: stop them with docker compose -p bridge down"

  say ""
  [ "$DRY" = 1 ] && { say ":: dry run: nothing was changed"; exit 0; }
  say ":: uninstalled. Left alone: ~/.local/share/ProjectNier, ~/.config/projectnier, ~/.config/fbtui, ~/.config/autostart,"
  say "   ~/backups and this repo. Log out and back in to Hyprland (or run: hyprctl reload)."
  exit 0
fi

# ---- what is needed --------------------------------------------------------------------------------------------
say ":: checking programs"
need=(Hyprland qs kitty jq python3 curl nmcli bluetoothctl wpctl pactl playerctl powerprofilesctl grim slurp wl-copy notify-send dolphin)
want=(docker hyprsunset gwenview chromium firefox keepassxc secret-tool btop cliphist qalc)
missing=(); for p in "${need[@]}"; do command -v "$p" >/dev/null 2>&1 || missing+=("$p"); done
optional=(); for p in "${want[@]}"; do command -v "$p" >/dev/null 2>&1 || optional+=("$p"); done
python3 -c 'import gi; gi.require_version("Gio", "2.0")' 2>/dev/null || missing+=("python-gobject")
fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd" || missing+=("JetBrainsMono Nerd Font")
if [ ${#missing[@]} -gt 0 ]; then say "   missing (the shell needs these): ${missing[*]}"; else say "   all required programs found"; fi
[ ${#optional[@]} -gt 0 ] && say "   optional, not found: ${optional[*]}  (docker: Messenger; keepassxc/secret-tool: mail passwords in a keyring; cliphist: clipboard history; qalc: calculator in the search box)"

# ---- links -----------------------------------------------------------------------------------------------------
# link <target in repo> <path in home>: an existing link to the same place is left alone, anything else moved aside
link() {
  local src="$1" dst="$2"
  if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then say "   ok      $dst"; return; fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then do_ mv "$dst" "$dst.pre-projectnier-$STAMP"; done_ "   moved   $dst -> $dst.pre-projectnier-$STAMP"; fi
  [ -d "$(dirname "$dst")" ] || do_ mkdir -p "$(dirname "$dst")"
  do_ ln -s "$src" "$dst"; done_ "   linked  $dst -> $src"
}
# place <file in repo> <path in home>: a copy this machine owns (only made when missing, or when the one there does
# not load the shared settings, which is then moved aside)
place() {
  local src="$1" dst="$2" keep_if="${3:-}"
  if [ -f "$dst" ] && { [ -z "$keep_if" ] || grep -q "$keep_if" "$dst"; }; then say "   ok      $dst (yours, kept)"; return; fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then do_ mv "$dst" "$dst.pre-projectnier-$STAMP"; done_ "   moved   $dst -> $dst.pre-projectnier-$STAMP"; fi
  [ -d "$(dirname "$dst")" ] || do_ mkdir -p "$(dirname "$dst")"
  do_ cp "$src" "$dst"; done_ "   copied  $dst"
}

say ":: shell"
link "$REPO/quickshell/ProjectNier" "$HOME/.config/quickshell/ProjectNier"

say ":: hyprland"
link "$REPO/hypr/projectnier.lua" "$HOME/.config/hypr/projectnier.lua"
# hyprland.lua stays a real file: Hyprland looks for local.lua next to the real file, not next to a link's target
place "$REPO/hypr/hyprland.lua" "$HOME/.config/hypr/hyprland.lua" 'require("projectnier")'
place "$REPO/hypr/local.lua.example" "$HOME/.config/hypr/local.lua"

say ":: messenger bridge recipe"
B="$HOME/.local/share/projectnier/messenger-bridge"
[ -d "$B" ] || do_ mkdir -p "$B"
for f in docker-compose.yml patch_configs.py setup.sh .gitignore; do
  if [ -f "$B/$f" ] && cmp -s "$REPO/messenger-bridge/$f" "$B/$f"; then continue; fi
  do_ cp "$REPO/messenger-bridge/$f" "$B/$f"; done_ "   copied  $B/$f"
done
say "   (its data, once set up, stays in $B: synapse/ meta/ .env)"

# ---- next ------------------------------------------------------------------------------------------------------
say ""
[ "$DRY" = 1 ] && { say ":: dry run: nothing was changed"; exit 0; }
say ":: done. Next:"
say "   1. Log out and back in to Hyprland (or run: hyprctl reload, then qs -c ProjectNier -d)."
[ -f "$HOME/.config/hypr/hyprland.lua.pre-projectnier-$STAMP" ] && \
  say "      Your previous hyprland.lua is hyprland.lua.pre-projectnier-$STAMP: move what you want to keep into local.lua."
say "   2. Messenger: Communication → Messages → SET UP MESSENGER (needs Docker)."
say "   3. Email: Communication → Email → sign in with a Google app password."
say "   4. System → Self Check shows whether everything is in order."
