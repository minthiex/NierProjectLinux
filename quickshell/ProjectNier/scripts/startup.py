#!/usr/bin/env python3
"""Startup Apps (Configuration -> Startup Apps): the programs in ~/.config/autostart (XDG autostart).

  startup.py rows            panel rows (key TAB value TAB percent TAB click)
  startup.py toggle <file>   switch one entry on / off
  startup.py add <text>      add an installed app (desktop id, name or command name) or a plain command
  startup.py prune           move the switched-off entries to ~/.local/share/ProjectNier/autostart-removed/
  startup.py run [--now]     start the switched-on entries; without --now only once per Hyprland session
                             (the shell calls this when it starts, so a shell restart does not start them again)

Only the user's folder is used: the system one (/etc/xdg/autostart) is full of KDE / Plasma helpers.
"""
import os
import re
import shlex
import shutil
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
CONFIG = os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")
FOLDER = os.path.join(CONFIG, "autostart")
DATA = os.path.join(HOME, ".local", "share", "ProjectNier")
REMOVED = os.path.join(DATA, "autostart-removed")
LOG = os.path.join(DATA, "startup.log")
SELF = os.path.abspath(__file__)
DESKTOP = "Hyprland"
DEFAULT_DELAY = 4            # seconds: the tray, the keyring (KeePassXC) and the shell are up by then


def q(s):
    return shlex.quote(s)


def row(key, value="", pct="", click=""):
    clean = lambda s: str(s).replace("\t", " ").replace("\n", " ")
    print("\t".join([clean(key), clean(value), clean(pct), clean(click)]))


def notify(msg):
    subprocess.run(["notify-send", "-a", "ProjectNier", "Startup Apps", msg], check=False)


# ---- desktop files: only the [Desktop Entry] section is read / changed, the rest is kept as it is ----
def read_entry(path):
    vals, section = {}, None
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                s = line.strip()
                if s.startswith("["):
                    section = s
                elif section == "[Desktop Entry]" and "=" in s and not s.startswith("#"):
                    k, v = s.split("=", 1)
                    vals.setdefault(k.strip(), v.strip())
    except OSError:
        pass
    return vals


def set_keys(path, changes):
    with open(path, encoding="utf-8", errors="replace") as f:
        lines = f.read().splitlines()
    out, section, seen, entry_end = [], None, set(), None
    for line in lines:
        s = line.strip()
        if s.startswith("["):
            if section == "[Desktop Entry]":
                entry_end = len(out)
            section = s
        elif section == "[Desktop Entry]" and "=" in s and not s.startswith("#"):
            k = s.split("=", 1)[0].strip()
            if k in changes:
                if k in seen:
                    continue
                seen.add(k)
                line = k + "=" + changes[k]
        out.append(line)
    if entry_end is None:
        entry_end = len(out)
    while entry_end > 0 and out[entry_end - 1].strip() == "":
        entry_end -= 1
    missing = [k + "=" + v for k, v in changes.items() if k not in seen]
    out[entry_end:entry_end] = missing
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    os.replace(tmp, path)


def enabled(e):
    return e.get("Hidden", "false").lower() != "true" and e.get("X-GNOME-Autostart-enabled", "true").lower() != "false"


def for_this_desktop(e):
    only = [x for x in e.get("OnlyShowIn", "").split(";") if x]
    never = [x for x in e.get("NotShowIn", "").split(";") if x]
    return (not only or DESKTOP in only) and DESKTOP not in never


def command(e):
    """the Exec line without its field codes (%U, %f ...), ready for sh -c"""
    cmd = re.sub(r"%[fFuUdDnNickvm]", "", e.get("Exec", "")).replace("%%", "%")
    return " ".join(cmd.split())


def program(cmd):
    try:
        words = shlex.split(cmd)
    except ValueError:
        words = cmd.split()
    while words and (words[0] == "env" or "=" in words[0]):
        words.pop(0)
    return words[0] if words else ""


