import QtQuick

// A selectable plate: tan at rest, a dark bar wipes in on hover and stays while selected.
Item {
    id: root
    property string text
    property bool selected: false
    property bool enabledLook: true
    signal clicked()

    readonly property bool lit: enabledLook && (hit.containsMouse || selected)

    implicitWidth: label.implicitWidth + 28
    implicitHeight: 28
    opacity: enabledLook ? 1 : 0.45

    Rectangle { anchors.fill: parent; color: Theme.paperDark }
    Rectangle {
        height: parent.height
        width: root.lit ? parent.width : 0
        color: Theme.ink
        Behavior on width { NumberAnimation { duration: Theme.hoverMs; easing.type: Easing.OutCubic } }
    }
    Rectangle {
        x: 9
        anchors.verticalCenter: parent.verticalCenter
        width: 7; height: 7
        color: root.lit ? Theme.paper : Theme.ink
    }
    Text {
        id: label
        x: 22
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        color: root.lit ? Theme.paper : Theme.ink
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        font.letterSpacing: 1
        Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
    }
    MouseArea {
        id: hit
        anchors.fill: parent
        enabled: root.enabledLook
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
