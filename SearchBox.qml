import QtQuick

// Search box at the top left: type an application, a sub-function or a menu, pick a result with the mouse or the
// arrow keys + Enter. The screen decides what a pick does (go to that sub-function / menu, or ask for a category).
Item {
    id: root
    property var results: []                 // [{ name, loc, kind }]  kind: "" (app) | "function" | "menu"; loc: where it leads, "" = nowhere yet
    property string text: field.text
    signal picked(var item)
    signal cleared()

    property int cur: 0
    readonly property bool open: field.activeFocus && field.text.trim() !== ""
    function reset() { field.text = ""; field.focus = false; cur = 0; cleared() }

    width: 300
    height: 30
    onResultsChanged: cur = 0

    Rectangle { anchors.fill: parent; color: Theme.paperDark; border.width: 1; border.color: Theme.ink }
    Rectangle { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; color: Theme.ink }

    TextInput {
        id: field
        x: 32
        width: parent.width - 44
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.ink
        selectionColor: Theme.ink
        selectedTextColor: Theme.paper
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        font.letterSpacing: 1
        clip: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Down) { root.cur = Math.min(root.results.length - 1, root.cur + 1); event.accepted = true }
            else if (event.key === Qt.Key_Up) { root.cur = Math.max(0, root.cur - 1); event.accepted = true }
            else if (event.key === Qt.Key_Escape) { root.reset(); event.accepted = true }
        }
        // focus went elsewhere (a click on another window, for instance): clear it
        onActiveFocusChanged: if (!activeFocus && text !== "") Qt.callLater(function () { if (!field.activeFocus) root.reset() })
        onAccepted: if (root.results.length > 0) root.choose(root.results[Math.min(root.cur, root.results.length - 1)])

        Text {
            visible: field.text === "" && !field.activeFocus
            text: "SEARCH APPS & FUNCTIONS"
            color: Theme.inkSoft
            font.family: Theme.font
            font.pixelSize: Theme.smallFontSize + 1
            font.letterSpacing: 2
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    function choose(item) { root.picked(item); root.reset() }

    // results, under the box
    Rectangle {
        visible: root.open
        y: root.height + 2
        width: root.width + 120
        height: root.results.length > 0 ? root.results.length * 32 + 2 : 32
        color: Theme.paper
        border.width: 1
        border.color: Theme.ink
        z: 100

        Text {
            visible: root.results.length === 0
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            text: "NO MATCH"
            color: Theme.inkSoft
            font.family: Theme.font
            font.pixelSize: Theme.smallFontSize + 1
            font.letterSpacing: 2
        }

        Column {
            x: 1; y: 1
            width: parent.width - 2
            Repeater {
                model: root.results
                Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool lit: root.cur === index
                    width: parent.width
                    height: 32

                    Rectangle { anchors.fill: parent; color: row.lit ? Theme.ink : Theme.paper }
                    // a sub-function or a menu (not an app): a small square in front, like the menu's own items
                    Rectangle {
                        visible: row.modelData.kind === "function" || row.modelData.kind === "menu"
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 7; height: 7
                        color: row.lit ? Theme.paper : Theme.ink
                    }
                    Text {
                        x: row.modelData.kind ? 27 : 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * 0.5
                        elide: Text.ElideRight
                        text: row.modelData.name
                        color: row.lit ? Theme.paper : Theme.ink
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * 0.5 - 30
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideLeft
                        text: row.modelData.kind === "menu" ? "MENU"
                            : row.modelData.kind === "function" ? "FUNCTION · " + row.modelData.loc.toUpperCase()
                            : row.modelData.loc !== "" ? row.modelData.loc.toUpperCase() : "NOT IN A CATEGORY"
                        color: row.lit ? Theme.paper : (row.modelData.loc !== "" ? Theme.inkSoft : Theme.accent)
                        font.family: Theme.font
                        font.pixelSize: Theme.smallFontSize
                        font.letterSpacing: 1
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.cur = row.index
                        onClicked: root.choose(row.modelData)
                    }
                }
            }
        }
    }
}
