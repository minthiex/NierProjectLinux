import Quickshell
import Quickshell.Wayland
import QtQuick

// Shown in the middle of the screen, above everything, when an application tried to open outside
// the content window. It was closed; this asks which menu and sub-function it belongs to.
PanelWindow {
    id: win

    property var app: null                 // { cls, name, cmd } or null
    property var suggestion: null          // { menu, sub, creating } pre-selected for this kind of app, or null
    property var pages: []                 // [{ label, subs: [{ name }] }]
    signal accepted(string menu, string sub)
    signal dismissed()

    property int menuIndex: 0
    property string subName: ""
    property bool creating: false
    readonly property var subs: pages[menuIndex] ? pages[menuIndex].subs : []
    readonly property string chosen: creating ? newField.text.trim() : subName
    readonly property bool ready: chosen !== ""

    function reset() {
        menuIndex = 0; subName = ""; creating = false; newField.text = ""
        var sg = suggestion
        if (!sg) return
        for (var i = 0; i < pages.length; i++) if (pages[i].label === sg.menu) menuIndex = i
        if (sg.creating) { creating = true; newField.text = sg.sub }
        else subName = sg.sub
    }
    onAppChanged: reset()
    onSuggestionChanged: reset()

    visible: app !== null
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "projectnier-prompt"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    // dim everything behind; a click outside the box does nothing (the question has to be answered)
    Rectangle { anchors.fill: parent; color: Theme.ink; opacity: 0.4 }
    MouseArea { anchors.fill: parent }

    Rectangle {
        id: box
        anchors.centerIn: parent
        width: 860
        height: head.height + body.height + 36
        color: Theme.paper
        border.width: 1
        border.color: Theme.ink

        // title bar
        Rectangle {
            id: head
            width: parent.width
            height: 30
            color: Theme.ink
            Rectangle { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; color: Theme.accent }
            Text {
                x: 30
                anchors.verticalCenter: parent.verticalCenter
                text: "UNREGISTERED APPLICATION"
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
                text: (win.app ? win.app.name : "") + " tried to open outside a menu, so it was closed."
                color: Theme.ink
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 2
                font.bold: true
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: "Applications may only run inside the content window. Choose the menu and category it belongs to and it will open there from now on."
                color: Theme.inkSoft
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }

            // menu
            Text { text: "MENU"; color: Theme.inkSoft; font.family: Theme.font; font.pixelSize: Theme.smallFontSize; font.letterSpacing: 3; font.bold: true }
            Flow {
                width: parent.width
                spacing: 8
                Repeater {
                    model: win.pages
                    ChipButton {
                        required property var modelData
                        required property int index
                        text: modelData.label.toUpperCase()
                        selected: win.menuIndex === index
                        onClicked: { win.menuIndex = index; win.subName = ""; win.creating = false }
                    }
                }
            }

            // sub-function
            Text { text: "CATEGORY"; color: Theme.inkSoft; font.family: Theme.font; font.pixelSize: Theme.smallFontSize; font.letterSpacing: 3; font.bold: true }
            Flickable {
                width: parent.width
                height: Math.min(150, subFlow.height)
                contentHeight: subFlow.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Flow {
                    id: subFlow
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: win.subs
                        ChipButton {
                            required property var modelData
                            text: modelData.name
                            selected: !win.creating && win.subName === modelData.name
                            onClicked: { win.creating = false; win.subName = modelData.name }
                        }
                    }
                    ChipButton {
                        text: "+ NEW"
                        selected: win.creating
                        onClicked: { win.creating = true; win.subName = ""; newField.forceActiveFocus() }
                    }
                }
            }

            // name of a new sub-function
            Rectangle {
                visible: win.creating
                width: parent.width
                height: win.creating ? 30 : 0
                color: "transparent"
                border.width: 1
                border.color: Theme.ink
                Rectangle { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 9; height: 9; color: Theme.ink }
                TextInput {
                    id: newField
                    x: 30
                    width: parent.width - 42
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.ink
                    selectionColor: Theme.ink
                    selectedTextColor: Theme.paper
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    clip: true
                    onAccepted: if (win.ready) win.accepted(win.pages[win.menuIndex].label, win.chosen)
                    Text {
                        visible: newField.text === "" && !newField.activeFocus
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Name of the new category, then Enter"
                        color: Theme.inkSoft
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                    }
                }
            }

            // answer
            Row {
                spacing: 10
                ChipButton {
                    text: "ADD AND OPEN"
                    enabledLook: win.ready
                    onClicked: win.accepted(win.pages[win.menuIndex].label, win.chosen)
                }
                ChipButton {
                    text: "CANCEL"
                    onClicked: win.dismissed()
                }
            }
        }
    }
}
