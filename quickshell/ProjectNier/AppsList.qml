import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import QtQuick

// Every open application window, as small tan chips. Click one to bring it forward;
// the focused one stays dark. (The content terminal windows are left out.)
Item {
    id: root

    property var contentApps: []        // [{ slug, name }]: apps running in the content windows
    property var managed: ({})          // window class -> sub-function slug (apps placed in a content frame)
    property var extWins: []            // [{ addr, slug, cls }]: windows placed in a content frame
    signal windowClicked(string addr, string cls)   // a window that is not in a content frame was clicked
    property string activeSlug: ""
    signal contentClicked(string slug)
    signal contentClosed(string slug)

    readonly property var niceNames: ({})
    property var steamNames: ({})       // Steam app id -> game name (windows of Steam games have the class steam_app_<id>)
    function nice(id) {
        if (niceNames[id]) return niceNames[id]
        var g = /^steam_app_(\d+)$/.exec(String(id))
        if (g) return steamNames[g[1]] || "Steam Game"
        var s = String(id).replace(/^.*\./, "").replace(/-/g, " ")
        return s.charAt(0).toUpperCase() + s.substring(1)
    }

    // first icon the theme actually has: the desktop entry's, then guesses from the window class
    function findIcon(appId, entry) {
        var id = String(appId)
        var names = []
        if (entry && entry.icon) names.push(entry.icon)
        names.push(id, id.toLowerCase(), id.toLowerCase() + "-browser", id.toLowerCase() + "-desktop",
                   id.toLowerCase().replace(/-.*$/, ""))
        for (var i = 0; i < names.length; i++) {
            var path = Quickshell.iconPath(names[i], true)
            if (path !== "") return path
        }
        return ""
    }

    Text {
        id: label
        text: "APPS"
        color: Theme.inkSoft
        font.family: Theme.font
        font.pixelSize: Theme.smallFontSize
        font.letterSpacing: 3
        font.bold: true
    }

    Flickable {
        id: flick
        y: label.height + 6
        width: parent.width
        height: 24
        contentWidth: row.width
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentWidth > width

        Row {
            id: row
            spacing: 8

            Repeater {
                model: ToplevelManager.toplevels

                Item {
                    id: chip
                    required property var modelData
                    readonly property bool mine: modelData.appId === "projectnier-term"
                    readonly property bool lit: hit.containsMouse || modelData.activated

                    // the app's icon (from its desktop entry, else a guess from its class)
                    readonly property var entry: DesktopEntries.heuristicLookup(modelData.appId)
                    readonly property string iconSrc: root.findIcon(modelData.appId, entry)
                    readonly property bool hasIcon: iconSrc !== ""

                    visible: !mine
                    width: mine ? 0 : txt.x + txt.implicitWidth + 10
                    height: 24

                    Rectangle { anchors.fill: parent; color: Theme.paperDark }
                    Rectangle {
                        height: parent.height
                        width: chip.lit ? parent.width : 0
                        color: Theme.ink
                        Behavior on width { NumberAnimation { duration: Theme.hoverMs; easing.type: Easing.OutCubic } }
                    }
                    IconImage {
                        visible: chip.hasIcon
                        x: 5
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: 16
                        source: chip.iconSrc
                    }
                    // no icon in the theme (terminal apps and the like): a small terminal glyph in a dark box
                    Rectangle {
                        visible: !chip.hasIcon
                        x: 5
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16; height: 16
                        color: chip.lit ? Theme.paper : Theme.ink
                        Text {
                            anchors.centerIn: parent
                            text: "\uf120"
                            color: chip.lit ? Theme.ink : Theme.paper
                            font.family: Theme.font
                            font.pixelSize: Theme.smallFontSize
                        }
                    }
                    Text {
                        id: txt
                        x: 26
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.nice(chip.modelData.appId)
                        color: chip.lit ? Theme.paper : Theme.ink
                        font.family: Theme.font
                        font.pixelSize: Theme.smallFontSize + 1
                        Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                    }
                    // the window's Hyprland address (no 0x), to find it among the placed windows
                    readonly property string addr: {
                        var h = Hyprland.toplevels.values
                        for (var i = 0; i < h.length; i++)
                            if (h[i].wayland === chip.modelData) return String(h[i].address).replace(/^0x/, "").toLowerCase()
                        return ""
                    }
                    readonly property string managedSlug: {
                        for (var i = 0; i < root.extWins.length; i++) if (root.extWins[i].addr.toLowerCase() === chip.addr) return root.extWins[i].slug
                        return root.managed[modelData.appId] ? root.managed[modelData.appId] : ""
                    }

                    // process id of this window (from Hyprland)
                    function pidOf() {
                        var h = Hyprland.toplevels.values
                        for (var i = 0; i < h.length; i++)
                            if (h[i].wayland === chip.modelData && h[i].lastIpcObject) return h[i].lastIpcObject.pid
                        return 0
                    }

                    ThemedMenu {
                        id: ctx
                        target: chip
                        items: chip.managedSlug !== "" ? [
                            { text: "Show", run: () => root.contentClicked(chip.managedSlug) },
                            { separator: true },
                            { text: "Close and End Process", danger: true, confirm: true, run: () => root.contentClosed(chip.managedSlug) }
                        ] : [
                            { text: "Bring Forward", run: () => chip.modelData.activate() },
                            { text: "Close Window", run: () => chip.modelData.close() },
                            { separator: true },
                            { text: "Kill Process", danger: true, confirm: true, run: () => {
                                Hyprland.refreshToplevels()
                                var pid = chip.pidOf()
                                if (pid > 0) Quickshell.execDetached(["bash", Panes.script("kill-tree.sh"), String(pid)])
                            } }
                        ]
                    }

                    MouseArea {
                        id: hit
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) { Hyprland.refreshToplevels(); ctx.open() }
                            else if (chip.managedSlug !== "") root.contentClicked(chip.managedSlug)
                            else if (chip.addr !== "") root.windowClicked(chip.addr, chip.modelData.appId)
                            else chip.modelData.activate()
                        }
                    }
                }
            }

            // apps running inside the content windows
            Repeater {
                model: root.contentApps

                Item {
                    id: cchip
                    required property var modelData
                    readonly property bool lit: chit.containsMouse || root.activeSlug === modelData.slug
                    width: ctxt.x + ctxt.implicitWidth + 10
                    height: 24

                    Rectangle { anchors.fill: parent; color: Theme.paperDark }
                    Rectangle {
                        height: parent.height
                        width: cchip.lit ? parent.width : 0
                        color: Theme.ink
                        Behavior on width { NumberAnimation { duration: Theme.hoverMs; easing.type: Easing.OutCubic } }
                    }
                    Rectangle {
                        x: 5
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16; height: 16
                        color: cchip.lit ? Theme.paper : Theme.ink
                        Text {
                            anchors.centerIn: parent
                            text: "\uf120"
                            color: cchip.lit ? Theme.ink : Theme.paper
                            font.family: Theme.font
                            font.pixelSize: Theme.smallFontSize
                        }
                    }
                    Text {
                        id: ctxt
                        x: 26
                        anchors.verticalCenter: parent.verticalCenter
                        text: cchip.modelData.name
                        color: cchip.lit ? Theme.paper : Theme.ink
                        font.family: Theme.font
                        font.pixelSize: Theme.smallFontSize + 1
                        Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                    }

                    ThemedMenu {
                        id: cctx
                        target: cchip
                        items: [
                            { text: "Show", run: () => root.contentClicked(cchip.modelData.slug) },
                            { separator: true },
                            { text: "Close and End Process", danger: true, confirm: true, run: () => root.contentClosed(cchip.modelData.slug) }
                        ]
                    }

                    MouseArea {
                        id: chit
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) cctx.open()
                            else root.contentClicked(cchip.modelData.slug)
                        }
                    }
                }
            }

            Text {
                visible: root.contentApps.length === 0 && ToplevelManager.toplevels.values.filter(t => t.appId !== "projectnier-term").length === 0
                anchors.verticalCenter: parent.verticalCenter
                text: "NONE OPEN"
                color: Theme.paperDark
                font.family: Theme.font
                font.pixelSize: Theme.smallFontSize + 1
                font.letterSpacing: 2
            }
        }
    }
}
