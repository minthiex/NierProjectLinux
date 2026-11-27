import Quickshell
import Quickshell.Io
import QtQuick

// Right-hand panel for a sub-function: dark title bar, key / value rows (optional
// percent bars, optional click command), an optional text field and action buttons.
// Opening wipes the bar in and brings the rows in one after another.
Item {
    id: root
    property string name
    property var spec: ({})

    property var rows: []            // [[key, value, pct, click]]
    readonly property var actions: spec.actions ? spec.actions : []
    readonly property bool hasInput: spec.input !== undefined
    readonly property int rowH: 28
    readonly property real contentH: lower.y + lower.height
    signal openTerm(string title, var cmd)   // an action wants to run in the content window
    signal openApp(string app)               // an action wants a built-in app in the content window
    signal hideSub()                         // the "-" in the title bar: take this sub-function out of its menu
    signal restoreSub(string key)            // "Restore ..." button of the Restore Functions sub-function
    signal removeSub(string key)             // its "-": remove that hidden sub-function for good
    property bool hideArmed: false
    signal removeApp(string cls, string title)           // the "-" button on a registered application's row
    signal openViewer(var cmd)               // an image was clicked: show it in the image viewer
    signal openFm(var cmd)                   // an action wants the file manager: go to the File Manager sub-function
    signal launching()                       // something is about to start an application window
    signal gate(var what, var go, bool app)   // an app wants the content window: the screen may ask first, then calls go()
                                          // (app: a window of its own, which may share the frame with the open one)

    // clicking the result itself refreshes it (rows with their own click command, buttons and the text field keep theirs)
    MouseArea {
        anchors.fill: parent
        z: -1
        cursorShape: root.spec.script !== undefined ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.refresh()
    }

    // ---- running things -------------------------------------------------------------
    // delay: ms before the panel refreshes after a quiet command (the action's own, else the spec's, else 700)
    function run(cmd, term, quiet, launch, delay) {
        var wait = delay !== undefined ? delay : (spec.delay !== undefined ? spec.delay : 700)
        // anything that starts the file manager shows the File Manager sub-function (Dolphin opens there, at the path)
        if (!term && cmd.length > 0 && cmd[0] === "dolphin") { root.openFm(cmd); return }
        if (!term && launch === true) { root.gate(cmd, () => root.run(cmd, false, quiet, false), true); return }
        if (!term && wait === 0) {
            // no delay: wait for the command itself to finish, then refresh straight away
            runner.running = false
            runner.command = cmd
            runner.running = true
            return
        }
        if (term) { root.gate(cmd, () => root.openTerm(root.name, cmd), false); return }
        if (!quiet) root.launching()      // a window it opens belongs to this sub-function (quiet commands open none)
        Quickshell.execDetached(cmd)
        if (quiet || spec.script) { later.interval = Math.max(1, wait); later.restart() }
    }

    Process {
        id: runner
        onExited: root.refresh()
    }

    function clickRow(cmd) {
        if (cmd.indexOf("term:") === 0) run(["sh", "-c", cmd.substring(5)], true, false)
        else if (cmd.indexOf("dolphin ") === 0) openFm(["sh", "-c", cmd])
        else if (cmd.indexOf("gwenview ") === 0) openViewer(["sh", "-c", cmd])
        else {
            // rows that start a program (a file in its app, a game from the Game Library): its window belongs here.
            // Other rows (connect a device, pick an output, tick a task) open no window and must not claim one.
            if (/^(xdg-open|gio open|steam|lutris|heroic) /.test(cmd)) root.launching()
            run(["sh", "-c", cmd], false, true)
        }
    }

    Timer { id: later; interval: 700; onTriggered: root.refresh() }

    // ---- data ----------------------------------------------------------------------
    // Every refresh starts its own process, tagged with a generation number. Output that
    // arrives for an older generation (you switched panels meanwhile) is thrown away,
    // so a slow script can never overwrite the panel that is showing now.
    property int gen: 0
    property var current: null

    function refresh() {
        gen++
        if (current) { current.running = false; current = null }
        if (!spec.script) return
        var p = procComp.createObject(root, {
            gen: gen,
            command: ["sh", Quickshell.shellPath("scripts/" + spec.script)].concat(spec.args ? spec.args : [])
        })
        current = p
        p.running = true
        p.destroy(90000)           // slow ones (checkupdates on a slow mirror, the self check) need well over 20 s
    }

    function accept(g, text) {
        if (g !== gen || !spec.script) return
        var out = []
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
            if (lines[i] === "") continue
            var c = lines[i].split("\t")
            out.push([c[0] ? c[0] : "", c[1] ? c[1] : "",
                      (c.length > 2 && c[2] !== "") ? Number(c[2]) : -1,
                      c.length > 3 ? c.slice(3).join("\t") : ""])     // the click command may hold a quoted TAB
        }
        rows = out
    }

    onSpecChanged: {
        hideArmed = false
        gen++                      // anything still running belongs to the previous panel
        rows = spec.rows ? spec.rows : []
        wipe.restart()
        refresh()
    }

    Component {
        id: procComp
        Process {
            id: p
            property int gen: 0
            stdout: StdioCollector {
                onStreamFinished: root.accept(p.gen, text)
            }
        }
    }

    Timer {
        interval: root.spec.interval ? root.spec.interval : 1000
        running: root.visible && root.spec.script !== undefined && root.spec.interval > 0
        repeat: true
        onTriggered: root.refresh()
    }

    // ---- title bar -------------------------------------------------------------------
    Item {
        id: head
        width: parent.width
        height: 30

        Rectangle {
            id: bar
            height: parent.height
            width: 0
            color: Theme.ink
        }

        Text {
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            text: root.name
            color: Theme.paper
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            font.bold: true
            font.letterSpacing: 1
            opacity: bar.width > 80 ? 1 : 0
        }

        // "-": hide this sub-function (second click confirms)
        Rectangle {
            id: hideBtn
            visible: root.name !== Registry.restoreName && !root.spec.noHide      // the way back must stay
            anchors.right: parent.right
            anchors.rightMargin: root.spec.script !== undefined ? 36 : 8
            anchors.verticalCenter: parent.verticalCenter
            width: root.hideArmed ? hideText.implicitWidth + 14 : 18; height: 18
            color: (hideHit.containsMouse || root.hideArmed) ? Theme.accent : "transparent"
            border.width: 1
            border.color: Theme.paper
            opacity: bar.width > head.width - 40 ? 1 : 0
            Text {
                id: hideText
                anchors.centerIn: parent
                text: root.hideArmed ? "Hide?" : "\u2212"
                color: Theme.paper
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }
            MouseArea {
                id: hideHit
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (!root.hideArmed) { root.hideArmed = true; hideDisarm.restart(); return }
                    root.hideArmed = false
                    root.hideSub()
                }
                onExited: if (root.hideArmed) hideDisarm.restart()
            }
            Timer { id: hideDisarm; interval: 2500; onTriggered: root.hideArmed = false }
        }

        // refresh
        Text {
            visible: root.spec.script !== undefined
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: "↻"
            color: Theme.paper
            font.family: Theme.font
            font.pixelSize: Theme.fontSize + 2
            opacity: bar.width > head.width - 40 ? 1 : 0

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: root.refresh()
            }
        }
    }

    NumberAnimation {
        id: wipe
        target: bar
        property: "width"
        from: 0
        to: head.width
        duration: Theme.hoverMs * 2
        easing.type: Easing.OutCubic
    }

    // ---- rows ------------------------------------------------------------------------
    Flickable {
        id: flick
        y: head.height + 8
        width: parent.width
        height: Math.min(col.height, Math.max(0, root.height - head.height - 8 - lower.height - (lower.height > 0 ? 12 : 0)))
        contentHeight: col.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
            id: col
            width: flick.width

            Repeater {
                model: root.rows.length

                Item {
                    id: line
                    required property int index
                    readonly property var r: root.rows[index] ? root.rows[index] : ["", "", -1, ""]
                    readonly property bool clickable: r[3] !== undefined && r[3] !== ""
                    width: col.width
                    height: root.rowH
                    opacity: 0
                    x: 14

                    SequentialAnimation {
                        id: reveal
                        PauseAnimation { duration: Math.min(line.index, 14) * 35 }
                        ParallelAnimation {
                            NumberAnimation { target: line; property: "opacity"; to: 1; duration: Theme.hoverMs }
                            NumberAnimation { target: line; property: "x"; to: 0; duration: Theme.hoverMs; easing.type: Easing.OutCubic }
                        }
                    }
                    Component.onCompleted: reveal.start()

                    // hover bar for rows that can be clicked
                    Rectangle {
                        height: parent.height - 1
                        width: rowHit.containsMouse && line.clickable ? parent.width : 0
                        color: Theme.ink
                        Behavior on width { NumberAnimation { duration: Theme.hoverMs; easing.type: Easing.OutCubic } }
                    }

                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.paperDark }

                    readonly property color fg: (line.clickable && rowHit.containsMouse) ? Theme.paper : Theme.ink

                    Text {
                        id: key
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width * 0.45)
                        elide: Text.ElideRight
                        text: line.r[0]
                        color: line.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                        font.letterSpacing: 1
                    }

                    // percent bar
                    Rectangle {
                        visible: line.r[2] >= 0
                        x: parent.width * 0.42
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * 0.22
                        height: 8
                        color: Theme.paperDark

                        Rectangle {
                            height: parent.height
                            width: parent.width * Math.max(0, Math.min(100, line.r[2])) / 100
                            color: Theme.ink
                            Behavior on width { NumberAnimation { duration: Theme.hoverMs } }
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: line.r[2] >= 0 ? parent.width * 0.32 : Math.max(0, parent.width - key.width - 40)
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        text: line.r[1]
                        color: line.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                    }

                    MouseArea {
                        id: rowHit
                        anchors.fill: parent
                        hoverEnabled: line.clickable
                        enabled: line.clickable
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.clickRow(line.r[3])
                    }
                }
            }
        }
    }

    Component {
        id: fieldBox

        Item {
            Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: Theme.ink }
            Rectangle {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 10; height: 10
                color: Theme.ink
            }

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
                clip: true
                onAccepted: {
                    var t = field.text.trim()
                    if (t === "") return
                    var inp = root.spec.input
                    root.run(inp.cmd.concat([t]), inp.term === true, true, inp.launch === true)
                    field.text = ""
                }

                Text {
                    visible: field.text === "" && !field.activeFocus
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.spec.input ? root.spec.input.placeholder : ""
                    color: Theme.inkSoft
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                }
            }
        }
    }

    // ---- calendar (the Calendar sub-function): in the middle of the result window ----
    CalendarBox {
        id: calBox
        visible: root.spec.calendar === true
        anchors.horizontalCenter: parent.horizontalCenter
        y: head.height + 24
    }

    // ---- text field + actions ------------------------------------------------------------
    Column {
        id: lower
        y: Math.max(flick.y + flick.height, calBox.visible ? calBox.y + calBox.height + 20 : 0) + ((root.hasInput || root.actions.length > 0) ? 12 : 0)
        width: parent.width
        spacing: 10
        height: (root.hasInput ? 30 : 0) + (root.actions.length > 0 ? root.actions.length * 28 + (root.actions.length - 1) * 10 : 0)
                + (root.hasInput && root.actions.length > 0 ? 10 : 0)

        // text field (only created for panels that have one)
        Item {
            visible: root.hasInput
            width: lower.width
            height: root.hasInput ? 30 : 0

            Loader {
                anchors.fill: parent
                active: root.hasInput
                sourceComponent: fieldBox
            }
        }

        Repeater {
            model: root.actions

            Item {
                id: btn
                required property var modelData
                required property int index
                property bool armed: false
                property bool rmArmed: false
                readonly property bool lit: hit.containsMouse || armed || rmArmed
                width: lower.width
                height: 28

                Timer { id: disarm; interval: 3000; onTriggered: btn.armed = false }
                Timer { id: rmDisarm; interval: 4000; onTriggered: btn.rmArmed = false }

                Rectangle { anchors.fill: parent; color: Theme.paperDark }
                Rectangle {
                    height: parent.height
                    width: btn.lit ? parent.width : 0
                    color: Theme.ink
                    Behavior on width { NumberAnimation { duration: Theme.hoverMs; easing.type: Easing.OutCubic } }
                }
                Rectangle {
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10; height: 10
                    color: btn.lit ? Theme.paper : Theme.ink
                }
                Text {
                    x: 30
                    anchors.verticalCenter: parent.verticalCenter
                    text: btn.rmArmed ? (btn.modelData.removeKey !== undefined ? "Remove for good?  Click \u2212 again to confirm"
                                                                       : "Remove from list?  Click \u2212 again to confirm") : (btn.armed ? "Click again to confirm:  " + btn.modelData.label : btn.modelData.label)
                    color: btn.lit ? Theme.paper : Theme.ink
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    font.letterSpacing: 1
                    Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                }
                MouseArea {
                    id: hit
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (btn.modelData.confirm && !btn.armed) {
                            btn.armed = true
                            disarm.restart()
                            return
                        }
                        btn.armed = false
                        if (btn.modelData.restoreKey !== undefined) { root.restoreSub(btn.modelData.restoreKey); return }
                        if (btn.modelData.app) { root.gate(btn.modelData.app, () => root.openApp(btn.modelData.app), false); return }
                        if (btn.modelData.fm === true) { root.openFm(btn.modelData.cmd); return }
                        root.run(btn.modelData.cmd, btn.modelData.term === true, btn.modelData.quiet === true, btn.modelData.launch === true, btn.modelData.delay)
                    }
                    onExited: if (btn.armed) disarm.restart()
                }
                // "-": take a registered application out of this list / remove a hidden sub-function for good
                Rectangle {
                    visible: btn.modelData.removeCls !== undefined || btn.modelData.removeKey !== undefined
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18
                    color: (rm.containsMouse || btn.rmArmed) ? Theme.accent : "transparent"
                    border.width: 1
                    border.color: btn.lit ? Theme.paper : Theme.ink
                    Text {
                        anchors.centerIn: parent
                        text: "\u2212"
                        color: btn.lit ? Theme.paper : Theme.ink
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                    }
                    MouseArea {
                        id: rm
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!btn.rmArmed) { btn.rmArmed = true; rmDisarm.restart(); return }
                            btn.rmArmed = false
                            if (btn.modelData.removeKey !== undefined) { root.removeSub(btn.modelData.removeKey); return }
                            root.removeApp(btn.modelData.removeCls, btn.modelData.removeTitle || "")
                        }
                        onExited: if (btn.rmArmed) rmDisarm.restart()
                    }
                }
            }
        }
    }
}
