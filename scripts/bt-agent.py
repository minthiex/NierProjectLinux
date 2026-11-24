#!/usr/bin/env python3
"""BlueZ pairing agent for the shell's Bluetooth manager (BluetoothAgent.qml).

Registers as the default org.bluez.Agent1 ("KeyboardDisplay") and turns every question BlueZ asks into one JSON line
on stdout; the shell answers with one JSON line on stdin.

  out: {"id": N, "kind": "confirm"|"pin"|"passkey"|"authorize"|"service", "device": path, "passkey": "123456", "uuid": ...}
       {"kind": "display-passkey"|"display-pin", "device": path, "passkey": "...", "entered": n}   (no answer needed)
       {"kind": "cancel"}                                                                          (BlueZ gave up)
       {"kind": "ready"} | {"kind": "error", "message": "..."}
  in:  {"id": N, "ok": true|false, "value": "1234"}     value = the PIN / passkey for "pin" / "passkey"
Standard library + GObject introspection (Gio) only.
"""
import json
import sys

from gi.repository import Gio, GLib

AGENT_PATH = "/org/projectnier/btagent"
IFACE_XML = """
<node>
  <interface name="org.bluez.Agent1">
    <method name="Release"/>
    <method name="RequestPinCode"><arg type="o" direction="in"/><arg type="s" direction="out"/></method>
    <method name="DisplayPinCode"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
    <method name="RequestPasskey"><arg type="o" direction="in"/><arg type="u" direction="out"/></method>
    <method name="DisplayPasskey"><arg type="o" direction="in"/><arg type="u" direction="in"/><arg type="q" direction="in"/></method>
    <method name="RequestConfirmation"><arg type="o" direction="in"/><arg type="u" direction="in"/></method>
    <method name="RequestAuthorization"><arg type="o" direction="in"/></method>
    <method name="AuthorizeService"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
    <method name="Cancel"/>
  </interface>
</node>
"""

pending = {}        # id -> (invocation, kind)
next_id = [0]


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def ask(invocation, kind, **extra):
    next_id[0] += 1
    pending[next_id[0]] = (invocation, kind)
    emit(dict(id=next_id[0], kind=kind, **extra))


def reject(invocation, msg="org.bluez.Error.Rejected"):
    invocation.return_dbus_error(msg, "rejected by the user")


def on_call(conn, sender, path, iface, method, params, invocation):
    a = params.unpack()
    if method == "RequestConfirmation":
        ask(invocation, "confirm", device=a[0], passkey="%06d" % a[1])
    elif method == "RequestPinCode":
        ask(invocation, "pin", device=a[0])
    elif method == "RequestPasskey":
        ask(invocation, "passkey", device=a[0])
    elif method == "RequestAuthorization":
        ask(invocation, "authorize", device=a[0])
    elif method == "AuthorizeService":
        ask(invocation, "service", device=a[0], uuid=a[1])
    elif method == "DisplayPasskey":
        emit({"kind": "display-passkey", "device": a[0], "passkey": "%06d" % a[1], "entered": a[2]})
        invocation.return_value(None)
    elif method == "DisplayPinCode":
        emit({"kind": "display-pin", "device": a[0], "passkey": a[1]})
        invocation.return_value(None)
    elif method == "Cancel":
        for inv, _ in pending.values():
            reject(inv, "org.bluez.Error.Canceled")
        pending.clear()
        emit({"kind": "cancel"})
        invocation.return_value(None)
    else:                                   # Release
        invocation.return_value(None)


def on_stdin(channel, cond):
    if cond & (GLib.IO_HUP | GLib.IO_ERR):
        loop.quit()                          # the shell went away
        return False
    line = channel.readline()
    if not line:
        loop.quit()
        return False
    try:
        msg = json.loads(line)
        inv, kind = pending.pop(int(msg["id"]))
    except (ValueError, KeyError, TypeError):
        return True
    if not msg.get("ok"):
        reject(inv)
    elif kind == "pin":
        inv.return_value(GLib.Variant("(s)", (str(msg.get("value", "")),)))
    elif kind == "passkey":
        try:
            inv.return_value(GLib.Variant("(u)", (int(msg.get("value", "")),)))
        except ValueError:
            reject(inv)
    else:
        inv.return_value(None)
    return True


try:
    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    node = Gio.DBusNodeInfo.new_for_xml(IFACE_XML)
    bus.register_object(AGENT_PATH, node.interfaces[0], on_call, None, None)
    mgr = Gio.DBusProxy.new_sync(bus, Gio.DBusProxyFlags.NONE, None, "org.bluez", "/org/bluez",
                                 "org.bluez.AgentManager1", None)
    mgr.call_sync("RegisterAgent", GLib.Variant("(os)", (AGENT_PATH, "KeyboardDisplay")), Gio.DBusCallFlags.NONE, -1, None)
    mgr.call_sync("RequestDefaultAgent", GLib.Variant("(o)", (AGENT_PATH,)), Gio.DBusCallFlags.NONE, -1, None)
except GLib.Error as e:
    emit({"kind": "error", "message": e.message})
    sys.exit(1)

emit({"kind": "ready"})
loop = GLib.MainLoop()
ch = GLib.IOChannel.unix_new(sys.stdin.fileno())
GLib.io_add_watch(ch, GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, on_stdin)
try:
    loop.run()
finally:
    try:
        mgr.call_sync("UnregisterAgent", GLib.Variant("(o)", (AGENT_PATH,)), Gio.DBusCallFlags.NONE, 2000, None)
    except GLib.Error:
        pass
