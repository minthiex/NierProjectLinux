import QtQuick

// Gmail in the screen's style (through scripts/mail.py, see MailClient.qml).
// Left: the inbox. Right: the open message, the composer, or (first run) the sign-in form.
Item {
    id: root

    property var client                  // the shell-wide MailClient (keeps checking while this is closed)
    Connections {
        target: root.client
        function onSent() { root.composing = false }
        function onAddressChanged() { root.composing = false; root.removeArmed = false }
        function onAccountsChanged() { if (root.adding && root.client.accounts.length > 0 && !root.client.busy) root.adding = false }
    }

    signal webmail(string address)       // WEBMAIL: the shell opens Gmail in its own sub-function
    property string filterText: ""
    property bool composing: false
    property bool adding: false          // the sign-in form is open to add another account
    property bool removeArmed: false
    property string replyTo: ""          // Message-ID being answered ("" = a new mail)
    property string replyRefs: ""

    readonly property int listW: 340
    readonly property int gap: 12

    // mails that match the search box
    readonly property var shown: {
        var q = filterText.trim().toLowerCase()
        var out = []
        var all = client.mails
        for (var i = 0; i < all.length; i++)
            if (q === "" || (all[i].from + " " + all[i].subject).toLowerCase().indexOf(q) >= 0) out.push(all[i])
        return out
    }

    function dayStamp(ts) {
        var d = new Date(ts), n = new Date()
        if (d.toDateString() === n.toDateString()) return Qt.formatDateTime(d, "hh:mm")
        if (d.getFullYear() === n.getFullYear()) return Qt.formatDateTime(d, "d MMM")
        return Qt.formatDateTime(d, "d MMM yyyy")
    }
    function fullStamp(ts) { return ts > 0 ? Qt.formatDateTime(new Date(ts), "ddd d MMM yyyy  hh:mm") : "" }

    function compose(to, subject, body, inReplyTo, refs) {
        toField.text = to
        subjectField.text = subject
        bodyEdit.text = body
        root.replyTo = inReplyTo
        root.replyRefs = refs
        root.composing = true
        if (to === "") toField.forceActiveFocus(); else { bodyEdit.forceActiveFocus(); bodyEdit.cursorPosition = 0 }
    }
    function startReply() {
        var d = client.detail
        if (!d) return
        var subj = /^re:/i.test(d.subject) ? d.subject : "Re: " + d.subject
        var quoted = String(d.body).split("\n").map(l => "> " + l).join("\n")
        compose(d.replyTo, subj, "\n\n" + fullStamp(d.ts) + ", " + d.from + " wrote:\n" + quoted, d.messageId, d.references)
    }

    // ---- a bordered one-line field with a caption -------------------------------------------------

    // =============================================================== inbox
    Item {
        id: left
        width: root.listW
        height: parent.height

        // one chip per saved account, and + to add another
        Flow {
            id: accountRow
            visible: client.configured
            width: parent.width
            spacing: 6
            Repeater {
                model: client.accounts
                delegate: ChipButton {
                    required property string modelData
                    text: modelData.replace(/@.*/, "").substring(0, 16)
                          + (client.accountUnread[modelData] > 0 ? " (" + client.accountUnread[modelData] + ")" : "")
                    selected: modelData === client.address && !root.adding
                    onClicked: { root.adding = false; if (modelData !== client.address) client.switchTo(modelData) }
                }
            }
            ChipButton { text: "+"; selected: root.adding; onClicked: root.adding = !root.adding }
        }

        Rectangle {
            id: searchBox
            y: accountRow.visible ? accountRow.height + 8 : 0
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
                    text: "Search mail"
                    color: Theme.inkSoft
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                }
            }
        }

        NierScrollBar {
            view: mailList
            x: parent.width - width
            y: mailList.y
            height: mailList.height
        }

        ListView {
            id: mailList
            y: searchBox.y + searchBox.height + 8
            width: parent.width - 14
            height: parent.height - y
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: 4
            model: root.shown.length

            delegate: Item {
                id: row
                required property int index
                readonly property var m: root.shown[index] ? root.shown[index] : ({ uid: "", from: "", subject: "", ts: 0, seen: true })
                readonly property bool lit: hit.containsMouse || (client.currentUid === m.uid && !root.composing)

                width: ListView.view.width
                height: 50

                Rectangle { anchors.fill: parent; color: Theme.paperDark }
                Rectangle {
                    height: parent.height
                    width: row.lit ? parent.width : 0
                    color: Theme.ink
                    Behavior on width { NumberAnimation { duration: Theme.hoverMs; easing.type: Easing.OutCubic } }
                }
                // unread: a filled red square, read: a small hollow one
                Rectangle {
                    x: 9
                    y: 11
                    width: 9; height: 9
                    color: row.m.seen ? "transparent" : Theme.accent
                    border.width: row.m.seen ? 1 : 0
                    border.color: row.lit ? Theme.paper : Theme.inkSoft
                }
                Text {
                    x: 28
                    y: 6
                    width: parent.width - 28 - stamp.implicitWidth - 20
                    elide: Text.ElideRight
                    text: row.m.from
                    textFormat: Text.PlainText
                    color: row.lit ? Theme.paper : Theme.ink
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    font.bold: !row.m.seen
                    Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                }
                Text {
                    id: stamp
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    y: 8
                    text: root.dayStamp(row.m.ts)
                    color: row.lit ? Theme.paperDark : Theme.inkSoft
                    font.family: Theme.font
                    font.pixelSize: Theme.smallFontSize
                    Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                }
                Text {
                    x: 28
                    y: 28
                    width: parent.width - 40
                    elide: Text.ElideRight
                    text: row.m.subject
                    textFormat: Text.PlainText
                    color: row.lit ? Theme.paperDark : Theme.inkSoft
                    font.family: Theme.font
                    font.pixelSize: Theme.smallFontSize
                    font.bold: !row.m.seen
                    Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                }
                MouseArea {
                    id: hit
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.composing = false; client.open(row.m.uid) }
                }
            }
        }

        Text {
            visible: client.configured && client.connected && root.shown.length === 0
            anchors.centerIn: mailList
            text: root.filterText !== "" ? "NO MATCH" : "INBOX EMPTY"
            color: Theme.inkSoft
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            font.letterSpacing: 3
        }
    }

    // =============================================================== right side
    Item {
        id: right
        x: root.listW + root.gap
        width: parent.width - x
        height: parent.height

        // header: title, unread count, status
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
                text: "EMAIL" + (client.address !== "" ? "   " + client.address : "") + (client.unread > 0 ? "   [" + client.unread + " UNREAD]" : "")
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
                text: client.sending ? "SENDING" : client.status
                color: client.connected ? Theme.inkSoft : Theme.accent
                font.family: Theme.font
                font.pixelSize: Theme.smallFontSize
                font.letterSpacing: 2
            }
        }

        // toolbar
        Flow {
            id: bar
            visible: client.configured
            y: head.height + 8
            width: parent.width
            spacing: 8
            ChipButton { text: "REFRESH"; onClicked: client.refresh() }
            ChipButton { text: "NEW"; onClicked: root.compose("", "", "", "", "") }
            ChipButton {
                text: "REPLY"
                enabledLook: client.detail !== null && !root.composing
                onClicked: if (enabledLook) root.startReply()
            }
            ChipButton {
                text: "WEBMAIL"
                onClicked: root.webmail(client.address)
            }
            ChipButton {
                text: root.removeArmed ? "SURE? CLICK AGAIN" : "REMOVE ACCOUNT"
                selected: root.removeArmed
                onClicked: {
                    if (!root.removeArmed) { root.removeArmed = true; disarm.restart(); return }
                    root.removeArmed = false
                    client.removeCurrent()
                }
                Timer { id: disarm; interval: 4000; onTriggered: root.removeArmed = false }
            }
        }

        // problem line (offline, refused login, send result)
        Text {
            id: noticeLine
            visible: text !== ""
            y: bar.visible ? bar.y + bar.height + 8 : head.height + 8
            width: parent.width
            wrapMode: Text.Wrap
            color: Theme.accent
            font.family: Theme.font
            font.pixelSize: Theme.smallFontSize
            font.letterSpacing: 1
            text: client.notice === "offline" ? "CANNOT REACH GMAIL. RETRYING EVERY 90 SECONDS, OR PRESS REFRESH."
                : client.notice === "login" ? "GOOGLE REFUSED THE LOGIN. THE APP PASSWORD MAY HAVE BEEN REVOKED."
                : client.notice === "locked" ? "THE APP PASSWORD IS IN KEEPASSXC: UNLOCK ITS DATABASE, THEN PRESS REFRESH."
                : client.notice
        }

        readonly property real below: (noticeLine.visible ? noticeLine.y + noticeLine.height : (bar.visible ? bar.y + bar.height : head.height)) + 10

        // ---------------------------------------------------------- first run: sign in
        Item {
            id: setup
            visible: root.adding || (!client.configured && client.status !== "STARTING" && client.status !== "CONNECTING")
            y: right.below
            width: parent.width
            height: parent.height - y

            Text {
                id: setupText
                width: parent.width
                wrapMode: Text.Wrap
                lineHeight: 1.35
                color: Theme.ink
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                text: (client.configured ? "ADD ANOTHER GOOGLE ACCOUNT" : "SIGN IN TO GOOGLE MAIL") + "\n\nGoogle does not allow your normal password here. Create an app password:\n"
                    + "  1. Open myaccount.google.com, Security.\n"
                    + "  2. Turn on 2-Step Verification (if it is off).\n"
                    + "  3. Search for \"App passwords\" and create one named ProjectNier.\n"
                    + "  4. Paste the 16 letters below.\n\n"
                    + "It is checked with Google, then kept in your keyring (KeePassXC) if one is running, else in ~/.config/projectnier/mail.json (readable only by you)."
            }
            FormField {
                id: addrField
                label: "ADDRESS"
                y: setupText.height + 18
                width: Math.min(parent.width, 520)
                input.focus: true
                KeyNavigation.tab: passField
                onAccepted: passField.input.forceActiveFocus()
            }
            FormField {
                id: passField
                label: "APP PASSWORD"
                secret: true
                y: addrField.y + addrField.height + 8
                width: addrField.width
                KeyNavigation.tab: addrField
                onAccepted: connectBtn.clicked()
            }
            ChipButton {
                id: connectBtn
                y: passField.y + passField.height + 12
                text: client.busy ? "CHECKING…" : (client.configured ? "ADD" : "CONNECT")
                enabledLook: !client.busy
                onClicked: if (enabledLook) client.saveLogin(addrField.text, passField.text)
            }
            ChipButton {
                visible: client.configured
                x: connectBtn.width + 8
                y: connectBtn.y
                text: "CANCEL"
                onClicked: root.adding = false
            }
            Text {
                visible: client.status === "OFFLINE"
                y: connectBtn.y + connectBtn.height + 12
                text: "Cannot reach Google. Check the network."
                color: Theme.accent
                font.family: Theme.font
                font.pixelSize: Theme.smallFontSize
            }
        }

        // ---------------------------------------------------------- reading
        Item {
            id: reader
            visible: client.configured && !root.composing && !root.adding
            y: right.below
            width: parent.width
            height: parent.height - y

            Text {
                visible: client.detail === null
                anchors.centerIn: parent
                text: client.loadingDetail ? "LOADING" : "SELECT A MESSAGE"
                color: Theme.paperDark
                font.family: Theme.font
                font.pixelSize: Theme.titleSize
                font.letterSpacing: 4
            }

            Item {
                visible: client.detail !== null
                anchors.fill: parent

                Column {
                    id: meta
                    width: parent.width
                    spacing: 5

                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: client.detail ? client.detail.subject : ""
                        textFormat: Text.PlainText
                        color: Theme.ink
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 3
                        font.bold: true
                    }
                    Repeater {
                        model: client.detail ? [
                            ["FROM", client.detail.from + (client.detail.address && client.detail.address !== client.detail.from ? "  <" + client.detail.address + ">" : "")],
                            ["TO", client.detail.to],
                            ["CC", client.detail.cc],
                            ["DATE", root.fullStamp(client.detail.ts)]
                        ].filter(r => r[1] !== "") : []
                        delegate: Row {
                            required property var modelData
                            spacing: 12
                            Text {
                                width: 56
                                text: modelData[0]
                                color: Theme.inkSoft
                                font.family: Theme.font
                                font.pixelSize: Theme.smallFontSize
                                font.letterSpacing: 2
                            }
                            Text {
                                width: meta.width - 68
                                elide: Text.ElideRight
                                text: modelData[1]
                                textFormat: Text.PlainText
                                color: Theme.ink
                                font.family: Theme.font
                                font.pixelSize: Theme.smallFontSize + 1
                            }
                        }
                    }
                    Text {
                        visible: client.detail !== null && client.detail.attachments.length > 0
                        width: parent.width
                        elide: Text.ElideRight
                        text: client.detail ? "ATTACHMENTS   " + client.detail.attachments.join(",  ") + "   (open the mail in WEBMAIL to get them)" : ""
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: Theme.smallFontSize
                    }
                }
                Rectangle { id: rule; y: meta.height + 8; width: parent.width; height: 1; color: Theme.inkSoft }

                NierScrollBar { view: bodyFlick; x: parent.width - width; y: bodyFlick.y; height: bodyFlick.height }
                Flickable {
                    id: bodyFlick
                    y: rule.y + 10
                    width: parent.width - 14
                    height: parent.height - y
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: width
                    contentHeight: bodyText.height + 10
                    onContentHeightChanged: contentY = 0

                    TextEdit {
                        id: bodyText
                        width: bodyFlick.width
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.Wrap
                        text: client.detail ? client.detail.body : ""
                        textFormat: TextEdit.PlainText
                        color: Theme.ink
                        selectionColor: Theme.ink
                        selectedTextColor: Theme.paper
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                    }
                }
            }
        }

        // ---------------------------------------------------------- writing
        Item {
            id: writer
            visible: client.configured && root.composing && !root.adding
            y: right.below
            width: parent.width
            height: parent.height - y

            FormField {
                id: toField
                label: "TO"
                width: parent.width
                KeyNavigation.tab: subjectField
                onAccepted: subjectField.input.forceActiveFocus()
            }
            FormField {
                id: subjectField
                label: "SUBJECT"
                y: toField.height + 8
                width: parent.width
                KeyNavigation.tab: bodyEdit
                onAccepted: bodyEdit.forceActiveFocus()
            }
            Rectangle {
                id: bodyBox
                y: subjectField.y + subjectField.height + 8
                width: parent.width
                height: parent.height - y - 38
                color: "transparent"
                border.width: 1
                border.color: Theme.ink

                Flickable {
                    id: editFlick
                    anchors.fill: parent
                    anchors.margins: 10
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: width
                    contentHeight: bodyEdit.height
                    function follow() {
                        var r = bodyEdit.cursorRectangle
                        if (r.y < contentY) contentY = r.y
                        else if (r.y + r.height > contentY + height) contentY = r.y + r.height - height
                    }
                    TextEdit {
                        id: bodyEdit
                        width: editFlick.width
                        height: Math.max(implicitHeight, editFlick.height)
                        wrapMode: TextEdit.Wrap
                        color: Theme.ink
                        selectionColor: Theme.ink
                        selectedTextColor: Theme.paper
                        selectByMouse: true
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                        KeyNavigation.priority: KeyNavigation.BeforeItem
                        KeyNavigation.backtab: subjectField
                        onCursorRectangleChanged: editFlick.follow()
                        Text {
                            visible: bodyEdit.text === "" && !bodyEdit.activeFocus
                            text: "Write your message"
                            color: Theme.inkSoft
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize
                        }
                    }
                }
            }
            Row {
                anchors.bottom: parent.bottom
                spacing: 8
                ChipButton {
                    text: client.sending ? "SENDING…" : "SEND"
                    enabledLook: !client.busy
                    onClicked: if (enabledLook) client.send(toField.text, subjectField.text, bodyEdit.text, root.replyTo, root.replyRefs)
                }
                ChipButton { text: "DISCARD"; onClicked: root.composing = false }
            }
        }
    }
}
