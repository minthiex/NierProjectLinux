#!/usr/bin/env python3
"""Writes the NieR look (palette + font from Theme.qml, square corners, no animation) into the
userChrome.css / userContent.css / user.js of the Firefox profile. Restart the browser after."""
import re, sys, pathlib

home = pathlib.Path.home()
theme = (home / ".config/quickshell/ProjectNier/Theme.qml").read_text()
def col(n): return re.search(r'property color %s: "(#[0-9a-fA-F]+)"' % n, theme).group(1)
font = re.search(r'property string font: "([^"]+)"', theme).group(1)
paper, dark, ink, soft, acc = (col(n) for n in ("paper", "paperDark", "ink", "inkSoft", "accent"))

vars_ = f"""
:root {{
  --nier-paper: {paper}; --nier-paper-dark: {dark}; --nier-ink: {ink}; --nier-soft: {soft}; --nier-accent: {acc};
  --nier-font: "{font}", monospace;
}}
"""

chrome = vars_ + """
/* ---- NieR: flat paper, thin ink lines, square, no animation ---- */
:root, :root[lwtheme], :root:-moz-lwtheme {
  --toolbar-bgcolor: var(--nier-paper) !important;
  --toolbar-color: var(--nier-ink) !important;
  --toolbar-field-background-color: var(--nier-paper-dark) !important;
  --toolbar-field-color: var(--nier-ink) !important;
  --toolbar-field-border-color: var(--nier-ink) !important;
  --toolbar-field-focus-background-color: var(--nier-paper-dark) !important;
  --toolbar-field-focus-color: var(--nier-ink) !important;
  --toolbar-field-focus-border-color: var(--nier-accent) !important;
  --lwt-accent-color: var(--nier-paper) !important;
  --lwt-text-color: var(--nier-ink) !important;
  --lwt-toolbar-field-background-color: var(--nier-paper-dark) !important;
  --lwt-toolbar-field-color: var(--nier-ink) !important;
  --tab-selected-bgcolor: var(--nier-paper-dark) !important;
  --tab-selected-textcolor: var(--nier-ink) !important;
  --tab-loading-fill: var(--nier-accent) !important;
  --urlbar-box-bgcolor: var(--nier-paper-dark) !important;
  --urlbar-box-hover-bgcolor: var(--nier-paper-dark) !important;
  --urlbar-box-text-color: var(--nier-ink) !important;
  --arrowpanel-background: var(--nier-paper) !important;
  --arrowpanel-color: var(--nier-ink) !important;
  --arrowpanel-border-color: var(--nier-ink) !important;
  --panel-background: var(--nier-paper) !important;
  --panel-color: var(--nier-ink) !important;
  --focus-outline-color: var(--nier-accent) !important;
  --toolbarbutton-icon-fill: var(--nier-ink) !important;
  --toolbarbutton-hover-background: var(--nier-paper-dark) !important;
  --toolbarbutton-active-background: var(--nier-soft) !important;
  --sidebar-background-color: var(--nier-paper) !important;
  --sidebar-text-color: var(--nier-ink) !important;
  --chrome-content-separator-color: var(--nier-ink) !important;
  --tab-border-radius: 0 !important;
  --toolbarbutton-border-radius: 0 !important;
  --urlbar-border-radius: 0 !important;
  --border-radius-small: 0 !important; --border-radius-medium: 0 !important; --border-radius-large: 0 !important;
  --arrowpanel-border-radius: 0 !important;
}
* { font-family: var(--nier-font) !important; border-radius: 0 !important; }
*, *::before, *::after { transition: none !important; animation: none !important; }
#nav-bar, #TabsToolbar, #titlebar, #navigator-toolbox, #PersonalToolbar, #tabbrowser-tabs {
  background: var(--nier-paper) !important; color: var(--nier-ink) !important;
}
#navigator-toolbox { border-bottom: 1px solid var(--nier-ink) !important; }
#nav-bar { border-top: 0 !important; box-shadow: none !important; }
#urlbar-background, .urlbar-background, #searchbar { background: var(--nier-paper-dark) !important; border: 1px solid var(--nier-ink) !important; box-shadow: none !important; outline: 0 !important; }
#urlbar[focused] > #urlbar-background, #urlbar[open] > #urlbar-background { border-color: var(--nier-accent) !important; }
.tabbrowser-tab .tab-background { background: transparent !important; box-shadow: none !important; border: 1px solid transparent !important; }
.tabbrowser-tab[selected] .tab-background, .tabbrowser-tab[visuallyselected] .tab-background { background: var(--nier-paper-dark) !important; border-color: var(--nier-ink) !important; }
.tabbrowser-tab:hover:not([selected]) .tab-background { background: var(--nier-paper-dark) !important; }
.tab-label, .tab-text { color: var(--nier-ink) !important; }
.tab-icon-image { filter: none !important; }
panel, menupopup, .panel-arrowcontent, .menupopup-arrowscrollbox { --panel-background: var(--nier-paper); background: var(--nier-paper) !important; color: var(--nier-ink) !important; border: 1px solid var(--nier-ink) !important; box-shadow: none !important; }
menuitem[_moz-menuactive], menu[_moz-menuactive], .urlbarView-row[selected], .urlbarView-row:hover { background: var(--nier-paper-dark) !important; color: var(--nier-ink) !important; }
.urlbarView-row[selected] .urlbarView-title, .urlbarView-title { color: var(--nier-ink) !important; }
.urlbarView-url, .urlbarView-secondary { color: var(--nier-accent) !important; }
toolbarbutton:hover:not([disabled]) > .toolbarbutton-icon, toolbarbutton:hover:not([disabled]) { background-color: var(--nier-paper-dark) !important; }
/* nothing dims when the window is not focused */
:root:-moz-window-inactive, :root:-moz-window-inactive * { opacity: 1 !important; filter: none !important; }
:root:-moz-window-inactive { --toolbar-color: var(--nier-ink) !important; --lwt-text-color: var(--nier-ink) !important; --tab-selected-textcolor: var(--nier-ink) !important; }
:root:-moz-window-inactive .tab-label, :root:-moz-window-inactive toolbarbutton, :root:-moz-window-inactive #urlbar { color: var(--nier-ink) !important; }
/* no white panels, no shadows */
#urlbar, #urlbar[breakout-extend], #urlbar[breakout-extend][open] { box-shadow: none !important; filter: none !important; }
#urlbar .urlbar-background, #urlbar[breakout-extend] > .urlbar-background > .urlbar-background, #urlbar[open] > .urlbar-background {
  background: var(--nier-paper) !important; border: 1px solid var(--nier-ink) !important; box-shadow: none !important; outline: 0 !important; }
.urlbarView, .urlbarView-body-outer, .urlbarView-body-inner, .urlbarView-results, .urlbarView-row-inner, #urlbar-input-container, .urlbar-input-container {
  background: transparent !important; color: var(--nier-ink) !important; box-shadow: none !important; }
.urlbarView-row[selected] { background: var(--nier-paper-dark) !important; }
.urlbarView-no-wrap, .urlbarView-title, .urlbarView-action { color: var(--nier-ink) !important; }
#urlbar-input { color: var(--nier-ink) !important; }
.urlbarView-separator, .urlbarView-body-outer { border-color: var(--nier-ink) !important; }
#tabbrowser-tabbox, #tabbrowser-tabpanels, #appcontent, #browser, .browserContainer {
  background: var(--nier-paper) !important; box-shadow: none !important; border-color: var(--nier-ink) !important; }
.browserContainer { border: 1px solid var(--nier-ink) !important; }
.browserSidebarContainer, .browserStack { box-shadow: none !important; }
/* the little menus inside the address bar (search engine switcher, result "..." menu) and tooltips */
panel-list, tooltip, .urlbarView, #urlbar {
  --panel-background: var(--nier-paper) !important; --panel-color: var(--nier-ink) !important;
  --panel-border-color: var(--nier-ink) !important; --panel-shadow: none !important; --panel-border-radius: 0px !important;
  --panel-item-hover-bgcolor: var(--nier-paper-dark) !important; --panel-item-active-bgcolor: var(--nier-soft) !important;
  --panel-item-hover-color: var(--nier-ink) !important; --panel-separator-color: var(--nier-ink) !important;
  --background-color-box: var(--nier-paper) !important; --text-color: var(--nier-ink) !important;
}
panel-list, tooltip { background: var(--nier-paper) !important; color: var(--nier-ink) !important; border: 1px solid var(--nier-ink) !important; box-shadow: none !important; }
scrollbar, scrollbar * { appearance: none !important; background: var(--nier-paper) !important; }
"""

