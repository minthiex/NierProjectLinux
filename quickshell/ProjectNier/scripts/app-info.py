#!/usr/bin/env python3
"""usage: app-info.py <pid> <window class>
Prints one JSON line about the program behind a window, for registering it in a sub-function (block-window.sh):
  {"cmd": "<shell-quoted command to start it again>", "name": "<app name from its .desktop file, or empty>"}
The command keeps options and folders but drops the files the program was opened with (a video, a document):
opening the sub-function later should start the app, not replay that one file."""
import json
import os
import shlex
import sys

INTERPRETERS = ("python", "python3", "sh", "bash", "node", "perl", "ruby", "java")


def argv_of(pid):
    try:
        raw = open(f"/proc/{pid}/cmdline", "rb").read()
    except OSError:
        return []
    return [a.decode(errors="replace") for a in raw.split(b"\0") if a]


def is_interpreter(path):
    b = os.path.basename(path)
    return b in INTERPRETERS or b.startswith("python")


def launch_cmd(argv):
    if not argv:
        return ""
    keep = [argv[0]]
    script_at = 1 if is_interpreter(argv[0]) else 0       # python3 /usr/bin/tool: the script is the program, keep it
    for i, a in enumerate(argv[1:], 1):
        if i == script_at:
            keep.append(a)
            continue
        if a.startswith("file://") or (not a.startswith("-") and os.path.isfile(a)):
            continue                                         # a file it was opened with
        if a.startswith(("/", "~")) and not os.path.isdir(os.path.expanduser(a)) and os.path.splitext(a)[1]:
            continue                                         # ... that was moved or deleted since
        keep.append(a)
    while len(keep) > 1 and keep[-1] == "--":                # "mpv ... --" with the file gone
        keep.pop()
    return shlex.join(keep)


def desktop_dirs():
    home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    dirs = [home] + (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
    dirs += [os.path.expanduser("~/.local/share/flatpak/exports/share"), "/var/lib/flatpak/exports/share"]
    seen = []
    for d in dirs:
        p = os.path.join(d, "applications")
        if p not in seen and os.path.isdir(p):
            seen.append(p)
    return seen


def read_entry(path):
    e, on = {}, False
    try:
        for line in open(path, encoding="utf-8", errors="replace"):
            line = line.strip()
            if line.startswith("["):
                on = line == "[Desktop Entry]"
                continue
            if on and "=" in line:
                k, v = line.split("=", 1)
                e.setdefault(k.strip(), v.strip())
    except OSError:
        pass
    return e


def class_key(c):
    c = c.lower()
    return c.rsplit(".", 1)[-1] if c.count(".") >= 2 else c


def app_name(cls, argv):
    exe = ""
    if argv:
        exe = os.path.basename(argv[1] if is_interpreter(argv[0]) and len(argv) > 1 else argv[0])
    want = cls.lower()
    best = (0, "")
    for d in desktop_dirs():
        for root, _, files in os.walk(d):
            for f in files:
                if not f.endswith(".desktop"):
                    continue
                e = read_entry(os.path.join(root, f))
                name = e.get("Name", "")
                if not name or e.get("Type", "Application") != "Application":
                    continue
                fid = f[:-8].lower()
                score = 0
                if e.get("StartupWMClass", "").lower() == want:
                    score = 3
                elif fid == want or class_key(fid) == class_key(want):
                    score = 2
                elif exe:
                    try:
                        bin_ = os.path.basename(shlex.split(e.get("Exec", ""))[0])
                    except (ValueError, IndexError):
                        bin_ = ""
                    if bin_ == exe:
                        score = 1
                # equally good: the plainer entry ("VSCodium" over "VSCodium - Wayland")
                if score > best[0] or (score and score == best[0] and len(name) < len(best[1])):
                    best = (score, name)
    if not best[1] and argv and is_interpreter(argv[0]) and exe:
        return exe[:1].upper() + exe[1:]                     # a script with a generic window class: name it after the script
    return best[1]


def main():
    if len(sys.argv) < 3:
        print(json.dumps({"cmd": "", "name": ""}))
        return
    argv = argv_of(sys.argv[1])
    print(json.dumps({"cmd": launch_cmd(argv), "name": app_name(sys.argv[2], argv)}))


if __name__ == "__main__":
    main()
