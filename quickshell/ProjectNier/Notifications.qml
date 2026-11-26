import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick
import Qt.labs.folderlistmodel

// The desktop's notification daemon, drawn in the screen's style at the top middle, above windows.
// Honours Focus Mode (Missions): with do-not-disturb on, only critical notices come through.
Scope {
    id: root

    property bool dnd: false
    property int replying: 0         // cards with an open reply field
    property var shown: []           // newest first, at most `limit`
    readonly property int limit: 4

    // do-not-disturb flag file (scripts/toggle-dnd.sh): the folder is watched, so a toggle shows at once without polling
    FolderListModel {
        id: dndWatch
        folder: "file://" + Quickshell.env("HOME") + "/.local/share/ProjectNier"
        nameFilters: ["dnd"]
        showDirs: false
        showHidden: true
        onCountChanged: root.dnd = count > 0
    }

    NotificationServer {
        id: server
        actionsSupported: true
        bodyMarkupSupported: true
        imageSupported: true
        inlineReplySupported: true          // REPLY in the card (NotificationCard), used by Messenger notices
        keepOnReload: false

        onNotification: note => {
            var missed = root.dnd && note.urgency !== NotificationUrgency.Critical
            root.remember(note, missed)
            if (missed) return                    // not tracked: not shown (kept in the history, summed up after DND)
            note.tracked = true
        }
    }

    // ---- history (System → Notifications): the last 100 notices, also the ones do-not-disturb held back ----
    // ~/.local/share/ProjectNier/notices.json, mode 600 (it holds message previews); scripts/notices.py shows / clears it
    readonly property string historyPath: Quickshell.env("HOME") + "/.local/share/ProjectNier/notices.json"
    property var history: []
    property bool historyLoaded: false
    FileView {
        id: historyFile
        path: root.historyPath
        printErrors: false
        watchChanges: true                       // "Clear History" rewrites it from outside
        onFileChanged: reload()
        onLoaded: {
            try { var d = JSON.parse(text()); root.history = Array.isArray(d) ? d : [] } catch (e) { root.history = [] }
            root.historyLoaded = true
        }
        onLoadFailed: root.historyLoaded = true  // no file yet
    }
    Timer { id: historySave; interval: 1500; onTriggered: { historyFile.setText(JSON.stringify(root.history)); historyMode.running = true } }
    Process { id: historyMode; command: ["chmod", "600", root.historyPath] }
    function plain(s) {
        return String(s || "").replace(/<[^>]*>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"")
                              .replace(/&#39;|&apos;/g, "'").replace(/&amp;/g, "&").replace(/\s+/g, " ").trim()
    }
    function remember(note, missed) {
        var h = history.concat([{ t: Date.now(), app: String(note.appName || ""), summary: plain(note.summary).substring(0, 120),
                                  body: plain(note.body).substring(0, 240), missed: missed }])
        history = h.slice(-100)
        if (missed) {
            var m = Object.assign({}, missedApps)
            var a = String(note.appName || "Other")
            m[a] = (m[a] || 0) + 1
            missedApps = m
        }
        if (historyLoaded) historySave.restart()
    }

    // do-not-disturb ends: one notice sums up what it held back
    property var missedApps: ({})                // app -> notices held back since DND went on
    onDndChanged: {
        if (dnd) { missedApps = ({}); return }
        var held = missedApps, names = Object.keys(held), n = 0
        names.forEach(k => n += held[k])
        missedApps = ({})
        if (n === 0) return
        Quickshell.execDetached(["notify-send", "-a", "System", "-i", "preferences-system-notifications",
            n + (n === 1 ? " notice" : " notices") + " while Do Not Disturb was on",
            names.map(k => k + " " + held[k]).join("  ·  ") + ". System → Notifications lists them."])
    }

    function expireNote(n) { if (n) n.expire() }

    // newest on top, a few at a time (older ones wait until there is room)
    readonly property var visibleNotes: {
        var all = server.trackedNotifications.values
        var out = []
        for (var i = all.length - 1; i >= 0 && out.length < limit; i--) out.push(all[i])
        return out
    }

    PanelWindow {
        id: win
        visible: root.visibleNotes.length > 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "projectnier-notify"
        // only while a card's reply field is open: the notices never take the keyboard otherwise
        WlrLayershell.keyboardFocus: root.replying > 0 ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true }
        margins { top: 22 }
        implicitWidth: 520
        implicitHeight: Math.max(1, col.height)
        color: "transparent"
        mask: Region { item: col }

        Column {
            id: col
            width: 520
            spacing: 8

            Repeater {
                // a ScriptModel keeps the cards that stay (a plain array would rebuild every card on each new notice:
                // a reply being typed would be lost and every countdown would start over)
                model: ScriptModel { values: root.visibleNotes }

                NotificationCard {
                    required property var modelData
                    note: modelData
                    onReplyingChanged: root.replying = Math.max(0, root.replying + (replying ? 1 : -1))
                    // counted down here (not in onFinished): a card can also go away with its reply field open
                    // (the sender closed the notice), and a count left behind would keep the keyboard grabbed
                    Component.onDestruction: if (replying) root.replying = Math.max(0, root.replying - 1)
                    onFinished: {
                        visible = false                       // stop drawing before the notification object goes away
                        Qt.callLater(root.expireNote, modelData)
                    }
                }
            }
        }
    }
}
