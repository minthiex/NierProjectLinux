import QtQuick

// Page opened from a top tab: big shadowed title, and the sub buttons under it.
// The cursor row is dark (it follows the mouse); a left rail carries a small marker.
Item {
    id: root
    property string title
    property string subtitle
    property string purpose
    property var items: []          // [{ name, desc }]
    property int cur: 0
    property var badges: ({})           // sub-function name -> count shown as "(N)"
    property string selectedName: ""   // the opened sub-function, if any
    property var hiddenItems: []        // sub-functions taken out of this menu (listed while arranging, to bring back)
    property bool arranging: false
    signal moved(string name, int delta)
    signal restored(string name)
    onTitleChanged: arranging = false

    readonly property int selIndex: {
        for (var i = 0; i < items.length; i++)
            if (items[i].name === selectedName) return i
        return -1
    }
    // the highlight returns to the selected row (or the first) when the mouse leaves the list
    function restoreCursor() { cur = selIndex >= 0 ? selIndex : 0 }
    onSelIndexChanged: if (selIndex >= 0) cur = selIndex
    signal activated(string name)

    readonly property string curName: items.length > 0 ? items[Math.min(cur, items.length - 1)].name : ""
    readonly property string curDesc: items.length > 0 ? items[Math.min(cur, items.length - 1)].desc : ""

    readonly property real listTop: view.y
    readonly property int rowW: 240
    readonly property int rowH: 32
    readonly property int rowGap: 12

    onItemsChanged: cur = 0

    implicitWidth: rowW + 26
    implicitHeight: view.y + list.height

    // title with a soft drop shadow
    Item {
        id: titleBox
        width: titleText.width + 3
        height: titleText.height + 3

        Text {
            x: 3; y: 3
            text: root.title
            color: Theme.paperDark
            font.family: Theme.font
            font.pixelSize: Theme.titleSize
            font.letterSpacing: 3
        }
        Text {
            id: titleText
            text: root.title
            color: Theme.ink
            font.family: Theme.font
            font.pixelSize: Theme.titleSize
            font.letterSpacing: 3
        }
    }

    Text {
        id: subText
        y: titleBox.height + 6
        text: root.subtitle
        color: Theme.inkSoft
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        font.letterSpacing: 2
    }

    Text {
        id: purposeText
        y: subText.y + subText.height + 4
        text: root.purpose
        color: Theme.inkSoft
        font.family: Theme.font
        font.pixelSize: Theme.smallFontSize + 1
    }

    // the list scrolls inside the space down to the bottom box (a scroll bar shows when it does not fit)
    Flickable {
        id: view
        x: -4
        y: purposeText.y + purposeText.height + 36
        width: root.implicitWidth + 4
        height: Math.max(root.rowH, Math.min(list.height, root.height - y))
        contentWidth: width
        contentHeight: list.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        // left rail + cursor marker
        Rectangle {
            x: 4
            y: 0
            width: 6
            height: list.height
            color: Theme.paperDark
        }
        Text {
            x: 2
            y: root.cur * (root.rowH + root.rowGap) + root.rowH / 2 - height / 2
            text: "◂"
            color: Theme.ink
            font.family: Theme.font
            font.pixelSize: Theme.fontSize + 2
            Behavior on y { NumberAnimation { duration: Theme.hoverMs; easing.type: Easing.OutCubic } }
        }

        Column {
            id: list
            HoverHandler { onHoveredChanged: if (!hovered) root.restoreCursor() }
            x: 30
            y: 0
            spacing: root.rowGap

            Repeater {
                model: root.arranging ? root.items.concat(root.hiddenItems.map(h => ({ name: h.name, desc: h.desc, hiddenRow: true }))) : root.items

                Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool lit: root.cur === index
                    width: root.rowW
                    height: root.rowH
                    opacity: 0
                    transform: Translate { id: slide; x: -24 }

                    // rows come in one after another
                    SequentialAnimation {
                        id: appear
                        PauseAnimation { duration: row.index * 55 }
                        ParallelAnimation {
                            NumberAnimation { target: row; property: "opacity"; to: 1; duration: Theme.hoverMs + 60 }
                            NumberAnimation { target: slide; property: "x"; to: 0; duration: Theme.hoverMs + 100; easing.type: Easing.OutCubic }
                        }
                    }
                    Component.onCompleted: appear.start()

                    Rectangle { anchors.fill: parent; color: Theme.paperDark }
                    readonly property bool dim: row.modelData.hiddenRow === true

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: row.lit ? row.width : 0
                        color: Theme.ink
                        Behavior on width { NumberAnimation { duration: Theme.hoverMs; easing.type: Easing.OutCubic } }
                    }

                    Rectangle {
                        x: 11
                        anchors.verticalCenter: parent.verticalCenter
                        width: 11; height: 11
                        color: row.lit ? Theme.paper : Theme.ink
                        Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                    }

                    Text {
                        x: 32
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.StyledText      // the (N) badge is bold
                        text: row.modelData.name.replace(/&/g, "&amp;").replace(/</g, "&lt;") + (root.badges[row.modelData.name] > 0 ? "  <b>(" + root.badges[row.modelData.name] + ")</b>" : "")
                        color: row.lit ? Theme.paper : Theme.ink
                        opacity: row.dim ? 0.5 : 1
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 1
                        font.letterSpacing: 1
                        Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.cur = row.index
                        onClicked: if (!root.arranging) root.activated(row.modelData.name)
                    }

                    // arrange mode: up / down on a shown row, "+" on a hidden one
                    Row {
                        visible: root.arranging
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Repeater {
                            model: row.dim ? [{ g: "+", d: 0 }] : [{ g: "\u25b2", d: -1 }, { g: "\u25bc", d: 1 }]
                            Rectangle {
                                id: ab
                                required property var modelData
                                width: 20; height: 20
                                color: abHit.containsMouse ? Theme.accent : "transparent"
                                border.width: 1
                                border.color: row.lit ? Theme.paper : Theme.ink
                                Text {
                                    anchors.centerIn: parent
                                    text: ab.modelData.g
                                    color: row.lit || abHit.containsMouse ? Theme.paper : Theme.ink
                                    font.family: Theme.font
                                    font.pixelSize: Theme.smallFontSize
                                }
                                MouseArea {
                                    id: abHit
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (row.dim) root.restored(row.modelData.name)
                                        else root.moved(row.modelData.name, ab.modelData.d)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    NierScrollBar {
        view: view
        x: root.implicitWidth + 4
        y: view.y
        height: view.height
    }
}
