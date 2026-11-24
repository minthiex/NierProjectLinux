import QtQuick

// Tooltip of the title-bar buttons: a paper tag inside the bar, left of the buttons (it stays in the bar so an
// app window under the bar can never cover it). Empty text = hidden.
Rectangle {
    id: tip
    property string text: ""
    property string shown: ""          // keeps the last text while fading out

    onTextChanged: if (text !== "") shown = text
    opacity: text !== "" ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Theme.hoverMs } }

    width: label.implicitWidth + 16
    height: 20
    color: Theme.paper

    Rectangle { width: 4; height: parent.height; color: Theme.accent }

    Text {
        id: label
        x: 10
        anchors.verticalCenter: parent.verticalCenter
        text: tip.shown.toUpperCase()
        color: Theme.ink
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 3
        font.bold: true
        font.letterSpacing: 1
    }
}
