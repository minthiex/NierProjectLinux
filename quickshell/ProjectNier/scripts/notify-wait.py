#!/usr/bin/env python3
"""usage: notify-wait.py --app NAME --summary TEXT [--body MARKUP] [--icon NAME]
                         [--action KEY=LABEL ...] [--reply PLACEHOLDER] [--timeout MIN]
                         [--replaces ID] [--print-id]
Sends one desktop notification with buttons (and, with --reply, an inline reply field: NotificationCard's REPLY) and
waits for the answer, then prints one JSON line and exits:
  {"action": "KEY"}  a button (or, for KEY "default", the card itself) was clicked
  {"reply": "TEXT"}  a reply was sent
  {"closed": N}      the notice went away without an answer (expired, closed); also after --timeout minutes
--replaces ID updates notice ID in place (Messenger: one notice per chat); --print-id first prints {"id": N} as soon
as the notice is up (the caller needs it for --replaces).
The shell's own notification daemon (Notifications.qml) shows it, so do-not-disturb applies as usual."""
import argparse
import json
import sys

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

BUS, PATH, IFACE = "org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--app", required=True)
    ap.add_argument("--summary", required=True)
    ap.add_argument("--body", default="")
    ap.add_argument("--icon", default="")
    ap.add_argument("--action", action="append", default=[])
    ap.add_argument("--reply", default=None)
    ap.add_argument("--timeout", type=float, default=15)
    ap.add_argument("--replaces", type=int, default=0)
    ap.add_argument("--print-id", action="store_true")
    a = ap.parse_args()

    actions = []
    for spec in a.action:
        key, _, label = spec.partition("=")
        actions += [key, label or key]
    hints = {}
    if a.reply is not None:
        actions += ["inline-reply", "Reply"]
        hints["x-kde-reply-placeholder-text"] = GLib.Variant("s", a.reply)

    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    loop = GLib.MainLoop()
    state = {"id": None, "result": None, "early": []}

    def finish(result):
        if state["result"] is None:
            state["result"] = result
            loop.quit()

    def on_signal(_conn, _sender, _path, _iface, name, params):
        args = params.unpack()
        if state["id"] is None:                   # a signal that came before Notify returned: keep it for later
            state["early"].append((name, args))
            return
        handle(name, args)

    def handle(name, args):
        if args[0] != state["id"]:
            return
        if name == "ActionInvoked" and args[1] != "inline-reply":
            finish({"action": args[1]})
        elif name == "NotificationReplied":
            finish({"reply": args[1]})
        elif name == "NotificationClosed":
            finish({"closed": args[1]})

    for sig in ("ActionInvoked", "NotificationReplied", "NotificationClosed"):
        bus.signal_subscribe(BUS, IFACE, sig, PATH, None, Gio.DBusSignalFlags.NONE, on_signal)

    try:
        r = bus.call_sync(BUS, PATH, IFACE, "Notify",
                          GLib.Variant("(susssasa{sv}i)", (a.app, a.replaces, a.icon, a.summary, a.body, actions, hints, -1)),
                          GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, 10000, None)
    except GLib.Error as e:
        print(json.dumps({"error": e.message}))
        return
    state["id"] = r.unpack()[0]
    if a.print_id:
        print(json.dumps({"id": state["id"]}))
        sys.stdout.flush()
    for name, args in state["early"]:
        handle(name, args)
    GLib.timeout_add_seconds(int(a.timeout * 60), lambda: finish({"closed": 0}) or False)
    if state["result"] is None:
        loop.run()
    print(json.dumps(state["result"]))
    sys.stdout.flush()


if __name__ == "__main__":
    main()
