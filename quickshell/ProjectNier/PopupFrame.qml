import Quickshell
import Quickshell.Wayland
import QtQuick

// The frame of a popped-out app window. Hyprland draws its border (so that always moves with the window); the shell
// adds a title bar on top of the border (drag it to move the window, X puts the window back in its sub-function's
// content window) and a resize grip on the bottom-right corner. Bar and grip are overlay layer surfaces: they cannot
// follow a moving window frame by frame, so they fade out while it moves and come back where it stopped.
Scope {
    id: pf
    required property var modelData        // { slug, addr, name, sel }
    property var view                       // PopOut (pop-out state; view.view is NierScreen)

    readonly property string addr: modelData.addr
    readonly property var g: view.popGeo[addr] || null
    readonly property bool shown: g !== null && !g.fs
    readonly property bool moving: view.popMoving[addr] === true
    readonly property int b: view.popBorder
    readonly property int barH: view.headH
    readonly property int gripS: 18

    // while dragging, each surface stays where it was pressed: the pointer's offset from the press is the move
    property var frozen: null

    PanelWindow {
        id: bar
        readonly property var at: pf.frozen || pf.g
        visible: pf.shown
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "projectnier-popup"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; left: true }
        // sits on the window's top edge, as wide as the border; its bottom covers the top border line
        margins.left: at ? at.x - pf.b : 0
        margins.top: at ? Math.max(0, at.y - pf.barH) : 0
        implicitWidth: at ? Math.max(200, at.w + pf.b * 2) : 200
        implicitHeight: pf.barH

        Rectangle {
            anchors.fill: parent
            color: Theme.ink
            opacity: pf.moving ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Theme.hoverMs } }

            // drag anywhere on the bar (outside the X) to move the window; double-click puts it back
            MouseArea {
                id: moveHit
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property real px: 0
                property real py: 0
                onPressed: mouse => { px = mouse.x; py = mouse.y; pf.frozen = pf.g; pf.view.beginDrag(pf.addr, "move") }
                onPositionChanged: mouse => { if (pressed) pf.view.dragBy(mouse.x - px, mouse.y - py) }
                onReleased: { pf.view.endDrag(); pf.frozen = null }
                onCanceled: { pf.view.endDrag(); pf.frozen = null }
                onDoubleClicked: pf.view.popBack(pf.addr)
            }

            Text {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                width: tipTag.x - 24
                elide: Text.ElideRight
                text: pf.modelData.name
                color: Theme.paper
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.bold: true
                font.letterSpacing: 1
            }

            HeadTip {
                id: tipTag
                anchors.right: back.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: back.active ? back.tip : (moveHit.containsMouse && !moveHit.pressed ? "Drag to move" : "")
            }

            HeadButton {
                id: back
                z: 1
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                glyph: ""
                danger: true
                tip: "Close pop-up"
                onClicked: pf.view.popBack(pf.addr)
            }
        }

    }

    PanelWindow {
        visible: pf.shown
        readonly property var at: pf.frozen || pf.g
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "projectnier-popup"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; left: true }
        // on the bottom-right corner of the border, reaching a little inside the window
        margins.left: at ? at.x + at.w + pf.b - pf.gripS : 0
        margins.top: at ? at.y + at.h + pf.b - pf.gripS : 0
        implicitWidth: pf.gripS
        implicitHeight: pf.gripS

        Item {
            anchors.fill: parent
            opacity: pf.moving ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Theme.hoverMs } }

            // an ink corner (continuing the border) with three paper grip lines
            Rectangle { anchors.fill: parent; color: gripHit.containsMouse || gripHit.pressed ? Theme.accent : Theme.ink }
            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    readonly property int len: 6 + index * 4
                    width: len; height: 2
                    color: Theme.paper
                    x: pf.gripS - 3 - len / 2 - len / 2 * 0.7
                    y: pf.gripS - 3 - len / 2 * 0.7
                    rotation: -45
                    antialiasing: true
                }
            }
        }

        MouseArea {
            id: gripHit
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.SizeFDiagCursor
            property real px: 0
            property real py: 0
            onPressed: mouse => { px = mouse.x; py = mouse.y; pf.frozen = pf.g; pf.view.beginDrag(pf.addr, "resize") }
            onPositionChanged: mouse => { if (pressed) pf.view.dragBy(mouse.x - px, mouse.y - py) }
            onReleased: { pf.view.endDrag(); pf.frozen = null }
            onCanceled: { pf.view.endDrag(); pf.frozen = null }
        }
    }
}
