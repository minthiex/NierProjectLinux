import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick
import Qt.labs.folderlistmodel

// The desktop's notification daemon, drawn in the screen's style at the top middle, above windows.
// Honours Focus Mode (Missions): with do-not-disturb on, only critical notices come through.
Scope {
    id: root

    property bool dnd: false
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
        keepOnReload: false

        onNotification: note => {
            if (root.dnd && note.urgency !== NotificationUrgency.Critical) return   // not tracked: dropped
            note.tracked = true
        }
    }

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
                model: root.visibleNotes

                NotificationCard {
                    required property var modelData
                    note: modelData
                    onFinished: {
                        var n = modelData
                        visible = false                       // stop drawing before the notification object goes away
                        Qt.callLater(function () { n.expire() })
                    }
                }
            }
        }
    }
}
