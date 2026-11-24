#!/bin/sh
# usage: gmail.sh [address]
# Opens Gmail as a Chromium app window (no tabs or URL bar, window class chrome-mail.google.com__-Default, own profile
# ~/.config/tui-gmail-chromium) so it never touches the Firefox in the Browser sub-function.
u="https://mail.google.com/"
[ -n "$1" ] && u="https://mail.google.com/?authuser=$(printf '%s' "$1" | jq -sRr @uri)"
python3 "$(dirname "$0")/theme-gmail.py" >/dev/null 2>&1
exec chromium --app="$u" --load-extension="$HOME/.config/tui-gmail-chromium-ext" --user-data-dir="$HOME/.config/tui-gmail-chromium" --ozone-platform=wayland
