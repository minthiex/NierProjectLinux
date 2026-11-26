import Quickshell
import QtQuick
import QtMultimedia

// A photo or video from a chat, shown inline. Photos open large when clicked.
// Videos show their poster with a play square; clicking downloads and plays them right here.
Item {
    id: root
    property var client
    property var msg
    signal enlarge(string path)          // a photo's full-size file is ready

    readonly property bool isVideo: msg.kind === "video"
    property string poster: ""           // local file of the picture shown
    property string videoFile: ""        // local file of the video once downloaded
    property bool posterFailed: false
    property bool loadingFull: false
    property bool playing: false

    // downloads answer later: by then the chat list may have destroyed this box or reused it for another message.
    // Each request carries a ticket; a JS object (kept alive by the closure) says whether the box still exists.
    property var life: ({ alive: true, ticket: 0 })
    Component.onDestruction: life.alive = false
    function later(cb) {
        var l = life, t = ++l.ticket
        return function (p) { if (l.alive && l.ticket === t) cb(p) }
    }

    function loadPoster() {
        poster = ""; posterFailed = false; videoFile = ""; playing = false; loadingFull = false
        var src = isVideo ? msg.thumb : msg.mxc          // videos need a thumbnail in their metadata
        if (!src) { posterFailed = isVideo ? false : true; return }
        var url = client.mediaUrl(src, 640, 480)
        client.fetch(url, later(function (p) { if (p === "") root.posterFailed = true; else root.poster = p }))
    }
    // the first msg arrives while the box is being created (onMsgChanged then fires too): load once, when complete
    property bool ready: false
    onMsgChanged: if (ready) loadPoster()
    Component.onCompleted: { ready = true; loadPoster() }

    function click() {
        if (isVideo) {
            if (videoFile !== "") { playing = !playing; if (playing) player.play(); else player.pause(); return }
            if (loadingFull) return
            loadingFull = true
            client.fetch(client.mediaUrl(msg.mxc, 0, 0), later(function (p) {
                root.loadingFull = false
                if (p === "") { root.posterFailed = true; return }
                root.videoFile = p; root.playing = true
                player.play()
            }))
        } else {
            if (loadingFull) return
            loadingFull = true
            client.fetch(client.mediaUrl(msg.mxc, 0, 0), later(function (p) {
                root.loadingFull = false
                if (p !== "") root.enlarge(p)
            }))
        }
    }

    // the video in its own player window (the default player; the screen floats it as a pop-out when another
    // video already plays): downloaded first if needed
    function popOut() {
        if (!isVideo) return
        if (videoFile !== "") {
            if (playing) { playing = false; player.pause() }
            Quickshell.execDetached(["xdg-open", videoFile])
            return
        }
        if (loadingFull) return
        loadingFull = true
        client.fetch(client.mediaUrl(msg.mxc, 0, 0), later(function (p) {
            root.loadingFull = false
            if (p === "") { root.posterFailed = true; return }
            root.videoFile = p
            Quickshell.execDetached(["xdg-open", p])
        }))
    }

    // ground
    Rectangle { anchors.fill: parent; color: Theme.paperDark }

    Image {
        anchors.fill: parent
        visible: root.poster !== "" && !root.playing
        source: root.poster !== "" ? "file://" + root.poster : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
    }

    Video {
        id: player
        anchors.fill: parent
        visible: root.videoFile !== ""
        source: root.videoFile !== "" ? "file://" + root.videoFile : ""
        fillMode: VideoOutput.PreserveAspectFit
        onPlaybackStateChanged: if (playbackState === MediaPlayer.StoppedState) root.playing = false
    }

    // status text while there is no picture yet
    Text {
        anchors.centerIn: parent
        visible: (root.poster === "" && root.videoFile === "")
        text: root.posterFailed ? "UNAVAILABLE" : (root.isVideo && !msg.thumb ? "VIDEO" : "LOADING")
        color: Theme.inkSoft
        font.family: Theme.font
        font.pixelSize: Theme.smallFontSize
        font.letterSpacing: 3
    }

    // play square (video, not playing) / busy note
    Rectangle {
        visible: root.isVideo && !root.playing
        anchors.centerIn: parent
        width: 44; height: 44
        color: Theme.ink
        opacity: 0.92
        Text {
            anchors.centerIn: parent
            text: root.loadingFull ? "..." : ""
            color: Theme.paper
            font.family: Theme.font
            font.pixelSize: Theme.fontSize + 4
        }
    }

    // video length
    Rectangle {
        visible: root.isVideo && msg.dur > 0 && !root.playing
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: durText.implicitWidth + 12
        height: 20
        color: Theme.ink
        Text {
            id: durText
            anchors.centerIn: parent
            readonly property int s: Math.round(msg.dur / 1000)
            text: Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60)
            color: Theme.paper
            font.family: Theme.font
            font.pixelSize: Theme.smallFontSize
        }
    }

    // thin outline
    Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: Theme.inkSoft }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.click()
    }

    // POP OUT (videos): top right corner, over the click area
    Rectangle {
        visible: root.isVideo && !root.posterFailed
        anchors.right: parent.right
        anchors.top: parent.top
        width: popText.implicitWidth + 14
        height: 20
        color: popHit.containsMouse ? Theme.ink : Theme.paperDark
        Text {
            id: popText
            anchors.centerIn: parent
            text: "POP OUT"
            color: popHit.containsMouse ? Theme.paper : Theme.ink
            font.family: Theme.font
            font.pixelSize: Theme.smallFontSize
            font.letterSpacing: 1
        }
        MouseArea { id: popHit; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.popOut() }
    }
}
