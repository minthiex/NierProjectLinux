import Quickshell
import QtQuick

// Tab row with a solid rule and a dotted band underneath, edge to edge.
Item {
    id: root
    implicitHeight: Theme.menuH + Theme.ruleGap + 2 + Theme.bandH

    property int current: -1
    property var badges: ({})           // label -> count shown as "(N)"
    signal picked(int index)

    property var entries: []

    // tabs keep their natural (narrow) width; the gaps stretch so the row spans the full width
    property real sumW: 0
    function recalc() {
        var s = 0
        for (var i = 0; i < rep.count; i++) {
            var it = rep.itemAt(i)
            if (it) s += it.width
        }
        sumW = s
    }

    Row {
        x: Theme.tabInset
        spacing: Math.max(Theme.menuGap, (root.width - Theme.tabInset * 2 - root.sumW) / Math.max(1, rep.count - 1))

        Repeater {
            id: rep
            model: root.entries
            onItemAdded: root.recalc()

            MenuItem {
                required property var modelData
                required property int index
                icon: modelData.icon
                label: modelData.label
                badge: root.badges[modelData.label] > 0 ? "(" + root.badges[modelData.label] + ")" : ""
                selected: root.current === index
                onClicked: root.picked(index)
                onWidthChanged: root.recalc()
            }
        }
    }

    // solid rule
    Rectangle {
        y: Theme.menuH + Theme.ruleGap
        width: parent.width
        height: 2
        color: Theme.ink
    }

    // dotted band
    Image {
        y: Theme.menuH + Theme.ruleGap + 2
        width: parent.width
        height: Theme.bandH
        source: "file://" + Quickshell.shellPath("band.png")
        fillMode: Image.Tile
    }
}
