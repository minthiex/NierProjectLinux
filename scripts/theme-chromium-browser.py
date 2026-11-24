#!/usr/bin/env python3
"""Builds the NieR look for the regular Chromium browser as a theme extension (palette from Theme.qml)
in ~/.config/tui-chromium-theme, loaded by chromium.sh. Restart Chromium after."""
import re, json, pathlib

home = pathlib.Path.home()
theme = (home / ".config/quickshell/ProjectNier/Theme.qml").read_text()
def col(n):
    h = re.search(r'property color %s: "#([0-9a-fA-F]{6})"' % n, theme).group(1)
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)]
paper, dark, ink, soft, acc = (col(n) for n in ("paper", "paperDark", "ink", "inkSoft", "accent"))

out = home / ".config/tui-chromium-theme"
out.mkdir(parents=True, exist_ok=True)
(out / "manifest.json").write_text(json.dumps({
    "manifest_version": 3, "name": "tui chromium theme", "version": "1.0",
    "theme": {
        "colors": {
            "frame": dark, "frame_inactive": dark, "frame_incognito": ink, "frame_incognito_inactive": ink,
            "toolbar": paper, "tab_text": ink, "tab_background_text": soft,
            "bookmark_text": ink, "toolbar_text": ink, "toolbar_button_icon": ink,
            "omnibox_background": dark, "omnibox_text": ink,
            "ntp_background": paper, "ntp_text": ink, "ntp_link": ink,
            "button_background": paper,
        },
        "tints": {"buttons": [0, 0, 0.25], "frame": [0, 0, 0.75]},
    },
}, indent=2))
print("wrote", out)