content = vars_ + """
@-moz-document url-prefix("about:") {
  :root { --in-content-page-background: var(--nier-paper) !important; --in-content-page-color: var(--nier-ink) !important;
    --in-content-box-background: var(--nier-paper-dark) !important; --in-content-primary-button-background: var(--nier-accent) !important;
    --in-content-border-color: var(--nier-ink) !important; --in-content-accent-color: var(--nier-accent) !important;
    --newtab-background-color: var(--nier-paper) !important; --newtab-text-primary-color: var(--nier-ink) !important; }
  html, body { background: var(--nier-paper) !important; color: var(--nier-ink) !important; font-family: var(--nier-font) !important; }
  * { border-radius: 0 !important; }
  *, *::before, *::after { transition: none !important; animation: none !important; }
  a { color: var(--nier-accent) !important; }
}
"""


prefs = """// written by tui/scripts/theme-browsers.py
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("ui.prefersReducedMotion", 1);
user_pref("toolkit.cosmeticAnimations.enabled", false);
user_pref("general.smoothScroll", false);
user_pref("browser.fullscreen.animate", false);
user_pref("browser.download.animateNotifications", false);
user_pref("browser.tabs.hoverPreview.enabled", false);
"""

START, END = "/* >>> nier-theme */", "/* <<< nier-theme */"
def put(path, body, comment=True):
    path.parent.mkdir(parents=True, exist_ok=True)
    old = path.read_text() if path.exists() else ""
    old = re.sub(re.escape(START) + r".*?" + re.escape(END) + r"\n?", "", old, flags=re.S)
    path.write_text(old + START + "\n" + body + END + "\n")

profiles = [home / ".config/mozilla/firefox/ukde7p80.default-release"]
profiles = [x for x in profiles if x]
if len(sys.argv) > 1: profiles = [pathlib.Path(a) for a in sys.argv[1:]]
for p in profiles:
    put(p / "chrome/userChrome.css", chrome)
    put(p / "chrome/userContent.css", content)
    uj = p / "user.js"
    old = uj.read_text() if uj.exists() else ""
    old = re.sub(r"// written by tui/scripts/theme-browsers\.py.*", "", old, flags=re.S)
    uj.write_text(old + prefs)
    print("themed", p)
