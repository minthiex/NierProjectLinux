import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Widgets
import QtQuick

// One notification in the screen's style: dark title bar (app, time, close), paper body,
// tan action buttons and a thin bar that runs down while it waits to expire.
// A notification that offers an inline reply (Messenger, scripts/notify-wait.py) gets a REPLY button: it opens a text
// field in the card (the card stops counting down meanwhile); Enter sends, Escape goes back.
Item {
    id: root
    required property var note            // a Quickshell Notification
    signal finished()
    property bool replying: false         // the reply field is open: the notice window takes the keyboard
    onReplyingChanged: {
        if (replying) { lifeAnim.pause(); replyInput.text = ""; replyInput.forceActiveFocus() }
        else if (!leaving) lifeAnim.resume()
    }
    function sendReply() {
        var t = replyInput.text.trim()
        if (t === "") return
        replying = false
        var n = note
        act(function () { n.sendInlineReply(t) })
    }

    readonly property bool urgent: note.urgency === NotificationUrgency.Critical
    readonly property real seconds: urgent ? 0 : (note.expireTimeout > 0 ? note.expireTimeout : 7)
    property bool leaving: false
    readonly property color bar: urgent ? Theme.accent : Theme.ink

    width: 520
    height: card.height

    function close() {
        if (leaving) return
        leaving = true
        wipeOut.start()
    }
    // a button / the card was clicked: leave first, take the action at the end of the wipe. Invoking an action
    // dismisses the notification, which destroys this card at once, so nothing of the card may run after it.
    property var pendingAction: null     // a NotificationAction or a function
    function act(a) {
        if (leaving) return
        pendingAction = a
        close()
    }

    // ---- appear / disappear --------------------------------------------------------------
    opacity: 0
    transform: Translate { id: slide; y: -18 }
    Component.onCompleted: { appear.start(); if (root.seconds > 0) lifeAnim.start() }

    ParallelAnimation {
        id: appear
        NumberAnimation { target: root; property: "opacity"; to: 1; duration: Theme.hoverMs }
        NumberAnimation { target: slide; property: "y"; to: 0; duration: Theme.hoverMs + 80; easing.type: Easing.OutCubic }
        NumberAnimation { target: titleWipe; property: "width"; from: 0; to: root.width; duration: Theme.hoverMs * 2; easing.type: Easing.OutCubic }
    }
    NumberAnimation {
        id: lifeAnim
        target: life
        property: "width"
        from: root.width
        to: 0
        duration: Math.max(1, root.seconds * 1000)
    }
    SequentialAnimation {
        id: wipeOut
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 0; duration: Theme.hoverMs }
            NumberAnimation { target: slide; property: "y"; to: -12; duration: Theme.hoverMs; easing.type: Easing.InCubic }
        }
        ScriptAction { script: { var a = root.pendingAction; root.finished(); if (typeof a === "function") a(); else if (a) a.invoke() } }
    }

    // the sender updated the notice (Messenger: another message in the same chat): count down from the start again
    Connections {
        target: root.note
        function onBodyChanged() { root.restartLife() }
        function onSummaryChanged() { root.restartLife() }
    }
    function restartLife() {
        if (leaving || replying || seconds <= 0) return
        lifeTimer.restart()
        lifeAnim.restart()
    }

    // timer: when it runs out the card leaves by itself
    Timer {
        id: lifeTimer
        running: root.seconds > 0 && !root.replying
        interval: root.seconds * 1000
        onTriggered: root.close()
    }

    // ---- the card --------------------------------------------------------------------------
    Rectangle {
        id: card
        width: parent.width
        height: head.height + bodyBox.height + (actionRow.visible ? actionRow.height + 12 : 0) + (replyBox.visible ? replyBox.height + 12 : 0) + 4
        color: Theme.paper
        border.width: 1
        border.color: root.bar

        // title bar
        Rectangle {
            id: head
            width: parent.width
            height: 26
            color: "transparent"

            Rectangle { id: titleWipe; height: parent.height; width: 0; color: root.bar }

            Rectangle { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; color: Theme.paper }
            Text {
                x: 28
                anchors.verticalCenter: parent.verticalCenter
                text: root.note.appName !== "" ? String(root.note.appName).toUpperCase() : "NOTICE"
                color: Theme.paper
                font.family: Theme.font
                font.pixelSize: Theme.smallFontSize + 1
                font.bold: true
                font.letterSpacing: 3
            }

            // close
            HeadButton {
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                glyph: ""
                danger: true
                onClicked: root.close()
            }
        }

        // body
        Item {
            id: bodyBox
            y: head.height
            width: parent.width
            height: Math.max(texts.height, iconBox.visible ? iconBox.height : 0) + 20

            Rectangle {
                id: iconBox
                visible: pic.status === Image.Ready || icon.visible
                x: 14
                y: 12
                width: 44; height: 44
                color: Theme.paperDark
                IconImage {
                    id: icon
                    anchors.centerIn: parent
                    visible: root.note.image === "" && source !== ""
                    implicitSize: 30
                    source: root.note.appIcon !== "" ? Quickshell.iconPath(root.note.appIcon, true) : ""
                }
                Image {
                    id: pic
                    anchors.fill: parent
                    anchors.margins: 2
                    visible: root.note.image !== ""
                    source: root.note.image
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }

            Column {
                id: texts
                x: iconBox.visible ? 70 : 16
                y: 12
                width: parent.width - x - 16
                spacing: 4

                Text {
                    width: parent.width
                    visible: text !== ""
                    text: root.note.summary
                    textFormat: Text.PlainText          // the summary is plain text by the spec (a subject like "<b>" is not markup)
                    color: Theme.ink
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    // body markup: tags dropped, entities turned back into characters, then shown as plain text
                    text: String(root.note.body).replace(/<[^>]*>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
                          .replace(/&quot;/g, "\"").replace(/&#39;|&apos;/g, "'").replace(/&amp;/g, "&")
                    textFormat: Text.PlainText
                    color: Theme.inkSoft
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                }
            }

            // clicking the text takes the notification's default action (if any) and closes it
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    var acts = root.note.actions, def = null
                    for (var i = 0; i < acts.length; i++) if (acts[i].identifier === "default") { def = acts[i]; break }
                    root.act(def)
                }
            }
        }

        // action buttons
        Row {
            id: actionRow
            visible: (actionsModel.length > 0 || root.note.hasInlineReply) && !root.replying
            x: 16
            y: head.height + bodyBox.height
            spacing: 8
            readonly property var actionsModel: root.note.actions.filter(a => a.identifier !== "default" && a.identifier !== "inline-reply")

            // REPLY: opens the text field below
            Item {
                id: rb
                visible: root.note.hasInlineReply
                readonly property bool lit: rh.containsMouse
                width: rt.implicitWidth + 24
                height: 26
                Rectangle { anchors.fill: parent; color: Theme.paperDark }
                Rectangle {
                    height: parent.height
                    width: rb.lit ? parent.width : 0
                    color: Theme.ink
                    Behavior on width { NumberAnimation { duration: Theme.hoverMs; easing.type: Easing.OutCubic } }
                }
                Text {
                    id: rt
                    anchors.centerIn: parent
                    text: "Reply"
                    color: rb.lit ? Theme.paper : Theme.ink
                    font.family: Theme.font
                    font.pixelSize: Theme.smallFontSize + 1
                    Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                }
                MouseArea { id: rh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.replying = true }
            }

            Repeater {
                model: actionRow.actionsModel

                Item {
                    id: ab
                    required property var modelData
                    readonly property bool lit: ah.containsMouse
                    width: at.implicitWidth + 24
                    height: 26
                    Rectangle { anchors.fill: parent; color: Theme.paperDark }
                    Rectangle {
                        height: parent.height
                        width: ab.lit ? parent.width : 0
                        color: Theme.ink
                        Behavior on width { NumberAnimation { duration: Theme.hoverMs; easing.type: Easing.OutCubic } }
                    }
                    Text {
                        id: at
                        anchors.centerIn: parent
                        text: ab.modelData.text
                        color: ab.lit ? Theme.paper : Theme.ink
                        font.family: Theme.font
                        font.pixelSize: Theme.smallFontSize + 1
                        Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                    }
                    MouseArea {
                        id: ah
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.act(ab.modelData)
                    }
                }
            }
        }

        // reply field (Enter sends, Escape goes back)
        Rectangle {
            id: replyBox
            visible: root.replying
            x: 16
            y: head.height + bodyBox.height
            width: parent.width - 32
            height: 30
            color: Theme.paper
            border.width: 1
            border.color: Theme.ink
            Rectangle { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; color: Theme.ink }
            TextInput {
                id: replyInput
                x: 28
                width: parent.width - 40
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.ink
                selectionColor: Theme.ink
                selectedTextColor: Theme.paper
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                clip: true
                onAccepted: root.sendReply()
                Keys.onEscapePressed: root.replying = false
                Text {
                    visible: replyInput.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: (root.note.inlineReplyPlaceholder || "Write a reply") + ", then Enter"
                    color: Theme.inkSoft
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                }
            }
        }

        // time left
        Rectangle {
            id: life
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            height: 3
            width: 0
            color: root.bar
            visible: root.seconds > 0
        }
    }
}
