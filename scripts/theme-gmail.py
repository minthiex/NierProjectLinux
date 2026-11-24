#!/usr/bin/env python3
"""Builds the NieR look for the Gmail Chromium app as a tiny extension (palette + font from Theme.qml)
in ~/.config/tui-gmail-chromium-ext, loaded by gmail.sh. Restart the Gmail window after.

Gmail's own markup changes now and then: the theme leans on its Material colour variables and ARIA roles,
which are fairly stable, and only on a few long-lived class names (inbox rows, buttons). Mail bodies keep
their own layout and colours so newsletters stay readable; only the page around them is restyled."""
import json
import pathlib
import re

home = pathlib.Path.home()
theme = (home / ".config/quickshell/ProjectNier/Theme.qml").read_text()


def col(n):
    return re.search(r'property color %s: "(#[0-9a-fA-F]+)"' % n, theme).group(1)


font = re.search(r'property string font: "([^"]+)"', theme).group(1)
paper, dark, ink, soft, acc = (col(n) for n in ("paper", "paperDark", "ink", "inkSoft", "accent"))

# Material 3 colour roles Gmail reads its whole interface from
surfaces = ["background", "surface", "surface-bright", "surface-dim", "surface-container-lowest",
            "surface-container-low", "surface-container", "surface-container-high", "surface-container-highest"]
roles = {**{s: paper for s in surfaces},
         "surface-variant": dark, "surface-container-highest": dark,
         "on-background": ink, "on-surface": ink, "on-surface-variant": soft,
         "primary": ink, "on-primary": paper, "primary-container": dark, "on-primary-container": ink,
         "secondary": ink, "on-secondary": paper, "secondary-container": dark, "on-secondary-container": ink,
         "tertiary": ink, "on-tertiary": paper, "tertiary-container": dark, "on-tertiary-container": ink,
         "outline": ink, "outline-variant": soft, "inverse-surface": ink, "inverse-on-surface": paper,
         "inverse-primary": dark, "error": acc, "on-error": paper, "error-container": dark, "on-error-container": acc}
vars_ = "\n".join(f"  --gm3-sys-color-{k}: {v} !important;" for k, v in roles.items())

# icons are drawn with icon fonts in places: they must keep their own font
not_icon = ':not([class*="material-icons"]):not([class*="material-symbols"]):not(.google-material-icons):not(.google-symbols)'
not_mail = ':not(.a3s *):not(.a3s)'          # .a3s = the body of an opened mail

css = f"""/* NieR: flat paper, thin ink lines, square, no animation, no colour (mail bodies left as sent) */
:root, html, body {{
{vars_}
  background: {paper} !important; color: {ink} !important;
}}
*, *::before, *::after {{ border-radius: 0 !important; transition: none !important; animation: none !important; box-shadow: none !important; text-shadow: none !important; }}
:is(body, div, span, td, th, a, p, li, h1, h2, h3, input, textarea, button, label){not_icon}{not_mail} {{ font-family: "{font}", monospace !important; }}

/* page, side bar, top bar */
html, body, header, [role="banner"], [role="navigation"], [role="main"], [role="complementary"], .nH, .no, .bkK, .aeN, .aeF, .Tm {{ background-color: {paper} !important; }}
[role="banner"], header {{ border-bottom: 1px solid {ink} !important; }}
[role="navigation"] {{ border-right: 1px solid {ink} !important; }}

/* search */
form[role="search"], form[role="search"] * {{ background-color: {dark} !important; color: {ink} !important; }}
form[role="search"] {{ border: 1px solid {ink} !important; }}

/* folder list: the open folder is a dark plate */
.TO.nZ, .TO.nZ * {{ background-color: {ink} !important; color: {paper} !important; }}
.TO:hover:not(.nZ) {{ background-color: {dark} !important; }}

/* inbox rows: unread bold with a red mark, hover / selected tan */
tr.zA {{ background-color: {paper} !important; border-bottom: 1px solid {dark} !important; }}
tr.zA.zE {{ box-shadow: inset 4px 0 0 {acc} !important; }}
tr.zA.zE * {{ color: {ink} !important; }}
tr.zA.yO * {{ color: {soft} !important; }}
tr.zA:hover, tr.zA.x7, tr.zA.btb {{ background-color: {dark} !important; }}

/* buttons: Compose is the one solid plate */
.T-I {{ background-color: {dark} !important; color: {ink} !important; border: 1px solid {ink} !important; }}
.T-I.T-I-KE, .T-I.T-I-KE *, .z0 > .L3, .z0 > .L3 * {{ background-color: {ink} !important; color: {paper} !important; }}
[role="button"]:hover:not(.T-I-KE), a:hover {{ background-color: {dark} !important; }}

/* menus, dialogs, the compose window */
[role="dialog"], [role="menu"], [role="listbox"], [role="tooltip"], [role="alertdialog"] {{ background-color: {paper} !important; color: {ink} !important; border: 1px solid {ink} !important; }}
[role="dialog"] input, [role="dialog"] textarea, [contenteditable="true"], input[type="text"], input[type="search"], textarea {{ background-color: {paper} !important; color: {ink} !important; }}
::placeholder {{ color: {soft} !important; }}

/* reading a mail: the header around the body follows the theme, the body itself does not */
.ha h2, .hP {{ color: {ink} !important; }}
.gD, .go, .g3 {{ color: {soft} !important; }}

/* label chips in the inbox and Google's coloured promo buttons (Upgrade ...) */
.at, .at *, .ar.as {{ background-color: {dark} !important; color: {ink} !important; border-color: {ink} !important; }}
a[href*="one.google.com"], [aria-label*="Upgrade"], [aria-label*="upgrade"], [data-pep-id] button, [data-pep-id] [role="button"] {{ background-color: {dark} !important; color: {ink} !important; border: 1px solid {ink} !important; }}
[data-pep-id] button *, [data-pep-id] [role="button"] * {{ background-color: transparent !important; color: {ink} !important; }}

a{not_mail}, a{not_mail}:visited {{ color: {ink} !important; }}
img:not(.a3s img):not([src*="photo"]):not([src*="avatar"]) {{ filter: grayscale(1) contrast(0.9); }}
::selection {{ background: {ink}; color: {paper}; }}
::-webkit-scrollbar {{ width: 8px; height: 8px; background: {paper} !important; }}
::-webkit-scrollbar-thumb {{ background: {ink} !important; border-radius: 0 !important; }}
"""

out = home / ".config/tui-gmail-chromium-ext"
out.mkdir(parents=True, exist_ok=True)
(out / "gmail.css").write_text(css)
(out / "manifest.json").write_text(json.dumps({
    "manifest_version": 3, "name": "tui gmail theme", "version": "1.0",
    "content_scripts": [{"matches": ["*://mail.google.com/*"], "css": ["gmail.css"], "run_at": "document_start", "all_frames": False}],
}, indent=2))
print("wrote", out)
