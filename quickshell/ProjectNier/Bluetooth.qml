import Quickshell
import Quickshell.Bluetooth
import QtQuick
import QtQml

// Bluetooth manager in the screen's style (Network → Bluetooth, in the content window).
// Top: the adapter (power, visible to others, scan). Left: connected, paired and nearby devices.
// Right: the selected device with everything you can do to it, and the pairing card when BlueZ asks something.
// Talks to BlueZ through Quickshell.Bluetooth; passkey / PIN questions come from the shell-wide BluetoothAgent.
Item {
    id: root

    property var agent                                    // BluetoothAgent (lives in NierScreen)
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool powered: adapter !== null && adapter.enabled
    readonly property var all: Bluetooth.devices.values
    property string selAddr: ""
    property string notice: ""
    property var wanted: ({})                             // address -> true: pair, then trust and connect it
    property bool scanOurs: false                         // we started the scan (so we stop it again)
    property int scanLeft: 0

    readonly property int listW: 400
    readonly property int gap: 14

    // ---- device lists -----------------------------------------------------------------------------
    function named(d) { return d.deviceName !== "" }
    function label(d) { return d.name !== "" ? d.name : (d.deviceName !== "" ? d.deviceName : d.address) }
    readonly property var connectedList: all.filter(d => d.connected).sort((a, b) => label(a).localeCompare(label(b)))
    readonly property var pairedList: all.filter(d => d.paired && !d.connected).sort((a, b) => label(a).localeCompare(label(b)))
    readonly property var nearbyList: all.filter(d => !d.paired && !d.connected && named(d)).sort((a, b) => label(a).localeCompare(label(b)))
    readonly property int unnamed: all.filter(d => !d.paired && !d.connected && !named(d)).length
    readonly property var rows: {
        var out = []
        var sec = (title, list, empty) => {
            out.push({ hdr: title + "  " + list.length })
            if (list.length === 0) out.push({ hint: empty })
            list.forEach(d => out.push({ dev: d }))
        }
        sec("CONNECTED", connectedList, "nothing connected")
        sec("PAIRED", pairedList, "no other paired devices")
        sec("NEARBY", nearbyList, adapter && adapter.discovering ? "looking for devices…" : "press SCAN to look for devices")
        if (unnamed > 0) out.push({ hint: "+ " + unnamed + " nearby without a name (not shown)" })
        return out
    }
    readonly property var sel: {
        for (var i = 0; i < all.length; i++) if (all[i].address === selAddr) return all[i]
        return null
    }

    function stateText(d) {
        if (d.pairing) return "PAIRING…"
        if (d.state === BluetoothDeviceState.Connecting) return "CONNECTING…"
        if (d.state === BluetoothDeviceState.Disconnecting) return "DISCONNECTING…"
        if (d.connected) return "CONNECTED"
        if (d.blocked) return "BLOCKED"
        if (d.paired) return "PAIRED"
        return "NOT PAIRED"
    }
    function busy(d) { return d.pairing || d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting }
    // Nerd Font (Font Awesome) glyph for the kind of device BlueZ reports
    function glyph(icon) {
        var i = String(icon)
        if (/headset|headphone/.test(i)) return ""
        if (/audio|speaker|card/.test(i)) return ""
        if (/keyboard/.test(i)) return ""
        if (/mouse|tablet/.test(i)) return ""
        if (/gaming|joystick/.test(i)) return ""
        if (/phone/.test(i)) return ""
        if (/computer/.test(i)) return ""
        if (/display|video/.test(i)) return ""
        if (/printer/.test(i)) return ""
        if (/camera/.test(i)) return ""
        return ""
    }
    function kindName(icon) {
        var i = String(icon)
        return i === "" ? "unknown" : i.replace(/^(audio|input)-/, "").replace(/-/g, " ")
    }

    // ---- actions ----------------------------------------------------------------------------------
    function pairDev(d) {
        var w = Object.assign({}, wanted); w[d.address] = true; wanted = w
        notice = ""
        if (!adapter.pairable) adapter.pairable = true
        d.pair()
    }
    function forgetDev(d) {
        if (selAddr === d.address) selAddr = ""
        d.forget()
    }
    function setScan(on) {
        if (!adapter) return
        adapter.discovering = on
        scanOurs = on
        scanLeft = on ? 60 : 0
    }
    Timer {
        interval: 1000; repeat: true
        running: root.scanOurs && root.adapter !== null && root.adapter.discovering
        onTriggered: if (--root.scanLeft <= 0) root.setScan(false)
    }
    onVisibleChanged: if (!visible && scanOurs) setScan(false)      // never leave the radio scanning behind
    Component.onDestruction: if (scanOurs && adapter) adapter.discovering = false
    Timer { id: noticeClear; interval: 8000; onTriggered: root.notice = "" }
    onNoticeChanged: if (notice !== "") noticeClear.restart()

    // follow every device: finish a pairing we asked for (trust + connect), and say so when something fails
    Instantiator {
        model: Bluetooth.devices
        delegate: QtObject {
            id: watch
            required property var modelData
            property int last: modelData.state
            property bool wasPairing: modelData.pairing
            property Connections c: Connections {
                target: watch.modelData
                function onPairedChanged() {
                    var d = watch.modelData
                    if (d.paired && root.wanted[d.address]) {
                        var w = Object.assign({}, root.wanted); delete w[d.address]; root.wanted = w
                        d.trusted = true
                        if (!d.connected) d.connect()     // BlueZ often connects by itself after pairing
                        root.agent.clearDisplay()
                        root.notice = "PAIRED WITH " + root.label(d).toUpperCase()
                    }
                }
                function onPairingChanged() {
                    var d = watch.modelData
                    if (watch.wasPairing && !d.pairing && !d.paired && root.wanted[d.address]) {
                        var w = Object.assign({}, root.wanted); delete w[d.address]; root.wanted = w
                        root.agent.clearDisplay()
                        root.notice = "PAIRING WITH " + root.label(d).toUpperCase() + " FAILED  (rejected, timed out or out of range)"
                    }
                    watch.wasPairing = d.pairing
                }
                function onStateChanged() {
                    var d = watch.modelData
                    if (watch.last === BluetoothDeviceState.Connecting && d.state === BluetoothDeviceState.Disconnected)
                        root.notice = "COULD NOT CONNECT TO " + root.label(d).toUpperCase() + "  (is it on and in range?)"
                    watch.last = d.state
                }
            }
        }
    }

    // ---- small pieces in the screen's style -----------------------------------------------------------
    component Caption: Text {
        color: Theme.inkSoft
        font.family: Theme.font
        font.pixelSize: Theme.smallFontSize
        font.letterSpacing: 2
        font.bold: true
    }
    // a full-width action plate (like the result window's buttons); confirm = needs a second click
    component Action: Item {
        id: act
        property string text
        property bool confirm: false
        property bool danger: false
        property bool armed: false
        property bool active: true
        signal triggered()
        readonly property bool lit: active && (hit.containsMouse || armed)
        width: parent ? parent.width : 200
        height: 28
        opacity: active ? 1 : 0.45
        Timer { id: disarm; interval: 3000; onTriggered: act.armed = false }
        Rectangle { anchors.fill: parent; color: Theme.paperDark }
        Rectangle {
            height: parent.height
            width: act.lit ? parent.width : 0
            color: act.danger && act.armed ? Theme.accent : Theme.ink
            Behavior on width { NumberAnimation { duration: Theme.hoverMs; easing.type: Easing.OutCubic } }
        }
        Rectangle { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; color: act.lit ? Theme.paper : Theme.ink }
        Text {
            x: 30
            anchors.verticalCenter: parent.verticalCenter
            text: act.armed ? "Click again to confirm:  " + act.text : act.text
            color: act.lit ? Theme.paper : Theme.ink
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            font.letterSpacing: 1
        }
        MouseArea {
            id: hit
            anchors.fill: parent
            enabled: act.active
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (act.confirm && !act.armed) { act.armed = true; disarm.restart(); return }
                act.armed = false
                act.triggered()
            }
        }
    }
    component Line: Item {
        property string key
        property string value
        width: parent ? parent.width : 200
        height: 26
        Text { x: 0; anchors.verticalCenter: parent.verticalCenter; text: parent.key; color: Theme.inkSoft; font.family: Theme.font; font.pixelSize: Theme.fontSize; font.letterSpacing: 1 }
        Text {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.6; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
            text: parent.value; color: Theme.ink; font.family: Theme.font; font.pixelSize: Theme.fontSize
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.paperDark }
    }

    // =========================================================== adapter strip
    Item {
        id: strip
        width: parent.width
        height: 58

        Rectangle {
            id: radio
            width: 44; height: 44
            anchors.verticalCenter: parent.verticalCenter
            color: root.powered ? Theme.ink : "transparent"
            border.width: 1
            border.color: Theme.ink
            Text {
                anchors.centerIn: parent
                text: ""
                color: root.powered ? Theme.paper : Theme.ink
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 9
            }
        }
        Column {
            x: radio.width + 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Text {
                text: root.adapter ? String(root.adapter.name).toUpperCase() : "NO ADAPTER"
                color: Theme.ink
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 4
                font.bold: true
                font.letterSpacing: 3
            }
            Caption {
                text: !root.adapter ? "no Bluetooth controller found"
                    : root.adapter.state === BluetoothAdapterState.Blocked ? "BLOCKED BY RFKILL"
                    : root.adapter.state === BluetoothAdapterState.Enabling ? "TURNING ON…"
                    : root.adapter.state === BluetoothAdapterState.Disabling ? "TURNING OFF…"
                    : !root.powered ? "OFF"
                    : (root.adapter.discovering ? "SCANNING" + (root.scanOurs ? "  " + root.scanLeft + " S" : "") : "ON")
                      + (root.adapter.discoverable ? "  ·  VISIBLE TO OTHERS" : "")
                      + (root.agent && !root.agent.ready ? "  ·  PAIRING AGENT OFFLINE" : "")
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            ChipButton {
                visible: root.adapter !== null && root.adapter.state === BluetoothAdapterState.Blocked
                text: "Unblock"
                onClicked: Quickshell.execDetached(["rfkill", "unblock", "bluetooth"])
            }
            ChipButton {
                visible: root.adapter !== null
                text: "Power"
                selected: root.powered
                onClicked: root.adapter.enabled = !root.adapter.enabled
            }
            ChipButton {
                visible: root.adapter !== null
                enabledLook: root.powered
                text: "Visible"
                selected: root.powered && root.adapter.discoverable
                onClicked: root.adapter.discoverable = !root.adapter.discoverable
            }
            ChipButton {
                visible: root.adapter !== null
                enabledLook: root.powered
                text: root.adapter && root.adapter.discovering ? "Stop Scan" : "Scan"
                selected: root.powered && root.adapter.discovering
                onClicked: root.setScan(!root.adapter.discovering)
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: Theme.ink }
    }

    // a running scan: a thin bar sweeping under the strip
    Rectangle {
        visible: root.adapter !== null && root.adapter.discovering
        y: strip.height - 2
        height: 2
        width: 120
        color: Theme.accent
        SequentialAnimation on x {
            running: root.adapter !== null && root.adapter.discovering
            loops: Animation.Infinite
            NumberAnimation { from: 0; to: root.width - 120; duration: 1600; easing.type: Easing.InOutQuad }
            NumberAnimation { from: root.width - 120; to: 0; duration: 1600; easing.type: Easing.InOutQuad }
        }
    }

    // notice line (results and failures)
    Text {
        id: noticeText
        y: strip.height + 8
        width: parent.width
        visible: root.notice !== ""
        text: root.notice
        elide: Text.ElideRight
        color: /FAILED|COULD NOT/.test(root.notice) ? Theme.accent : Theme.ink
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        font.bold: true
        font.letterSpacing: 1
    }

    readonly property real bodyY: strip.height + (notice !== "" ? 34 : 14)

    // ======================================================== off / no adapter
    Column {
        visible: !root.powered
        y: root.bodyY + 40
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 14
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.adapter ? "BLUETOOTH IS OFF" : "NO BLUETOOTH ADAPTER"
            color: Theme.ink; font.family: Theme.font; font.pixelSize: Theme.fontSize + 6; font.bold: true; font.letterSpacing: 4
        }
        Caption {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.adapter ? "turn it on to see paired and nearby devices" : "plug in a Bluetooth dongle, or check that bluetooth.service runs"
        }
        ChipButton {
            visible: root.adapter !== null && root.adapter.state !== BluetoothAdapterState.Blocked
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Turn Bluetooth On"
            onClicked: root.adapter.enabled = true
        }
    }

    // ============================================================ device list
    ListView {
        id: list
        visible: root.powered
        y: root.bodyY
        width: root.listW
        height: parent.height - y
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.rows
        spacing: 0

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property var d: modelData.dev ? modelData.dev : null
            readonly property bool chosen: d !== null && d.address === root.selAddr
            width: list.width - 14
            height: modelData.hdr ? 34 : (modelData.hint ? 26 : 52)

            // section header
            Caption {
                visible: row.modelData.hdr !== undefined
                y: 14
                text: row.modelData.hdr || ""
            }
            // empty-section hint
            Text {
                visible: row.modelData.hint !== undefined
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.hint || ""
                color: Theme.inkSoft
                font.family: Theme.font
                font.pixelSize: Theme.smallFontSize
                font.italic: true
            }

            // device
            Item {
                visible: row.d !== null
                anchors.fill: parent
                readonly property bool lit: rowHit.containsMouse || row.chosen

                Rectangle { anchors.fill: parent; anchors.bottomMargin: 2; color: Theme.paperDark; visible: !parent.lit }
                Rectangle {
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 2; anchors.top: parent.top
                    width: parent.lit ? parent.width : 0
                    color: Theme.ink
                    Behavior on width { NumberAnimation { duration: Theme.hoverMs; easing.type: Easing.OutCubic } }
                }
                Rectangle {
                    id: icoBox
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -1
                    width: 32; height: 32
                    color: "transparent"
                    border.width: 1
                    border.color: parent.lit ? Theme.paper : Theme.ink
                    Text {
                        anchors.centerIn: parent
                        text: row.d ? root.glyph(row.d.icon) : ""
                        color: parent.parent.lit ? Theme.paper : Theme.ink
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 3
                    }
                }
                Column {
                    x: icoBox.x + icoBox.width + 12
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -1
                    width: parent.width - x - quick.width - 20
                    spacing: 2
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: row.d ? root.label(row.d) : ""
                        color: parent.parent.lit ? Theme.paper : Theme.ink
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                        font.bold: row.d !== null && row.d.connected
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: row.d ? root.stateText(row.d) + (row.d.batteryAvailable ? "  ·  " + Math.round(row.d.battery * 100) + "%" : "") : ""
                        color: parent.parent.lit ? Theme.paperDark : (row.d && root.busy(row.d) ? Theme.accent : Theme.inkSoft)
                        font.family: Theme.font
                        font.pixelSize: Theme.smallFontSize
                        font.letterSpacing: 1
                    }
                }
                MouseArea {
                    id: rowHit
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selAddr = row.d.address
                    onDoubleClicked: {                     // the obvious thing: connect / disconnect / pair
                        var d = row.d
                        if (root.busy(d)) return
                        if (d.connected) d.disconnect(); else if (d.paired) d.connect(); else root.pairDev(d)
                    }
                }
                // one-click action at the right end of the row
                ChipButton {
                    id: quick
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -1
                    visible: row.d !== null
                    enabledLook: row.d !== null && !root.busy(row.d) && !row.d.blocked
                    text: !row.d ? "" : row.d.connected ? "Disconnect" : row.d.paired ? "Connect" : "Pair"
                    onClicked: {
                        var d = row.d
                        if (d.connected) d.disconnect(); else if (d.paired) d.connect(); else root.pairDev(d)
                        root.selAddr = d.address
                    }
                }
            }
        }
    }
    NierScrollBar {
        visible: root.powered && span > 1
        view: list
        x: list.x + list.width - width
        y: list.y
        height: list.height
    }

    // ============================================================ right side
    Item {
        id: right
        visible: root.powered
        x: root.listW + root.gap * 2
        y: root.bodyY
        width: parent.width - x
        height: parent.height - y

        Rectangle { x: -root.gap; width: 1; height: parent.height; color: Theme.ink }

        // ---- pairing card: BlueZ is asking something -------------------------------------------------
        Rectangle {
            id: card
            readonly property var req: root.agent ? root.agent.request : null
            readonly property var disp: root.agent ? root.agent.display : null
            readonly property bool show: req !== null || disp !== null
            visible: show
            width: parent.width
            height: show ? cardCol.implicitHeight + 32 : 0
            color: "transparent"
            border.width: 2
            border.color: Theme.accent
            onReqChanged: { pinField.text = ""; if (req && (req.kind === "pin" || req.kind === "passkey")) pinField.forceActiveFocus() }

            Column {
                id: cardCol
                x: 16; y: 16
                width: parent.width - 32
                spacing: 12
                Caption { text: card.req ? "PAIRING REQUEST" : "PAIRING"; color: Theme.accent }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: card.req ? card.req.name : (card.disp ? card.disp.name : "")
                    color: Theme.ink
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 4
                    font.bold: true
                }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    color: Theme.inkSoft
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    text: {
                        var r = card.req
                        if (!r) return card.disp && card.disp.kind === "display-pin"
                                ? "Type this PIN on the device, then press Enter there."
                                : "Type this code on the device, then press Enter there."
                        if (r.kind === "confirm") return "Does the device show the same code? Only confirm if it matches."
                        if (r.kind === "pin") return "Enter the PIN for this device (often 0000 or 1234, or the one shown on it)."
                        if (r.kind === "passkey") return "Enter the 6-digit code shown on the device."
                        if (r.kind === "authorize") return "This device wants to pair with this computer."
                        return "This device wants to use a service on this computer (" + r.uuid + ")."
                    }
                }
                // the code, big and spaced out
                Text {
                    visible: (card.req && card.req.kind === "confirm") || card.disp !== null
                    text: String(card.req && card.req.passkey ? card.req.passkey : (card.disp ? card.disp.passkey : "")).split("").join(" ")
                    color: Theme.ink
                    font.family: Theme.font
                    font.pixelSize: Theme.titleSize
                    font.bold: true
                    font.letterSpacing: 6
                }
                Rectangle {
                    visible: card.req !== null && (card.req.kind === "pin" || card.req.kind === "passkey")
                    width: Math.min(parent.width, 260)
                    height: 32
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.ink
                    TextInput {
                        id: pinField
                        x: 10
                        width: parent.width - 20
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.ink
                        selectionColor: Theme.ink
                        selectedTextColor: Theme.paper
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 4
                        font.letterSpacing: 4
                        maximumLength: 16
                        validator: RegularExpressionValidator { regularExpression: card.req && card.req.kind === "passkey" ? /[0-9]{0,6}/ : /.*/ }
                        onAccepted: if (text !== "") root.agent.answer(true, text)
                    }
                }
                Row {
                    spacing: 8
                    ChipButton {
                        visible: card.req !== null
                        text: card.req && card.req.kind === "confirm" ? "Codes Match" : (card.req && (card.req.kind === "pin" || card.req.kind === "passkey") ? "Send" : "Allow")
                        enabledLook: !(card.req && (card.req.kind === "pin" || card.req.kind === "passkey") && pinField.text === "")
                        onClicked: root.agent.answer(true, pinField.text)
                    }
                    ChipButton {
                        visible: card.req !== null
                        text: "Reject"
                        onClicked: root.agent.answer(false)
                    }
                    ChipButton {
                        visible: card.req === null && card.disp !== null
                        text: "Hide"
                        onClicked: root.agent.clearDisplay()
                    }
                }
            }
        }

        // ---- the selected device --------------------------------------------------------------------
        Item {
            y: card.show ? card.height + 16 : 0
            width: parent.width
            height: parent.height - y

            Column {
                visible: root.sel === null
                y: 40
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: ""
                    color: Theme.paperDark
                    font.family: Theme.font
                    font.pixelSize: Theme.titleSize * 2
                }
                Caption { anchors.horizontalCenter: parent.horizontalCenter; text: "SELECT A DEVICE" }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: "To add one: put it in pairing mode, press SCAN,\nthen PAIR next to its name."
                    color: Theme.inkSoft
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                }
            }

            Flickable {
                id: detailFlick
                visible: root.sel !== null
                anchors.fill: parent
                contentHeight: detail.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Column {
                    id: detail
                    readonly property var d: root.sel
                    width: detailFlick.width - 14
                    spacing: 10

                    // big icon + name
                    Row {
                        spacing: 14
                        Rectangle {
                            width: 56; height: 56
                            color: detail.d && detail.d.connected ? Theme.ink : "transparent"
                            border.width: 1
                            border.color: Theme.ink
                            Text {
                                anchors.centerIn: parent
                                text: detail.d ? root.glyph(detail.d.icon) : ""
                                color: detail.d && detail.d.connected ? Theme.paper : Theme.ink
                                font.family: Theme.font
                                font.pixelSize: Theme.titleSize - 2
                            }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            Text {
                                width: detail.width - 70
                                elide: Text.ElideRight
                                text: detail.d ? root.label(detail.d) : ""
                                color: Theme.ink
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize + 6
                                font.bold: true
                            }
                            Caption {
                                text: detail.d ? root.stateText(detail.d) : ""
                                color: detail.d && root.busy(detail.d) ? Theme.accent : Theme.inkSoft
                            }
                        }
                    }

                    // battery
                    Item {
                        visible: detail.d !== null && detail.d.batteryAvailable
                        width: detail.width
                        height: 22
                        Caption { anchors.verticalCenter: parent.verticalCenter; text: "BATTERY" }
                        Rectangle {
                            x: 110
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 170
                            height: 10
                            color: Theme.paperDark
                            Rectangle {
                                height: parent.height
                                width: detail.d ? parent.width * Math.max(0, Math.min(1, detail.d.battery)) : 0
                                color: detail.d && detail.d.battery < 0.2 ? Theme.accent : Theme.ink
                                Behavior on width { NumberAnimation { duration: Theme.hoverMs } }
                            }
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: detail.d ? Math.round(detail.d.battery * 100) + "%" : ""
                            color: Theme.ink
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize
                        }
                    }

                    Column {
                        width: detail.width
                        spacing: 0
                        Line { key: "TYPE"; value: detail.d ? root.kindName(detail.d.icon) : "" }
                        Line { key: "ADDRESS"; value: detail.d ? detail.d.address : "" }
                        Line { key: "PAIRED"; value: detail.d ? (detail.d.paired ? (detail.d.bonded ? "yes (bonded)" : "yes") : "no") : "" }
                        Line { key: "TRUSTED"; value: detail.d ? (detail.d.trusted ? "yes: reconnects on its own" : "no") : "" }
                        Line { key: "BLOCKED"; value: detail.d ? (detail.d.blocked ? "yes" : "no") : "" }
                        Line { visible: detail.d !== null && detail.d.deviceName !== "" && detail.d.deviceName !== detail.d.name; key: "REPORTS ITSELF AS"; value: detail.d ? detail.d.deviceName : "" }
                    }

                    // rename (BlueZ alias)
                    Item {
                        visible: detail.d !== null && detail.d.paired
                        width: detail.width
                        height: 30
                        Rectangle {
                            width: parent.width - renameBtn.width - 8
                            height: 30
                            color: "transparent"
                            border.width: 1
                            border.color: Theme.ink
                            Caption { x: 10; anchors.verticalCenter: parent.verticalCenter; text: "NAME" }
                            TextInput {
                                id: renameField
                                x: 70
                                width: parent.width - 80
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.ink
                                selectionColor: Theme.ink
                                selectedTextColor: Theme.paper
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize
                                clip: true
                                text: detail.d ? detail.d.name : ""
                                onAccepted: if (detail.d && text.trim() !== "") detail.d.name = text.trim()
                            }
                        }
                        ChipButton {
                            id: renameBtn
                            anchors.right: parent.right
                            text: "Rename"
                            enabledLook: detail.d !== null && renameField.text.trim() !== "" && renameField.text.trim() !== detail.d.name
                            onClicked: detail.d.name = renameField.text.trim()
                        }
                    }

                    Item { width: 1; height: 4 }

                    // what you can do
                    Column {
                        width: detail.width
                        spacing: 8
                        Action {
                            visible: detail.d !== null && !detail.d.paired
                            text: detail.d && detail.d.pairing ? "Pairing… (put the device in pairing mode)" : "Pair and Connect"
                            active: detail.d !== null && !detail.d.pairing && !detail.d.blocked
                            onTriggered: root.pairDev(detail.d)
                        }
                        Action {
                            visible: detail.d !== null && detail.d.pairing
                            text: "Cancel Pairing"
                            onTriggered: { var w = Object.assign({}, root.wanted); delete w[detail.d.address]; root.wanted = w; detail.d.cancelPair() }
                        }
                        Action {
                            visible: detail.d !== null && detail.d.paired && !detail.d.connected
                            text: detail.d && detail.d.state === BluetoothDeviceState.Connecting ? "Connecting…" : "Connect"
                            active: detail.d !== null && !root.busy(detail.d) && !detail.d.blocked
                            onTriggered: detail.d.connect()
                        }
                        Action {
                            visible: detail.d !== null && detail.d.connected
                            text: "Disconnect"
                            active: detail.d !== null && !root.busy(detail.d)
                            onTriggered: detail.d.disconnect()
                        }
                        Action {
                            visible: detail.d !== null && detail.d.paired
                            text: detail.d && detail.d.trusted ? "Stop Trusting (no automatic reconnect)" : "Trust (reconnect automatically)"
                            onTriggered: detail.d.trusted = !detail.d.trusted
                        }
                        Action {
                            visible: detail.d !== null
                            text: detail.d && detail.d.blocked ? "Unblock" : "Block (refuse all connections)"
                            onTriggered: detail.d.blocked = !detail.d.blocked
                        }
                        Action {
                            visible: detail.d !== null && (detail.d.paired || detail.d.trusted)
                            text: "Forget Device (unpair)"
                            confirm: true
                            danger: true
                            onTriggered: root.forgetDev(detail.d)
                        }
                    }
                }
            }
        }
    }
}
