#!/bin/sh
# usage: chromium.sh [URL or search words]
# Starts the regular Chromium browser with the NieR theme extension.
python3 "$(dirname "$0")/theme-chromium-browser.py" >/dev/null 2>&1
exec chromium --load-extension="$HOME/.config/tui-chromium-theme" --ozone-platform=wayland "$@"
