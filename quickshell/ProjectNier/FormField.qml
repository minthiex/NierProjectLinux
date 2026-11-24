import QtQuick

// A labelled text field in the screen's style (Email sign-in, Messenger setup). secret: shows dots.
Rectangle {
    id: f
    property string label
    property bool secret: false
    property alias text: input.text
    property alias input: input
    signal accepted()
    onActiveFocusChanged: if (activeFocus) input.forceActiveFocus()     // Tab lands on the frame: type in the box
    height: 30
    color: "transparent"
    border.width: 1
    border.color: Theme.ink

    Text {
        id: cap
        x: 10
        anchors.verticalCenter: parent.verticalCenter
        width: 84
        text: f.label
        color: Theme.inkSoft
        font.family: Theme.font
        font.pixelSize: Theme.smallFontSize
        font.letterSpacing: 2
    }
    TextInput {
        id: input
        x: 100
        width: parent.width - 112
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.ink
        selectionColor: Theme.ink
        selectedTextColor: Theme.paper
        echoMode: f.secret ? TextInput.Password : TextInput.Normal
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        clip: true
        onAccepted: f.accepted()
    }
}
