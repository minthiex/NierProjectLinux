import QtQuick

// One tab. Resting: muted paper-dark plate with a dark icon box. Hover / active:
// a dark bar wipes in from the left, text turns paper colour, the icon box inverts.
Item {
    id: root
    property string icon
    property string label
    property string badge: ""
    signal clicked()

    property bool selected: false
    readonly property bool active: hit.containsMouse || selected

    implicitWidth: Theme.menuPad + Theme.iconBox + 8 + name.width + Theme.menuPad + 6
    implicitHeight: Theme.menuH

    // resting plate
    Rectangle { anchors.fill: parent; color: Theme.paperDark }

    // hover bar
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.active ? root.width : 0
        color: Theme.ink
        Behavior on width { NumberAnimation { duration: Theme.hoverMs; easing.type: Easing.OutCubic } }
    }

    // icon box
    Rectangle {
        id: box
        x: Theme.menuPad - 4
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.iconBox
        height: Theme.iconBox
        color: root.active ? Theme.paper : Theme.ink
        Behavior on color { ColorAnimation { duration: Theme.hoverMs } }

        Text {
            anchors.centerIn: parent
            text: root.icon
            color: root.active ? Theme.ink : Theme.paper
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
            Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
        }
    }

    Text {
        id: name
        x: box.x + box.width + 8
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.StyledText      // the (N) badge is bold
        text: root.label.toUpperCase().replace(/&/g, "&amp;").replace(/</g, "&lt;") + (root.badge !== "" ? " <b>" + root.badge + "</b>" : "")
        color: root.active ? Theme.paper : Theme.ink
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        font.letterSpacing: 2
        Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
    }

    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
