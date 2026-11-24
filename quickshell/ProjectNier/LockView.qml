import Quickshell
import Quickshell.Services.Mpris
import QtQuick

// The lock screen picture, after the NieR:Automata login screen: dark top bar with the tabs, LOGIN title and
// user plate, clock with the title and crosshair, Status panel, Authentication panel (passphrase + Restart /
// Shutdown), dark bottom bar. Keyboard input is handled here; the owner (Lock.qml) does the PAM part.
//   status: "ready" | "verifying" | "failed" | "granted"  (set by the owner)
//   Lock-out animation: bars and ground first, then the groups fade in one after another.
//   Login animation: "AUTHENTICATION COMPLETE", ink strips sweep over everything, then finished().
Item {
    id: root
    focus: true

    property string status: "ready"
    property string user: "user"
    property string host: ""
    signal submitted(string secret)
    signal touched()
    signal restartRequested()
    signal shutdownRequested()
    signal finished()

    // "intro" -> "ready" -> "afterGrant" -> "outro"
    property string mode: "intro"
    property int step: 0              // groups that have faded in
    property string secret: ""
    property string armed: ""         // "restart" | "shutdown": the next click confirms
    readonly property int stripCount: 12
    readonly property int stripDelay: 35
    readonly property int stripMs: 280
    readonly property int barH: 54
    readonly property int sideX: 100
    readonly property int panelW: 420
    readonly property bool typing: mode === "ready" && (status === "ready" || status === "failed")
    readonly property bool granted: mode === "afterGrant" || mode === "outro"

    onStatusChanged: {
        if (status === "failed") { secret = ""; shake.restart() }
        if (status === "granted") { mode = "afterGrant"; grantTimer.restart() }
        if (status === "ready" && mode === "afterGrant") mode = "ready"
    }
    Component.onCompleted: { forceActiveFocus(); stepTimer.start() }
    Timer { id: stepTimer; interval: 150; repeat: true; onTriggered: { root.step++; if (root.step >= 8) { stop(); root.mode = "ready" } } }
    Timer { id: grantTimer; interval: 1000; onTriggered: root.mode = "outro" }
    Timer { running: root.mode === "outro"; interval: root.stripCount * root.stripDelay + root.stripMs + 250; onTriggered: root.finished() }
    Timer { id: disarm; interval: 4000; onTriggered: root.armed = "" }

    SystemClock { id: clock; precision: SystemClock.Seconds }

    // media: the player that is playing (or the first paused one), shown with buttons while there is one
    readonly property var player: {
        var l = Mpris.players.values, paused = null
        for (var i = 0; i < l.length; i++) {
            if (l[i].isPlaying) return l[i]
            if (paused === null && l[i].playbackState === MprisPlaybackState.Paused) paused = l[i]
        }
        return paused
    }
    property bool mediaOn: player !== null
    property bool mediaPlaying: player ? player.isPlaying : false
    property string mediaTitle: player ? player.trackTitle : ""
    property string mediaArtist: player ? player.trackArtist : ""

    function submit() { if (typing && secret.length > 0) submitted(secret) }

    Keys.onPressed: event => {
        if (!root.typing) return
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.submit()
        else if (event.key === Qt.Key_Backspace) { root.secret = root.secret.slice(0, -1); root.touched() }
        else if (event.key === Qt.Key_Escape) { root.secret = ""; root.armed = ""; root.touched() }
        else if (event.text.length === 1 && event.text.charCodeAt(0) >= 32
                 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) { root.secret += event.text; root.touched() }
        else return
        event.accepted = true
    }

    component Lbl: Text {
        color: Theme.ink
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        font.letterSpacing: 1
    }
    // a dark plate that lights up on hover (Power Off / Reboot style)
    component DarkRow: Item {
        id: dr
        property string label
        property bool hot: false
        signal clicked()
        width: root.panelW; height: 36
        Rectangle { anchors.fill: parent; color: hit.containsMouse || dr.hot ? Theme.inkSoft : Theme.ink
                    Behavior on color { ColorAnimation { duration: Theme.hoverMs } } }
        Rectangle { x: 14; anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; rotation: 45; color: Theme.paper }
        Lbl { x: 38; anchors.verticalCenter: parent.verticalCenter; text: dr.label; color: Theme.paper }
        MouseArea { id: hit; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dr.clicked() }
    }
    // fade (and a short slide) in once its turn has come
    component Reveal: Item {
        property int turn: 0
        property int fromX: 0
        opacity: root.step > turn ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
        transform: Translate { x: root.step > turn ? 0 : fromX; Behavior on x { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } } }
    }

    // ---- ground ---------------------------------------------------------------------------------
    Rectangle { anchors.fill: parent; color: Theme.paper }
    Image { anchors.fill: parent; source: "file://" + Quickshell.shellPath("tile.png"); fillMode: Image.Tile }

    // faint diagonal lines and arcs, crosshair, dotted rows
    Canvas {
        id: deco
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d"), W = width, H = height
            ctx.clearRect(0, 0, W, H)
            function ink(a) { return Qt.rgba(Theme.ink.r, Theme.ink.g, Theme.ink.b, a) }
            ctx.lineWidth = 1
            ctx.strokeStyle = ink(0.13)
            var lines = [[0.18, 0.12, 0.40, 0.62], [0.24, 0.10, 0.50, 0.70], [0.62, 0.20, 0.86, 0.74], [0.68, 0.16, 0.92, 0.68]]
            for (var i = 0; i < lines.length; i++) {
                ctx.beginPath(); ctx.moveTo(lines[i][0] * W, lines[i][1] * H); ctx.lineTo(lines[i][2] * W, lines[i][3] * H); ctx.stroke()
            }
            ctx.beginPath(); ctx.arc(W * 0.02, H * 0.16, H * 0.22, -1.2, 1.1); ctx.stroke()
            ctx.beginPath(); ctx.arc(W * 0.02, H * 0.16, H * 0.19, -1.2, 1.1); ctx.stroke()
            ctx.beginPath(); ctx.arc(W * 0.99, H * 0.86, H * 0.28, 3.3, 4.9); ctx.stroke()
            ctx.beginPath(); ctx.arc(W * 0.99, H * 0.86, H * 0.25, 3.3, 4.9); ctx.stroke()
            // crosshair
            var cx = W / 2, cy = H * 0.57
            ctx.strokeStyle = ink(0.35)
            var rs = [62, 42, 20]
            for (var r = 0; r < rs.length; r++) { ctx.beginPath(); ctx.arc(cx, cy, rs[r], 0, Math.PI * 2); ctx.stroke() }
            ctx.beginPath(); ctx.moveTo(cx - 74, cy); ctx.lineTo(cx - 30, cy); ctx.moveTo(cx + 30, cy); ctx.lineTo(cx + 74, cy)
            ctx.moveTo(cx, cy - 74); ctx.lineTo(cx, cy - 30); ctx.moveTo(cx, cy + 30); ctx.lineTo(cx, cy + 74); ctx.stroke()
            ctx.fillStyle = ink(0.6); ctx.fillRect(cx - 2, cy - 2, 4, 4)
            ctx.strokeStyle = ink(0.12)
            ctx.beginPath(); ctx.arc(cx, cy, 190, 0, Math.PI * 2); ctx.stroke()
            // dotted rows under the top bar and over the bottom bar
            ctx.strokeStyle = ink(0.5)
            ctx.beginPath(); ctx.moveTo(0, root.barH + 6); ctx.lineTo(W, root.barH + 6); ctx.moveTo(0, H - root.barH - 6); ctx.lineTo(W, H - root.barH - 6); ctx.stroke()
            ctx.fillStyle = ink(0.75)
            for (var x = 8; x < W; x += 14) {
                ctx.fillRect(x, root.barH + 14, 4, 4)
                ctx.fillRect(x, H - root.barH - 18, 4, 4)
            }
        }
    }

    // ---- bars ------------------------------------------------------------------------------------
    Rectangle { width: parent.width; height: root.barH; color: Theme.ink }
    Row {
        x: 30; height: root.barH
        spacing: 6
        Repeater {
            model: ["LOGIN"].concat(Pages.list.map(p => p.label.toUpperCase()))
            Item {
                required property string modelData
                required property int index
                width: tabText.implicitWidth + 28; height: root.barH
                Rectangle { anchors.fill: parent; color: Theme.inkSoft; visible: index === 0 }
                Rectangle { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 5; height: 5; rotation: 45; color: Theme.paper; opacity: index === 0 ? 1 : 0.5 }
                Lbl { id: tabText; x: 22; anchors.verticalCenter: parent.verticalCenter; text: modelData; color: Theme.paper
                      opacity: index === 0 ? 1 : 0.5; font.letterSpacing: 2; font.pixelSize: Theme.smallFontSize + 1 }
            }
        }
    }

    Rectangle { y: parent.height - root.barH; width: parent.width; height: root.barH; color: Theme.ink }
    Lbl {
        x: 30; y: parent.height - root.barH + (root.barH - height) / 2
        color: root.status === "failed" ? Theme.accent : Theme.paper
        font.letterSpacing: 2
        text: root.status === "verifying" ? "Verifying credentials..."
            : root.status === "failed" ? "Authentication failed. Try again."
            : root.granted ? "Authentication complete."
            : root.armed !== "" ? "Select again to confirm."
            : "Enter credentials to proceed."
    }
    Row {
        anchors.right: parent.right; anchors.rightMargin: 30
        y: parent.height - root.barH + (root.barH - 22) / 2
        spacing: 22
        Repeater {
            model: [["Enter", "Confirm"], ["Esc", "Clear"]]
            Row {
                required property var modelData
                spacing: 8
                Rectangle { width: keyT.implicitWidth + 16; height: 22; color: Theme.paper; opacity: 0.85
                            Lbl { id: keyT; anchors.centerIn: parent; text: modelData[0]; font.pixelSize: Theme.smallFontSize } }
                Lbl { anchors.verticalCenter: parent.verticalCenter; text: modelData[1]; color: Theme.paper; opacity: 0.7; font.pixelSize: Theme.smallFontSize + 1 }
            }
        }
    }

    // ---- groups ----------------------------------------------------------------------------------
    // LOGIN title and user plate
    Reveal {
        turn: 0; fromX: -40
        x: root.sideX; y: root.height - root.barH - 20 - 130; width: 460; height: 130
        Lbl { text: "LOGIN"; font.pixelSize: 52; font.letterSpacing: 2; font.weight: Font.DemiBold }
        Rectangle { y: 66; width: parent.width; height: 3; color: "transparent"
                    Row { spacing: 4; Repeater { model: 57; Rectangle { width: 4; height: 2; color: Theme.ink; opacity: 0.7 } } } }
        Rectangle {
            y: 82; width: parent.width; height: 48; color: Theme.ink
            Rectangle { x: 16; anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: "transparent"; border.width: 1; border.color: Theme.paper }
            Lbl { x: 40; anchors.verticalCenter: parent.verticalCenter; text: root.user; color: Theme.paper; font.pixelSize: Theme.fontSize + 3; font.letterSpacing: 2 }
        }
    }

    // clock, date, title
    Reveal {
        turn: 1
        anchors.horizontalCenter: parent.horizontalCenter
        y: 250; width: 520; height: 200
        Lbl { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.formatDateTime(clock.date, "h:mm AP"); font.pixelSize: 72; font.letterSpacing: 8 }
        Lbl { y: 92; anchors.horizontalCenter: parent.horizontalCenter; color: Theme.inkSoft; font.letterSpacing: 5
              text: Qt.formatDateTime(clock.date, "yyyy.MM.dd") + "  " + Qt.formatDateTime(clock.date, "dddd").toUpperCase() }
        Lbl { y: 138; anchors.horizontalCenter: parent.horizontalCenter; text: "[  NieR:Automata  ]"; font.pixelSize: 30; font.letterSpacing: 6 }
        Lbl { y: 176; anchors.horizontalCenter: parent.horizontalCenter; text: "YoRHa Operating System"; color: Theme.inkSoft; font.pixelSize: Theme.smallFontSize; font.letterSpacing: 3 }
    }

    // Status
    Reveal {
        turn: 2; fromX: 40
        x: root.width - root.sideX - root.panelW; y: 130; width: root.panelW; height: 220
        Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: Theme.ink }
        Rectangle { width: parent.width; height: 34; color: Theme.ink
            Lbl { x: 14; anchors.verticalCenter: parent.verticalCenter; text: "Status"; color: Theme.paper; font.pixelSize: Theme.fontSize + 2 }
            Lbl { anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; text: "LOCKED"; color: Theme.paper; font.letterSpacing: 3 } }
        Rectangle { x: 16; y: 50; width: 56; height: 56; color: Theme.ink
            Lbl { anchors.centerIn: parent; text: root.user.substring(0, 2).toUpperCase(); color: Theme.paper; font.pixelSize: 20 } }
        Column {
            x: 92; y: 50; spacing: 8
            Repeater {
                model: [["Unit", root.host.toUpperCase()], ["User", root.user.toUpperCase()], ["Session", "HYPRLAND"], ["Auth", root.granted ? "Ok" : root.status === "failed" ? "Denied" : "Pending"]]
                Row {
                    required property var modelData
                    Lbl { width: 90; text: modelData[0]; color: Theme.inkSoft; font.pixelSize: Theme.smallFontSize }
                    Lbl { text: modelData[1]; font.pixelSize: Theme.smallFontSize; color: modelData[0] === "Auth" && root.status === "failed" ? Theme.accent : Theme.ink }
                }
            }
        }
        Rectangle { x: 16; y: 150; width: parent.width - 32; height: 1; color: Theme.ink; opacity: 0.4 }
        Lbl { y: 170; anchors.horizontalCenter: parent.horizontalCenter; text: "SYSTEM STATE: NO ERROR"; color: Theme.inkSoft; font.pixelSize: Theme.smallFontSize - 1; font.letterSpacing: 3 }
    }

    // Authentication
    Reveal {
        turn: 3
        anchors.horizontalCenter: parent.horizontalCenter
        y: 736; width: root.panelW; height: 236
        Rectangle { width: parent.width; height: 34; color: Theme.ink
            Lbl { id: authHead; x: 14; anchors.verticalCenter: parent.verticalCenter; color: Theme.paper; font.pixelSize: Theme.fontSize + 2
                  readonly property string full: "Authentication"
                  property int n: root.step > 3 ? 14 : 0
                  Behavior on n { NumberAnimation { duration: 600 } }
                  text: full.substring(0, n) } }
        // passphrase field
        Rectangle {
            id: field
            y: 46; width: parent.width; height: 42
            color: Theme.ink
            border.width: root.status === "failed" ? 2 : 0
            border.color: Theme.accent
            transform: Translate { id: shiftX }
            Lbl { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "Passphrase..."; color: Theme.paper; opacity: 0.45; visible: root.secret.length === 0 }
            Row {
                x: 16; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                Repeater { model: Math.min(root.secret.length, 26)
                    Rectangle { width: 9; height: 9; rotation: 45; color: root.status === "failed" ? Theme.accent : Theme.paper } }
                Rectangle { width: 8; height: 2; y: 6; color: Theme.paper; visible: root.typing && root.secret.length > 0
                    SequentialAnimation on opacity { loops: Animation.Infinite; running: root.typing
                        NumberAnimation { to: 0; duration: 450 } NumberAnimation { to: 1; duration: 450 } } }
            }
            Rectangle {   // run along the bottom edge while checking
                visible: root.status === "verifying"
                anchors.bottom: parent.bottom; height: 3; width: 70; color: Theme.accent
                SequentialAnimation on x { loops: Animation.Infinite; running: root.status === "verifying"
                    NumberAnimation { from: 0; to: field.width - 70; duration: 450; easing.type: Easing.InOutQuad }
                    NumberAnimation { from: field.width - 70; to: 0; duration: 450; easing.type: Easing.InOutQuad } }
            }
            Rectangle {   // submit arrow
                anchors.right: parent.right; width: 42; height: 42
                color: sub.containsMouse ? Theme.inkSoft : "transparent"
                Lbl { anchors.centerIn: parent; text: "▶"; color: Theme.paper; opacity: root.secret.length > 0 ? 1 : 0.4 }
                MouseArea { id: sub; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.submit() }
            }
        }
        DarkRow {
            y: 104
            label: root.armed === "shutdown" ? "Confirm Shutdown?" : "Shutdown"
            hot: root.armed === "shutdown"
            onClicked: { if (root.armed === "shutdown") root.shutdownRequested(); else { root.armed = "shutdown"; disarm.restart() } }
        }
        DarkRow {
            y: 148
            label: root.armed === "restart" ? "Confirm Restart?" : "Restart"
            hot: root.armed === "restart"
            onClicked: { if (root.armed === "restart") root.restartRequested(); else { root.armed = "restart"; disarm.restart() } }
        }
        DarkRow { y: 192; label: "Session: Hyprland"; enabled: false; opacity: 0.55 }
    }

    // bottom left: location / status text
    Reveal {
        turn: 4; fromX: -40
        x: root.sideX; y: 130; width: 460; height: 170
        Rectangle { width: parent.width; height: 1; color: Theme.ink; opacity: 0.5 }
        Lbl { y: 14; text: "CURRENT STATE: SESSION LOCKED"; color: Theme.inkSoft; font.pixelSize: Theme.smallFontSize - 1; font.letterSpacing: 2 }
        Lbl { y: 44; text: "MISSION STATUS: ACTIVE"; font.pixelSize: Theme.smallFontSize; font.letterSpacing: 2 }
        Lbl { y: 66; width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: Theme.smallFontSize; color: Theme.inkSoft
              text: "Objective: authenticate to resume the session. Running applications are held in place." }
        Lbl { y: 126; text: "SYSTEM SYNCHRONIZATION: HELD"; color: Theme.termGreen; font.pixelSize: Theme.smallFontSize - 1; font.letterSpacing: 2 }
        Lbl { y: 144; text: "POD 042 / " + root.host.toUpperCase() + " SYNC: 100%"; color: Theme.termGreen; font.pixelSize: Theme.smallFontSize; font.letterSpacing: 1 }
    }

    // media controls (left, only while something is playing)
    Reveal {
        turn: 4; fromX: -40
        visible: root.mediaOn
        x: root.sideX; y: 400; width: 460; height: 150
        Rectangle { width: parent.width; height: 1; color: Theme.ink; opacity: 0.5 }
        Lbl { y: 14; text: root.mediaPlaying ? "NOW PLAYING" : "PAUSED"; color: Theme.inkSoft; font.pixelSize: Theme.smallFontSize - 1; font.letterSpacing: 3 }
        Lbl { y: 40; width: parent.width; elide: Text.ElideRight; text: root.mediaTitle !== "" ? root.mediaTitle : "Unknown track"; font.pixelSize: Theme.fontSize + 3; font.letterSpacing: 1 }
        Lbl { y: 68; width: parent.width; elide: Text.ElideRight; text: root.mediaArtist; color: Theme.inkSoft; font.pixelSize: Theme.smallFontSize + 1 }
        Row {
            y: 100; spacing: 8
            Repeater {
                model: [["\u25c0\u25c0", "prev"], [root.mediaPlaying ? "\u2759\u2759" : "\u25b6", "toggle"], ["\u25b6\u25b6", "next"]]
                Item {
                    required property var modelData
                    width: 84; height: 36
                    Rectangle { anchors.fill: parent; color: mhit.containsMouse ? Theme.inkSoft : Theme.ink
                                Behavior on color { ColorAnimation { duration: Theme.hoverMs } } }
                    Lbl { anchors.centerIn: parent; text: modelData[0]; color: Theme.paper }
                    MouseArea {
                        id: mhit; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var p = root.player
                            if (!p) return
                            if (modelData[1] === "prev") p.previous()
                            else if (modelData[1] === "next") p.next()
                            else p.togglePlaying()
                        }
                    }
                }
            }
        }
    }

    // bottom right: link badge
    Reveal {
        turn: 5; fromX: 40
        x: root.width - root.sideX - 200; y: root.height - root.barH - 130; width: 200; height: 56
        Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: Theme.ink }
        Lbl { x: 10; y: 6; text: "SATELLITE LINK (BUNKER)"; color: Theme.inkSoft; font.pixelSize: Theme.smallFontSize - 2; font.letterSpacing: 1 }
        Rectangle { x: 10; y: 26; width: 38; height: 20; color: Theme.ink
            Lbl { anchors.centerIn: parent; text: "LINK"; color: Theme.paper; font.pixelSize: Theme.smallFontSize - 2 } }
        Lbl { x: 58; y: 29; text: "SECURE CH-04"; font.pixelSize: Theme.smallFontSize - 1; font.letterSpacing: 1 }
    }

    // left edge caption
    Lbl { x: 8; y: root.barH + 40; rotation: 90; transformOrigin: Item.TopLeft
          text: "SYSTEM ACCESS"; color: Theme.inkSoft; font.pixelSize: Theme.smallFontSize - 2; font.letterSpacing: 3
          opacity: root.step > 5 ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 420 } } }

    SequentialAnimation {
        id: shake
        NumberAnimation { target: shiftX; property: "x"; to: -14; duration: 50 }
        NumberAnimation { target: shiftX; property: "x"; to: 14; duration: 80 }
        NumberAnimation { target: shiftX; property: "x"; to: -9; duration: 70 }
        NumberAnimation { target: shiftX; property: "x"; to: 9; duration: 70 }
        NumberAnimation { target: shiftX; property: "x"; to: 0; duration: 50 }
    }

    // ---- login: strips sweep over everything --------------------------------------------------------
    Repeater {
        model: root.stripCount
        Rectangle {
            id: strip
            required property int index
            y: Math.floor(index * root.height / root.stripCount)
            height: Math.ceil(root.height / root.stripCount) + 1
            color: Theme.ink
            x: 0; width: 0; z: 100
            SequentialAnimation {
                running: root.mode === "outro"
                PauseAnimation { duration: strip.index * root.stripDelay }
                NumberAnimation { target: strip; property: "width"; from: 0; to: root.width; duration: root.stripMs; easing.type: Easing.InOutCubic }
            }
        }
    }
}