def installed(cmd):
    p = program(cmd)
    return bool(p) and (shutil.which(p) is not None or (os.path.isabs(p) and os.access(p, os.X_OK)))


def entries():
    try:
        names = sorted(n for n in os.listdir(FOLDER) if n.endswith(".desktop"))
    except OSError:
        names = []
    out = []
    for n in names:
        path = os.path.join(FOLDER, n)
        e = read_entry(path)
        if e.get("Type", "Application") != "Application":
            continue
        out.append((path, e))
    return out


# ---- commands ----
def cmd_rows():
    es = entries()
    on = [x for x in es if enabled(x[1])]
    row("STARTS AT LOGIN", "%d of %d switched on" % (len(on), len(es)))
    row("FOLDER", FOLDER)
    row("CLICK", "an app to switch it on / off")
    print("\t\t\t")
    if not es:
        row("NO STARTUP APPS", "type an app name below to add one")
    for path, e in es:
        cmd = command(e)
        name = e.get("Name") or os.path.basename(path)[:-8]
        if not installed(cmd):
            state = "MISSING  " + program(cmd)
        elif not for_this_desktop(e):
            state = "NOT FOR HYPRLAND"
        else:
            state = "ON" if enabled(e) else "OFF"
            delay = e.get("X-GNOME-Autostart-Delay", "")
            if enabled(e) and delay.isdigit() and int(delay) > 0:
                state += "  +%ss" % delay
        row(name, state, "", "python3 %s toggle %s" % (q(SELF), q(path)))


def cmd_toggle(path):
    path = os.path.abspath(path)
    if os.path.dirname(path) != os.path.abspath(FOLDER) or not os.path.isfile(path):
        sys.exit("not a startup entry: " + path)
    on = not enabled(read_entry(path))
    set_keys(path, {"Hidden": "false", "X-GNOME-Autostart-enabled": "true" if on else "false"})


