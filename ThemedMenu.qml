import Quickshell
import Quickshell.Hyprland
import QtQuick

// Context menu in the screen's style: a paper box with tan rows; hover wipes a row dark.
//   items: [{ text, enabled?, separator?, checked?, danger?, confirm?, keepOpen?, run }]
// A "danger" row wipes in the accent colour, a "confirm" row needs a second click.
PopupWindow {
    id: root
    property Item target
    property var items: []

    anchor.item: target
    anchor.edges: Edges.Top
    anchor.gravity: Edges.Top
    anchor.adjustment: PopupAdjustment.All

    implicitWidth: 250
    implicitHeight: col.height + 12
    color: "transparent"

    function open() { Menus.show(root) }

    // dismissal: a click anywhere outside (NierScreen calls Menus.closeAll()), another menu opening,
    // the pointer leaving the menu after it was in it, or the compositor's focus grab letting go
    property bool entered: false
    onVisibleChanged: { entered = false; leaveTimer.stop(); grabDelay.restart() }
    Timer { id: leaveTimer; interval: 450; onTriggered: root.visible = false }
    Timer { id: grabDelay; interval: 120; onTriggered: grab.active = root.visible }

    HoverHandler {
        onHoveredChanged: {
            if (hovered) { root.entered = true; leaveTimer.stop() }
            else if (root.entered) leaveTimer.restart()
        }
    }

    HyprlandFocusGrab {
        id: grab
        windows: [root]
        active: false
        onCleared: root.visible = false
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.paper
        border.width: 1
        border.color: Theme.ink
    }

    Column {
        id: col
        x: 6
        y: 6
        width: parent.width - 12
        spacing: 4

        Repeater {
            model: root.items

            Item {
                id: row
                required property var modelData
                property bool armed: false
                readonly property bool sep: modelData.separator === true
                readonly property bool ok: modelData.enabled !== false
                readonly property bool lit: ok && (hit.containsMouse || armed)

                width: col.width
                height: sep ? 7 : 26

                Timer { id: disarm; interval: 3000; onTriggered: row.armed = false }

                // separator
                Rectangle { visible: row.sep; anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 1; color: Theme.paperDark }

                // row
                Rectangle { visible: !row.sep; anchors.fill: parent; color: Theme.paperDark }
                Rectangle {
                    visible: !row.sep
                    height: parent.height
                    width: row.lit ? parent.width : 0
                    color: row.modelData.danger === true ? Theme.accent : Theme.ink
                    Behavior on width { NumberAnimation { duration: Theme.hoverMs; easing.type: Easing.OutCubic } }
                }
                Rectangle {
                    visible: !row.sep
                    x: 9
                    anchors.verticalCenter: parent.verticalCenter
                    width: 9; height: 9
                    color: row.lit ? Theme.paper : Theme.ink
                    opacity: row.ok ? 1 : 0.35
                }
                // check mark for ticked entries
                Rectangle {
                    visible: !row.sep && row.modelData.checked === true
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3; height: 3
                    color: row.lit ? Theme.ink : Theme.paper
                }
                Text {
                    visible: !row.sep
                    x: 28
                    width: parent.width - 28 - (row.modelData.hasChildren === true ? 22 : 10)
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: row.modelData.text === undefined ? "" : (row.armed ? "Click again: " + row.modelData.text : row.modelData.text)
                    color: row.lit ? Theme.paper : (row.ok ? Theme.ink : Theme.inkSoft)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                }
                Text {
                    visible: !row.sep && row.modelData.hasChildren === true
                    anchors.right: parent.right
                    anchors.rightMargin: 9
                    anchors.verticalCenter: parent.verticalCenter
                    text: "▸"
                    color: row.lit ? Theme.paper : Theme.ink
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                }

                MouseArea {
                    id: hit
                    anchors.fill: parent
                    enabled: !row.sep && row.ok
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (row.modelData.confirm === true && !row.armed) {
                            row.armed = true
                            disarm.restart()
                            return
                        }
                        row.armed = false
                        if (row.modelData.keepOpen !== true) root.visible = false
                        if (row.modelData.run) row.modelData.run()
                    }
                }
            }
        }
    }
}
