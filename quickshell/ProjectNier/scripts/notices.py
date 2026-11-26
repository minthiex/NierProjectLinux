#!/usr/bin/env python3
"""Notification history (System -> Notifications), written by Notifications.qml to
~/.local/share/ProjectNier/notices.json (the last 100 notices, also the ones do-not-disturb held back).

  notices.py rows     panel rows, newest first (key TAB value)
  notices.py clear    forget them all
"""
import json
import os
import sys
import time

PATH = os.path.join(os.path.expanduser("~"), ".local", "share", "ProjectNier", "notices.json")


def clean(s):
    return " ".join(str(s).replace("\t", " ").split())


def row(key, value=""):
    print("%s\t%s\t\t" % (clean(key), clean(value)))


def load():
    try:
        with open(PATH, encoding="utf-8") as f:
            d = json.load(f)
        return d if isinstance(d, list) else []
    except (OSError, ValueError):
        return []


def rows():
    h = load()
    missed = sum(1 for n in h if n.get("missed"))
    row("HISTORY", "%d notices kept (the last 100)" % len(h) + ("  ·  %d held back by DND" % missed if missed else ""))
    if not h:
        return
    print("\t\t\t")
    today = time.strftime("%Y-%m-%d")
    for n in reversed(h[-40:]):
        t = time.localtime(n.get("t", 0) / 1000)
        when = time.strftime("%H:%M" if time.strftime("%Y-%m-%d", t) == today else "%m-%d %H:%M", t)
        text = n.get("summary", "")
        if n.get("body"):
            text += "  —  " + n["body"]
        row(("◆ " if n.get("missed") else "") + when + "  " + (n.get("app") or "?").upper(), text)


def clear():
    tmp = PATH + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write("[]")
    os.replace(tmp, PATH)


if __name__ == "__main__":
    if sys.argv[1:] == ["rows"]:
        rows()
    elif sys.argv[1:] == ["clear"]:
        clear()
    else:
        sys.exit(__doc__)