def app_dirs():
    data_home = os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share")
    dirs = [data_home] + (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
    seen, out = set(), []
    for d in dirs:
        a = os.path.join(d, "applications")
        if a not in seen and os.path.isdir(a):
            seen.add(a)
            out.append(a)
    return out


def find_app(text):
    want = text.lower().removesuffix(".desktop")
    exact, partial = [], []
    for d in app_dirs():
        for root, _, files in os.walk(d):
            for n in files:
                if not n.endswith(".desktop"):
                    continue
                path = os.path.join(root, n)
                e = read_entry(path)
                if e.get("Type") != "Application" or e.get("NoDisplay", "").lower() == "true" or not e.get("Exec"):
                    continue
                ident = n[:-8].lower()
                name = e.get("Name", "").lower()
                prog = os.path.basename(program(command(e))).lower()
                if want in (ident, name, prog) or ident.endswith("." + want):
                    exact.append(path)
                elif want in name:
                    partial.append(path)
    hits = exact or partial
    return hits[0] if len(hits) == 1 or exact else (hits if hits else None)


def cmd_add(text):
    text = text.strip()
    if not text:
        return
    os.makedirs(FOLDER, exist_ok=True)
    hit = find_app(text)
    if isinstance(hit, list):
        names = ", ".join(sorted({read_entry(p).get("Name", "?") for p in hit})[:6])
        notify("Several apps match “%s”: %s. Type the full name." % (text, names))
        return
    if hit:
        dest = os.path.join(FOLDER, os.path.basename(hit))
        if os.path.exists(dest):
            set_keys(dest, {"Hidden": "false", "X-GNOME-Autostart-enabled": "true"})
        else:
            shutil.copyfile(hit, dest)
            set_keys(dest, {"X-GNOME-Autostart-enabled": "true"})
        notify("%s starts at login." % read_entry(dest).get("Name", text))
        return
    if not installed(text):
        notify("No app or command called “%s”." % text)
        return
    slug = re.sub(r"[^a-z0-9]+", "-", os.path.basename(program(text)).lower()).strip("-") or "command"
    dest = os.path.join(FOLDER, "projectnier-%s.desktop" % slug)
    n = 2
    while os.path.exists(dest):
        dest = os.path.join(FOLDER, "projectnier-%s-%d.desktop" % (slug, n))
        n += 1
    with open(dest, "w", encoding="utf-8") as f:
        f.write("[Desktop Entry]\nType=Application\nName=%s\nExec=%s\nX-GNOME-Autostart-enabled=true\n"
                % (os.path.basename(program(text)), text))
    notify("“%s” runs at login." % text)


def cmd_prune():
    gone = [p for p, e in entries() if not enabled(e)]
    if not gone:
        return
    stamp = time.strftime("%Y%m%d-%H%M%S")
    dest = os.path.join(REMOVED, stamp)
    os.makedirs(dest, exist_ok=True)
    for p in gone:
        shutil.move(p, os.path.join(dest, os.path.basename(p)))
    notify("Removed %d switched-off entr%s (kept in %s)." % (len(gone), "y" if len(gone) == 1 else "ies", dest))


# programs that only start another one (flatpak run org.x, python3 tool.py ...): for these the arguments say which
# program it is, else any flatpak / python process (this script itself is one) would count as "already running"
LAUNCHERS = re.compile(r"^(flatpak|snap|gtk-launch|dex|sh|bash|dash|zsh|fish|java|node|perl|ruby|uv|uvx|appimage-run"
                       r"|python[0-9.]*)$")


def running(cmd):
    try:
        words = shlex.split(cmd)
    except ValueError:
        words = cmd.split()
    while words and (words[0] == "env" or "=" in words[0]):
        words.pop(0)
    if not words:
        return False
    base = os.path.basename(words[0])
    pattern = "(.*/)?" + re.escape(base)
    if LAUNCHERS.match(base):
        if len(words) < 2:
            return False
        pattern += " " + re.escape(" ".join(words[1:]))
    return subprocess.run(["pgrep", "-f", "-x", pattern + "( .*)?"], stdout=subprocess.DEVNULL).returncode == 0


def cmd_run(now):
    if not now:
        runtime = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
        session = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE") or "nohypr"
        marker = os.path.join(runtime, "projectnier-startup-" + session)
        try:
            os.close(os.open(marker, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600))
        except FileExistsError:
            return                     # already done in this session (the shell was restarted / reloaded)
    os.makedirs(DATA, exist_ok=True)
    with open(LOG, "a", encoding="utf-8") as log:
        log.write("%s run%s\n" % (time.strftime("%F %T"), " (by hand)" if now else ""))
        for path, e in entries():
            name = e.get("Name") or os.path.basename(path)
            cmd = command(e)
            if not enabled(e) or not for_this_desktop(e) or not cmd:
                continue
            if not installed(cmd) or (e.get("TryExec") and not installed(e["TryExec"])):
                log.write("  skip %s: not installed\n" % name)
                continue
            if running(cmd):
                log.write("  skip %s: already running\n" % name)
                continue
            delay = e.get("X-GNOME-Autostart-Delay", "")
            delay = int(delay) if delay.isdigit() else (0 if now else DEFAULT_DELAY)
            if e.get("Terminal", "").lower() == "true":
                cmd = "kitty -e sh -c %s" % q(cmd)
            log.write("  start %s: %s\n" % (name, cmd))
            subprocess.Popen(["sh", "-c", "sleep %d; %s" % (delay, cmd)], start_new_session=True,
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             cwd=HOME)


def main(argv):
    if not argv:
        sys.exit(__doc__)
    c, rest = argv[0], argv[1:]
    if c == "rows":
        cmd_rows()
    elif c == "toggle" and rest:
        cmd_toggle(rest[0])
    elif c == "add":
        cmd_add(" ".join(rest))
    elif c == "prune":
        cmd_prune()
    elif c == "run":
        cmd_run("--now" in rest)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
