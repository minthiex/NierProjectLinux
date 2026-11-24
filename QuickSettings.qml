import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import QtQuick

// Quick Settings: a small panel over everything (top right, under the health light) with the common toggles, so
// they do not need a trip to Network or System. Volume and microphone go through PipeWire (live); the rest through
// scripts/quick.sh. Opened by the sliders button at the top right of the screen, or:
//   qs -c ProjectNier ipc call quick toggle
// A click outside it (Hyprland focus grab) or the X closes it.
Scope {
    id: q
    property bool shown: false
    signal lockRequested()

    function toggle() { shown = !shown }
    onShownChanged: { if (shown) refresh(); grabDelay.restart(); suspendArmed = false }

    IpcHandler {
        target: "quick"
        function toggle(): void { q.toggle() }
        function open(): void { q.shown = true }
        function close(): void { q.shown = false }
    }

    // ---- state -------------------------------------------------------------------------------------
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [q.sink, q.source].filter(o => o) }
    readonly property int volume: sink && sink.audio ? Math.round(sink.audio.volume * 100) : -1
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
    readonly property bool micMuted: source && source.audio ? source.audio.muted : false
    function setVolume(p) { if (sink && sink.audio) { sink.audio.muted = false; sink.audio.volume = Math.max(0, Math.min(100, p)) / 100 } }

    property var st: ({})               // quick.sh state: wifi, bt, dnd, night, profile
    function refresh() { stateProc.running = false; stateProc.running = true }
    Process {
        id: stateProc
        command: ["sh", Quickshell.shellPath("scripts/quick.sh"), "state"]
        stdout: StdioCollector {
            onStreamFinished: {
                var o = {}
                text.split("\n").forEach(l => { var p = l.split("\t"); if (p.length === 2) o[p[0]] = p[1] })
                q.st = o
            }
        }
    }
    // flip one; the state is read again once the command is done (radios take a moment to report)
    function flip(what) {
        var p = flipComp.createObject(q, { command: ["sh", Quickshell.shellPath("scripts/quick.sh"), what] })
        p.running = true
    }
    Component {
        id: flipComp
        Process {
            id: fp
            onExited: { q.refresh(); later.restart(); fp.destroy(100) }
        }
    }
    Timer { id: later; interval: 1500; onTriggered: if (q.shown) q.refresh() }
    Timer { interval: 5000; repeat: true; running: q.shown; onTriggered: q.refresh() }

    property bool suspendArmed: false
    Timer { id: disarm; interval: 3000; onTriggered: q.suspendArmed = false }

    // ---- window -----------------------------------------------------------------------------------
    PanelWindow {
        id: win
        visible: q.shown || card.opacity > 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "projectnier-quick"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; right: true }
        margins { top: Theme.frameMargin + Theme.pad + 34; right: Theme.frameMargin + Theme.tabInset }
        implicitWidth: card.width
        implicitHeight: card.height
        color: "transparent"

        Timer { id: grabDelay; interval: 120; onTriggered: grab.active = q.shown }
        HyprlandFocusGrab {
            id: grab
            windows: [win]
            active: false
            onCleared: q.shown = false
        }

        Item {
            id: card
            width: 360
            height: head.height + body.implicitHeight + 24
            opacity: q.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.hoverMs } }
            transform: Translate { y: q.shown ? 0 : -10; Behavior on y { NumberAnimation { duration: Theme.hoverMs + 80; easing.type: Easing.OutCubic } } }

            Rectangle { anchors.fill: parent; color: Theme.paper; border.width: 1; border.color: Theme.ink }

            // header
            Rectangle {
                id: head
                width: parent.width
                height: 30
                color: Theme.ink
                Rectangle { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 9; height: 9; color: Theme.paper }
                Text {
                    x: 30
                    anchors.verticalCenter: parent.verticalCenter
                    text: "QUICK SETTINGS"
                    color: Theme.paper
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    font.letterSpacing: 2
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: ""
                    color: closeHit.containsMouse ? Theme.accent : Theme.paper
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    MouseArea { id: closeHit; anchors.fill: parent; anchors.margins: -8; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: q.shown = false }
                }
            }

            Column {
                id: body
                x: 12
                y: head.height + 12
                width: parent.width - 24
                spacing: 8

                // volume: − / value (click = mute) / +
                Row {
                    spacing: 8
                    Text {
                        width: 128; anchors.verticalCenter: parent.verticalCenter
                        text: "VOLUME"; color: Theme.ink
                        font.family: Theme.font; font.pixelSize: Theme.fontSize; font.letterSpacing: 1
                    }
                    ChipButton { text: "−"; enabledLook: q.volume >= 0; onClicked: q.setVolume(q.volume - 5) }
                    ChipButton {
                        width: 92
                        text: q.volume < 0 ? "NONE" : q.muted ? "MUTED" : q.volume + "%"
                        selected: q.muted
                        enabledLook: q.volume >= 0
                        onClicked: if (q.sink && q.sink.audio) q.sink.audio.muted = !q.sink.audio.muted
                    }
                    ChipButton { text: "+"; enabledLook: q.volume >= 0; onClicked: q.setVolume(q.volume + 5) }
                }

                Repeater {
                    model: [
                        { key: "mic", label: "MICROPHONE" },
                        { key: "wifi", label: "WI-FI" },
                        { key: "bt", label: "BLUETOOTH" },
                        { key: "dnd", label: "DO NOT DISTURB" },
                        { key: "night", label: "NIGHT LIGHT" },
                        { key: "profile", label: "POWER PROFILE" }
                    ]
                    Row {
                        id: r
                        required property var modelData
                        spacing: 8
                        readonly property string value: {
                            if (modelData.key === "mic") return q.source ? (q.micMuted ? "MUTED" : "ON") : "NONE"
                            var v = q.st[modelData.key]
                            return v === undefined ? "…" : String(v).toUpperCase()
                        }
                        Text {
                            width: 128; anchors.verticalCenter: parent.verticalCenter
                            text: r.modelData.label; color: Theme.ink
                            font.family: Theme.font; font.pixelSize: Theme.fontSize; font.letterSpacing: 1
                        }
                        ChipButton {
                            width: 200
                            text: r.value
                            // lit = the thing is on (for the microphone: lit while muted, the state worth noticing)
                            selected: r.value === "ON" || (r.modelData.key === "mic" && r.value === "MUTED")
                            enabledLook: r.value !== "NONE" && r.value !== "…"
                            onClicked: {
                                if (r.modelData.key === "mic") { if (q.source && q.source.audio) q.source.audio.muted = !q.source.audio.muted }
                                else q.flip(r.modelData.key)
                            }
                        }
                    }
                }

                Rectangle { width: body.width; height: 1; color: Theme.inkSoft }

                Row {
                    spacing: 8
                    ChipButton { text: "LOCK"; onClicked: { q.shown = false; q.lockRequested() } }
                    ChipButton {
                        text: q.suspendArmed ? "CLICK AGAIN TO SUSPEND" : "SUSPEND"
                        selected: q.suspendArmed
                        onClicked: {
                            if (!q.suspendArmed) { q.suspendArmed = true; disarm.restart(); return }
                            q.shown = false
                            q.lockRequested()
                            Quickshell.execDetached(["systemctl", "suspend"])
                        }
                    }
                }
            }
        }
    }
}
