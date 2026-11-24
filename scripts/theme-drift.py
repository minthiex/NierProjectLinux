#!/usr/bin/env python3
"""Sets Drift's accent colour to the NieR soft ink colour from Theme.qml (no red) (the rest of Drift follows the terminal palette,
which the content terminals already get from Theme.qml). Restart Drift afterwards."""
import re, pathlib
home = pathlib.Path.home()
acc = re.search(r'property color inkSoft: "(#[0-9a-fA-F]+)"', (home / ".config/quickshell/ProjectNier/Theme.qml").read_text()).group(1)
p = home / ".config/drift/config.toml"
s = p.read_text()
new, n = re.subn(r'(?m)^accent\s*=.*$', f'accent = "{acc}"', s, count=1)
assert n == 1, "no accent line"
p.write_text(new)
print("drift accent", acc)
