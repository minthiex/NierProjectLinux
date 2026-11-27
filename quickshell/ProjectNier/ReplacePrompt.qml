import Quickshell
import Quickshell.Wayland
import QtQuick

// Shown in the middle of the screen when a second app is started in a sub-function whose
// content window is already in use: close the open one and replace it, or keep it.
PanelWindow {
    id: win

    property var ask: null                 // { name, old, both } or null   both: KEEP BOTH is offered
    signal accepted()
    signal keptBoth()
    signal cancelled()

    visible: ask !== null
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "projectnier-prompt"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    Rectangle { anchors.fill: parent; color: Theme.ink; opacity: 0.4 }
    MouseArea { anchors.fill: parent }

    Rectangle {
        anchors.centerIn: parent
        width: 620
        height: head.height + body.height + 36
        color: Theme.paper
        border.width: 1
        border.color: Theme.ink

        Rectangle {
            id: head
            width: parent.width
            height: 30
            color: Theme.ink
            Rectangle { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; color: Theme.accent }
            Text {
                x: 30
                anchors.verticalCenter: parent.verticalCenter
                text: "REPLACE APPLICATION"
                color: Theme.paper
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.bold: true
                font.letterSpacing: 3
            }
        }

        Column {
            id: body
            x: 24
            y: head.height + 20
            width: parent.width - 48
            spacing: 14

            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: (win.ask ? win.ask.old : "") + " is already open in this category."
                color: Theme.ink
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 2
                font.bold: true
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: "Close it and replace it with " + (win.ask ? win.ask.name : "") + "?"
                      + (win.ask && win.ask.both ? " Or keep both: the window's title bar then switches between them." : "")
                color: Theme.inkSoft
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }
            Row {
                spacing: 10
                ChipButton { text: "CLOSE AND REPLACE"; onClicked: win.accepted() }
                ChipButton { text: "KEEP BOTH"; visible: win.ask !== null && win.ask.both === true; onClicked: win.keptBoth() }
                ChipButton { text: "KEEP CURRENT"; onClicked: win.cancelled() }
            }
        }
    }
}
