import QtQuick

// Title-bar button in the same style as the top tabs: a tan plate with a dark icon box.
// Hover: a dark bar wipes in from the left and the icon box inverts (the "danger" kind
// wipes in the accent colour instead).
Item {
    id: root
    property string glyph
    property bool danger: false
    property string tip: ""             // shown by a HeadTip in the bar while hovered
    signal clicked()

    readonly property bool active: hit.containsMouse

    width: 40
    height: 22

    // resting plate
    Rectangle { anchors.fill: parent; color: Theme.paperDark }

    // hover bar
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.active ? root.width : 0
        color: root.danger ? Theme.accent : Theme.ink
        Behavior on width { NumberAnimation { duration: Theme.hoverMs; easing.type: Easing.OutCubic } }
    }

    // icon box
    Rectangle {
        anchors.centerIn: parent
        width: 18
        height: 18
        color: root.active ? Theme.paper : Theme.ink
        Behavior on color { ColorAnimation { duration: Theme.hoverMs } }

        Text {
            anchors.centerIn: parent
            text: root.glyph
            color: root.active ? Theme.ink : Theme.paper
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
            Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
        }
    }

    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
