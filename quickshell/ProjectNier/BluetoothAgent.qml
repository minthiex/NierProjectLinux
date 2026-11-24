import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import QtQuick

// The pairing agent (scripts/bt-agent.py) as seen by the shell: BlueZ's questions ("does 123456 match?", "type the PIN")
// arrive here and are answered from the Bluetooth manager. One instance lives all the time, so a phone that starts
// pairing on its own still gets an answer.
Item {
    id: root

    property bool ready: false
    property string error: ""
    property var request: null       // { id, kind: confirm|pin|passkey|authorize|service, device, name, passkey, uuid }
    property var display: null       // { kind: display-passkey|display-pin, device, name, passkey }  type this on the device
    signal requested()               // a new question (the screen may want to bring the manager forward)

    function deviceFor(path) {
        var all = Bluetooth.devices.values
        for (var i = 0; i < all.length; i++) if (all[i].dbusPath === path) return all[i]
        return null
    }
    function nameOf(path) {
        var d = deviceFor(path)
        if (d) return d.name || d.deviceName || d.address
        return String(path).replace(/^.*dev_/, "").replace(/_/g, ":")
    }

    function answer(ok, value) {
        if (!request) return
        agent.write(JSON.stringify({ id: request.id, ok: ok, value: value === undefined ? "" : String(value) }) + "\n")
        request = null
    }
    function clearDisplay() { display = null }

    function handle(line) {
        var m
        try { m = JSON.parse(line) } catch (e) { return }
        if (m.kind === "ready") { ready = true; error = ""; return }
        if (m.kind === "error") { ready = false; error = m.message; return }
        if (m.kind === "cancel") { request = null; display = null; return }
        m.name = nameOf(m.device)
        if (m.kind === "display-passkey" || m.kind === "display-pin") { display = m; return }
        if (request) answer(false)               // a newer question replaces one nobody answered
        request = m
        requested()
    }

    Process {
        id: agent
        running: true
        stdinEnabled: true
        command: ["python3", "-I", Quickshell.shellPath("scripts/bt-agent.py")]
        stdout: SplitParser { onRead: line => root.handle(line) }
        onExited: { root.ready = false; root.request = null; restart.restart() }
    }
    // BlueZ restarted, or the adapter came and went: try again (never in a tight loop)
    Timer { id: restart; interval: 10000; onTriggered: agent.running = true }
}
