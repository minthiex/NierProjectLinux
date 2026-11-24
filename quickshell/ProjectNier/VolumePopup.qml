import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import QtQuick

// Volume pop-up in the screen's style: appears at the bottom middle, above windows, whenever the volume or mute
// of the default output changes (keys, a mixer, an app), and leaves again by itself.
Scope {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink ? sink.audio : null
    readonly property real volume: audio ? audio.volume : 0
    readonly property bool muted: audio ? audio.muted : false
    readonly property int percent: Math.round(volume * 100)
    readonly property int segments: 20

    property bool armed: false          // ignore the values that arrive while the shell starts
    property bool shown: false

    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    Timer { interval: 1500; running: true; onTriggered: root.armed = true }
    Timer { id: hideTimer; interval: 1700; onTriggered: root.shown = false }

    function poke() {
        if (!armed) return
        shown = true
        hideTimer.restart()
    }
    onVolumeChanged: poke()
    onMutedChanged: poke()
    onSinkChanged: armed = false, rearm.restart()
    Timer { id: rearm; interval: 1500; onTriggered: root.armed = true }

    PanelWindow {
        id: win
        visible: root.shown || card.opacity > 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "projectnier-volume"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors { bottom: true }
        margins { bottom: 90 }
        implicitWidth: card.width
        implicitHeight: card.height
        color: "transparent"
        mask: Region {}                 // clicks go straight through

        Item {
            id: card
            width: 380
            height: head.height + body.height
            opacity: root.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.hoverMs } }
            transform: Translate { y: root.shown ? 0 : 12; Behavior on y { NumberAnimation { duration: Theme.hoverMs + 80; easing.type: Easing.OutCubic } } }

            Rectangle { anchors.fill: parent; color: Theme.paper; border.width: 1; border.color: Theme.ink }

            Rectangle {
                id: head
                width: parent.width
                height: 26
                color: Theme.ink
                Rectangle { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; color: root.muted ? Theme.accent : Theme.paper }
                Text {
                    x: 30
                    anchors.verticalCenter: parent.verticalCenter
                    text: "VOLUME"
                    color: Theme.paper
                    font.family: Theme.font
                    font.pixelSize: Theme.smallFontSize
                    font.bold: true
                    font.letterSpacing: 3
                }
            }

            Item {
                id: body
                y: head.height
                width: parent.width
                height: 54

                // segmented level bar
                Row {
                    id: bar
                    x: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Repeater {
                        model: root.segments
                        Rectangle {
                            required property int index
                            readonly property bool on: !root.muted && (index + 0.5) / root.segments <= Math.min(1, root.volume)
                            width: 10
                            height: 18
                            color: on ? Theme.ink : Theme.paperDark
                            Behavior on color { ColorAnimation { duration: 90 } }
                        }
                    }
                }
                Text {
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    text: root.muted ? "MUTED" : root.percent + "%"
                    color: root.muted ? Theme.accent : Theme.ink
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 2
                    font.bold: true
                }
            }
        }
    }
}
