import Quickshell
import QtQuick

// Facebook Messenger (through the local Matrix bridge) in the screen's style.
// Left: chats. Right: the open chat and its composer.
Item {
    id: root

    property var client                 // the shell-wide MatrixClient (keeps running while this is closed)

    // a message the server refused or never got: put it back in the input box (if still empty, same chat)
    Connections {
        target: root.client
        function onSendFailed(roomId, text) {
            if (roomId === root.client.currentId && input.text === "") input.text = text
        }
    }
    property string filterText: ""
    property string lightbox: ""        // local file of a photo shown large

    // chats that match the search box (the newest 80)
    readonly property var shown: {
        var q = filterText.trim().toLowerCase()
        var out = []
        var all = client.rooms
        for (var i = 0; i < all.length && out.length < 80; i++)
            if (q === "" || all[i].name.toLowerCase().indexOf(q) >= 0) out.push(all[i])
        return out
    }

    readonly property int listW: 300
    readonly property int gap: 12

    function fmt(ts) { return Qt.formatDateTime(new Date(ts), "hh:mm") }

    // =============================================================== chat list
    Item {
        id: left
        width: root.listW
        height: parent.height

        // search
        Rectangle {
            id: searchBox
            width: parent.width
            height: 30
            color: "transparent"
            border.width: 1
            border.color: Theme.ink

            Rectangle { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 9; height: 9; color: Theme.ink }
            TextInput {
                id: search
                x: 30
                width: parent.width - 40
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.ink
                selectionColor: Theme.ink
                selectedTextColor: Theme.paper
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                clip: true
                onTextChanged: root.filterText = text
                Text {
                    visible: search.text === "" && !search.activeFocus
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Search chats"
                    color: Theme.inkSoft
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                }
            }
        }

        NierScrollBar {
            view: roomList
            x: parent.width - width
            y: roomList.y
            height: roomList.height
        }

        ListView {
            id: roomList
            y: searchBox.height + 8
            width: parent.width - 14
            height: parent.height - y
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: 4
            model: root.shown.length

            delegate: Item {
                id: row
                required property int index
                readonly property var room: root.shown[index] ? root.shown[index] : ({ id: "", name: "", last: "", unread: 0 })
                readonly property bool lit: hit.containsMouse || client.currentId === room.id

                width: ListView.view.width
                height: 46

                Rectangle { anchors.fill: parent; color: Theme.paperDark }
                Rectangle {
                    height: parent.height
                    width: row.lit ? parent.width : 0
                    color: Theme.ink
                    Behavior on width { NumberAnimation { duration: Theme.hoverMs; easing.type: Easing.OutCubic } }
                }
                Rectangle {
                    x: 9
                    y: 9
                    width: 9; height: 9
                    color: row.lit ? Theme.paper : Theme.ink
                }
                Text {
                    x: 28
                    y: 5
                    width: parent.width - 28 - (row.room.unread > 0 ? 44 : 12)
                    elide: Text.ElideRight
                    text: row.room.name
                    textFormat: Text.PlainText
                    color: row.lit ? Theme.paper : Theme.ink
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                }
                Text {
                    x: 28
                    y: 25
                    width: parent.width - 40
                    elide: Text.ElideRight
                    text: row.room.last
                    textFormat: Text.PlainText
                    color: row.lit ? Theme.paperDark : Theme.inkSoft
                    font.family: Theme.font
                    font.pixelSize: Theme.smallFontSize
                    Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                }
                // unread count
                Rectangle {
                    visible: row.room.unread > 0
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    y: 6
                    width: Math.max(22, unreadText.implicitWidth + 10)
                    height: 18
                    color: Theme.accent
                    Text {
                        id: unreadText
                        anchors.centerIn: parent
                        text: row.room.unread > 99 ? "99+" : row.room.unread
                        color: Theme.paper
                        font.family: Theme.font
                        font.pixelSize: Theme.smallFontSize
                        font.bold: true
                    }
                }
                MouseArea {
                    id: hit
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: client.open(row.room.id)
                }
            }
        }
    }

    // =============================================================== open chat
    Item {
        id: right
        x: root.listW + root.gap
        width: parent.width - x
        height: parent.height

        // header
        Rectangle {
            id: head
            width: parent.width
            height: 30
            color: Theme.paperDark
            Rectangle { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 9; height: 9; color: Theme.ink }
            Text {
                x: 30
                width: parent.width - 30 - statusText.implicitWidth - 24
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: client.currentId !== "" ? client.currentName : "MESSENGER"
                textFormat: Text.PlainText
                color: Theme.ink
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.bold: true
                font.letterSpacing: 1
            }
            Text {
                id: statusText
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: client.sendError ? "NOT SENT" : client.status
                color: client.connected && !client.sendError ? Theme.inkSoft : Theme.accent
                font.family: Theme.font
                font.pixelSize: Theme.smallFontSize
                font.letterSpacing: 2
            }
        }

        // messages
        NierScrollBar {
            view: msgList
            x: parent.width - width
            y: msgList.y
            height: msgList.height
        }

        ListView {
            id: msgList
            y: head.height + 8
            width: parent.width - 14
            height: parent.height - y - composer.height - 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: 6
            model: client.messages.length
            onCountChanged: Qt.callLater(function () { msgList.positionViewAtEnd() })

            delegate: Item {
                id: msg
                required property int index
                readonly property var d: client.messages[index] ? client.messages[index] : ({ body: "", mine: false, name: "", ts: 0, kind: "text" })
                readonly property real maxW: width * 0.72

                width: ListView.view.width
                height: isMedia ? media.y + media.height : bubble.y + bubble.height
                opacity: 0

                NumberAnimation on opacity { to: 1; duration: Theme.hoverMs + 60; running: true }

                TextMetrics {
                    id: tm
                    text: msg.d.body
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                }

                Text {
                    id: meta
                    x: msg.d.mine ? msg.width - implicitWidth - 4 : 4
                    text: (msg.d.mine ? "" : msg.d.name + "   ") + root.fmt(msg.d.ts)
                    textFormat: Text.PlainText
                    color: Theme.inkSoft
                    font.family: Theme.font
                    font.pixelSize: Theme.smallFontSize
                }

                readonly property bool isMedia: d.kind === "image" || d.kind === "video"
                readonly property real mediaW: Math.min(380, width * 0.72)
                readonly property real mediaH: {
                    var r = (d.w > 0 && d.h > 0) ? d.h / d.w : 0.75
                    return Math.max(120, Math.min(300, mediaW * r))
                }

                MediaBox {
                    id: media
                    visible: msg.isMedia
                    client: root.client
                    msg: msg.d
                    y: meta.height + 3
                    x: msg.d.mine ? msg.width - width : 0
                    width: msg.mediaW
                    height: msg.mediaH
                    onEnlarge: path => root.lightbox = path
                }

                Rectangle {
                    id: bubble
                    visible: !msg.isMedia
                    y: meta.height + 3
                    x: msg.d.mine ? msg.width - width : 0
                    width: Math.min(tm.advanceWidth + 26, msg.maxW)
                    height: body.height + 16
                    color: msg.d.kind === "notice" ? "transparent" : (msg.d.mine ? Theme.ink : Theme.paperDark)
                    border.width: msg.d.kind === "notice" ? 1 : 0
                    border.color: Theme.paperDark

                    Text {
                        id: body
                        x: 13
                        y: 8
                        width: bubble.width - 26
                        wrapMode: Text.Wrap
                        text: msg.d.body
                    textFormat: Text.PlainText
                        color: msg.d.mine ? Theme.paper : (msg.d.kind === "media" || msg.d.kind === "notice" ? Theme.inkSoft : Theme.ink)
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                        font.italic: msg.d.kind === "notice"
                    }
                }
            }
        }

        Text {
            visible: client.currentId === "" && client.connected
            anchors.centerIn: msgList
            text: "SELECT A CHAT"
            color: Theme.paperDark
            font.family: Theme.font
            font.pixelSize: Theme.titleSize
            font.letterSpacing: 4
        }

        // composer
        Item {
            id: composer
            anchors.bottom: parent.bottom
            width: parent.width
            height: 34
            enabled: client.currentId !== ""
            opacity: enabled ? 1 : 0.45

            Rectangle {
                id: inputBox
                width: parent.width - sendBtn.width - 8
                height: parent.height
                color: "transparent"
                border.width: 1
                border.color: Theme.ink

                Rectangle { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 9; height: 9; color: Theme.ink }
                TextInput {
                    id: input
                    x: 30
                    width: parent.width - 42
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.ink
                    selectionColor: Theme.ink
                    selectedTextColor: Theme.paper
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    clip: true
                    onAccepted: { client.send(text); text = "" }
                    Text {
                        visible: input.text === "" && !input.activeFocus
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Write a message, then Enter"
                        color: Theme.inkSoft
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                    }
                }
            }

            Item {
                id: sendBtn
                anchors.right: parent.right
                width: 84
                height: parent.height
                readonly property bool lit: sendHit.containsMouse

                Rectangle { anchors.fill: parent; color: Theme.paperDark }
                Rectangle {
                    height: parent.height
                    width: sendBtn.lit ? parent.width : 0
                    color: Theme.ink
                    Behavior on width { NumberAnimation { duration: Theme.hoverMs; easing.type: Easing.OutCubic } }
                }
                Text {
                    anchors.centerIn: parent
                    text: "SEND"
                    color: sendBtn.lit ? Theme.paper : Theme.ink
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    font.letterSpacing: 2
                    Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                }
                MouseArea {
                    id: sendHit
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { client.send(input.text); input.text = "" }
                }
            }
        }
    }

    // photo shown large over the chat; click anywhere to close
    Rectangle {
        visible: root.lightbox !== ""
        x: root.listW + root.gap
        width: parent.width - x
        height: parent.height
        color: Theme.paper
        border.width: 1
        border.color: Theme.ink

        Image {
            anchors.fill: parent
            anchors.margins: 14
            source: root.lightbox !== "" ? "file://" + root.lightbox : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            width: hint.implicitWidth + 20
            height: 24
            color: Theme.ink
            Text {
                id: hint
                anchors.centerIn: parent
                text: "CLICK TO CLOSE"
                color: Theme.paper
                font.family: Theme.font
                font.pixelSize: Theme.smallFontSize
                font.letterSpacing: 2
            }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.lightbox = "" }
    }

    // =============================================================== first run: set up
    // No Messenger login yet (no ~/.config/fbtui/session.json): set up the local Matrix server and the Facebook bridge
    // (scripts/messenger-setup.py), then the chat with the bridge bot opens: send it "login" there.
    Rectangle {
        id: setup
        anchors.fill: parent
        visible: !root.client.hasLogin && root.client.status === "NO LOGIN FOUND"
        color: Theme.paper
        MouseArea { anchors.fill: parent }          // nothing under it takes clicks

        Column {
            width: Math.min(parent.width - 40, 640)
            x: 20
            y: 20
            spacing: 12

            Text {
                width: parent.width
                text: "SET UP MESSENGER"
                color: Theme.ink
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 2
                font.bold: true
                font.letterSpacing: 3
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                lineHeight: 1.35
                color: Theme.ink
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                text: "Messenger runs through a small Matrix server and a Facebook bridge on this computer (Docker). "
                    + "Nothing is reachable from outside it.\n\n"
                    + "  1. Pick a user name and password for that local server (they never leave this computer).\n"
                    + "  2. SET UP starts the server and the bridge (the first time downloads them, a few minutes).\n"
                    + "  3. The chat with the bridge bot opens: send  login messenger  (or  login facebook ) and paste the\n"
                    + "     cookies it asks for from your browser, where you are signed in to Messenger / Facebook."
            }
            FormField {
                id: userField
                label: "USER NAME"
                width: Math.min(parent.width, 520)
                text: Quickshell.env("USER") || ""
                KeyNavigation.tab: passField
                onAccepted: passField.input.forceActiveFocus()
            }
            FormField {
                id: passField
                label: "PASSWORD"
                secret: true
                width: userField.width
                KeyNavigation.tab: userField
                onAccepted: goBtn.clicked()
            }
            ChipButton {
                id: goBtn
                text: root.client.settingUp ? "SETTING UP…" : "SET UP"
                enabledLook: !root.client.settingUp
                onClicked: if (enabledLook) root.client.runSetup(userField.text, passField.text)
            }
            Text {
                width: parent.width
                visible: root.client.settingUp || root.client.setupError !== ""
                wrapMode: Text.Wrap
                text: root.client.setupError !== "" ? root.client.setupError.toUpperCase() : root.client.setupStep.toUpperCase() + "…"
                color: root.client.setupError !== "" ? Theme.accent : Theme.inkSoft
                font.family: Theme.font
                font.pixelSize: Theme.smallFontSize
                font.letterSpacing: 1
            }
        }
    }
}
