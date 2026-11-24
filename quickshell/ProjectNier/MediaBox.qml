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

    function loadPoster() {
        poster = ""; posterFailed = false; videoFile = ""; playing = false; loadingFull = false
        var src = isVideo ? msg.thumb : msg.mxc          // videos need a thumbnail in their metadata
        if (!src) { posterFailed = isVideo ? false : true; return }
        var url = client.mediaUrl(src, 640, 480)
        client.fetch(url, function (p) { if (p === "") posterFailed = true; else poster = p })
    }
    onMsgChanged: loadPoster()
    Component.onCompleted: loadPoster()

    function click() {
        if (isVideo) {
            if (videoFile !== "") { playing = !playing; if (playing) player.play(); else player.pause(); return }
            if (loadingFull) return
            loadingFull = true
            client.fetch(client.mediaUrl(msg.mxc, 0, 0), function (p) {
                loadingFull = false
                if (p === "") { posterFailed = true; return }
                videoFile = p; playing = true
                player.play()
            })
        } else {
            if (loadingFull) return
            loadingFull = true
            client.fetch(client.mediaUrl(msg.mxc, 0, 0), function (p) {
                loadingFull = false
                if (p !== "") root.enlarge(p)
            })
        }
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
}
