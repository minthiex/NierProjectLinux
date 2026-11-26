#!/usr/bin/env python3
"""usage: pick-file.py [TITLE]
Asks for one file with the desktop's file chooser (xdg-desktop-portal FileChooser: its window is a portal window,
which the shell lets through) and prints its path, or nothing when cancelled. Messenger → ATTACH uses it."""
import os
import sys
import urllib.parse

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402


def main():
    title = sys.argv[1] if len(sys.argv) > 1 else "Choose a file"
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    token = "projectnier%d" % os.getpid()
    sender = bus.get_unique_name()[1:].replace(".", "_")
    handle = "/org/freedesktop/portal/desktop/request/%s/%s" % (sender, token)
    loop = GLib.MainLoop()
    result = {"path": ""}

    def on_response(_c, _s, _p, _i, _n, params):
        code, res = params.unpack()
        uris = res.get("uris") or []
        if code == 0 and uris:
            u = urllib.parse.urlparse(uris[0])
            if u.scheme == "file":
                result["path"] = urllib.parse.unquote(u.path)
        loop.quit()

    # subscribed before the call: the answer may come before OpenFile returns
    bus.signal_subscribe("org.freedesktop.portal.Desktop", "org.freedesktop.portal.Request", "Response", handle, None,
                         Gio.DBusSignalFlags.NONE, on_response)
    opts = {"handle_token": GLib.Variant("s", token), "multiple": GLib.Variant("b", False),
            "modal": GLib.Variant("b", True)}
    try:
        bus.call_sync("org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
                      "org.freedesktop.portal.FileChooser", "OpenFile",
                      GLib.Variant("(ssa{sv})", ("", title, opts)), GLib.VariantType("(o)"),
                      Gio.DBusCallFlags.NONE, 10000, None)
    except GLib.Error as e:
        print("error: " + e.message, file=sys.stderr)
        sys.exit(1)
    GLib.timeout_add_seconds(900, loop.quit)
    loop.run()
    if result["path"]:
        print(result["path"])


if __name__ == "__main__":
    main()
