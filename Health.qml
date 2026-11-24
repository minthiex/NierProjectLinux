import Quickshell
import Quickshell.Io
import QtQuick

// Health light: watches what the screen depends on (Messenger connection, its Docker bridge, mail) and says when
// something is broken. Shown as the mark at the top right of NierScreen; click it for System → Self Check, whose
// REPAIR button runs scripts/repair.sh. A problem only counts after a grace period, so a retry blip or the
// CONNECTING at login never lights it up.
//   qs -c ProjectNier ipc call health status      -> OK | MESSENGER OFFLINE, BRIDGE DOWN ...
Scope {
    id: h
    required property var matrix          // MatrixClient
    required property var mail            // MailClient
    signal broke(string summary)          // healthy -> not healthy (once per breakdown)

    readonly property var containers: ["fbtui-synapse", "fbtui-meta"]
    property int messengerGrace: 90000
    property int mailGrace: 300000

    // ---- Messenger: not CONNECTED since when (0 = connected) ----
    property double msgBadSince: 0
    function trackMsg() {
        if (!matrix || matrix.status === "CONNECTED") msgBadSince = 0
        else if (msgBadSince === 0) msgBadSince = Date.now()
    }
    Connections { target: h.matrix; function onStatusChanged() { h.trackMsg() } }

    // ---- mail (only when a login is saved) ----
    property double mailBadSince: 0
    function mailBad() { return mail && mail.configured && (mail.status === "OFFLINE" || mail.status === "LOGIN REFUSED") }
    function trackMail() {
        if (!mailBad()) mailBadSince = 0
        else if (mailBadSince === 0) mailBadSince = Date.now()
    }
    Connections { target: h.mail; function onStatusChanged() { h.trackMail() } function onConfiguredChanged() { h.trackMail() } }

    // ---- the bridge containers: down on two checks in a row ----
    property var downCount: ({})          // container -> checks in a row it was not running
    Process {
        id: dockerCheck
        command: ["docker", "inspect", "-f", "{{.Name}} {{.State.Status}}"].concat(h.containers)
        stdout: StdioCollector {
            onStreamFinished: {
                var running = {}
                text.split("\n").forEach(l => {
                    var p = l.trim().replace(/^\//, "").split(" ")
                    if (p.length === 2 && p[1] === "running") running[p[0]] = true
                })
                var d = {}
                h.containers.forEach(c => d[c] = running[c] ? 0 : (h.downCount[c] || 0) + 1)
                h.downCount = d
            }
        }
    }
    Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: dockerCheck.running = true }

    // the grace periods are measured against this clock
    property double now: Date.now()
    Timer { interval: 15000; running: true; repeat: true; onTriggered: h.now = Date.now() }

    readonly property var problems: {
        var p = [], t = now
        var ms = matrix ? matrix.status : ""
        if (ms === "LOGIN EXPIRED") p.push("MESSENGER LOGIN EXPIRED")
        else if (msgBadSince > 0 && t - msgBadSince >= messengerGrace) p.push("MESSENGER " + (ms === "CONNECTING" || ms === "" ? "OFFLINE" : ms))
        var down = containers.filter(c => (downCount[c] || 0) >= 2)
        if (down.length > 0) p.push("BRIDGE DOWN")
        if (mailBadSince > 0 && t - mailBadSince >= mailGrace && mailBad()) p.push("MAIL " + mail.status)
        return p
    }
    readonly property bool ok: problems.length === 0
    readonly property string summary: ok ? "ALL SYSTEMS NOMINAL" : problems[0] + (problems.length > 1 ? "  +" + (problems.length - 1) : "")
    onOkChanged: if (!ok) broke(problems.join(", "))

    Component.onCompleted: { trackMsg(); trackMail() }

    IpcHandler {
        target: "health"
        function status(): string { return h.ok ? "OK" : h.problems.join(", ") }
        // what the light is looking at:   messenger=CONNECTED mail=CONNECTED fbtui-synapse=up fbtui-meta=up
        function detail(): string {
            return "messenger=" + (h.matrix ? h.matrix.status : "?") + " mail=" + (h.mail ? h.mail.status : "?") + " " +
                   h.containers.map(c => c + "=" + (h.downCount[c] === undefined ? "?" : h.downCount[c] === 0 ? "up" : "down")).join(" ")
        }
    }
}
