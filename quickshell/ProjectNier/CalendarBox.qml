import QtQuick

// Month calendar for the Calendar sub-function: "<  November 2026  >" on top, weekday names,
// the days (today on a dark plate). Click the month name to jump back to the current month.
Item {
    id: root
    property date today: new Date()
    property int viewYear: today.getFullYear()
    property int viewMonth: today.getMonth()          // 0-11
    readonly property int cellW: 46
    readonly property int cellH: 30
    readonly property var monthNames: ["January", "February", "March", "April", "May", "June", "July",
                                       "August", "September", "October", "November", "December"]
    readonly property var dayNames: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    width: cellW * 7
    height: nav.height + 10 + names.height + grid.height + 14 + caption.height

    function shift(d) {
        var m = viewMonth + d
        viewYear += Math.floor(m / 12)
        viewMonth = ((m % 12) + 12) % 12
    }
    function toToday() { viewYear = today.getFullYear(); viewMonth = today.getMonth() }

    // the 6 weeks shown: the day number, whether it is in this month, whether it is today
    readonly property var days: {
        var first = new Date(viewYear, viewMonth, 1)
        var start = new Date(viewYear, viewMonth, 1 - first.getDay())
        var out = []
        for (var i = 0; i < 42; i++) {
            var d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i)
            out.push({ n: d.getDate(), inMonth: d.getMonth() === viewMonth,
                       today: d.getFullYear() === today.getFullYear() && d.getMonth() === today.getMonth() && d.getDate() === today.getDate() })
        }
        return out
    }

    Timer { interval: 60000; running: true; repeat: true; onTriggered: root.today = new Date() }

    // ---- month switcher ----
    Item {
        id: nav
        width: parent.width
        height: 30

        component Arrow: Item {
            id: ar
            property string glyph
            signal clicked()
            width: 34; height: 30
            Rectangle { anchors.fill: parent; color: Theme.paperDark }
            Rectangle {
                height: parent.height
                width: arHit.containsMouse ? parent.width : 0
                color: Theme.ink
                Behavior on width { NumberAnimation { duration: Theme.hoverMs; easing.type: Easing.OutCubic } }
            }
            Text {
                anchors.centerIn: parent
                text: ar.glyph
                color: arHit.containsMouse ? Theme.paper : Theme.ink
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 3
                font.bold: true
            }
            MouseArea {
                id: arHit
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: ar.clicked()
            }
        }

        Arrow { x: 0; glyph: "‹"; onClicked: root.shift(-1) }
        Arrow { x: parent.width - width; glyph: "›"; onClicked: root.shift(1) }

        Text {
            anchors.centerIn: parent
            text: root.monthNames[root.viewMonth] + (root.viewYear !== root.today.getFullYear() ? " " + root.viewYear : "")
            color: Theme.ink
            font.family: Theme.font
            font.pixelSize: Theme.fontSize + 2
            font.bold: true
            font.letterSpacing: 2
            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toToday()
            }
        }
    }

    // ---- weekday names ----
    Row {
        id: names
        y: nav.height + 10
        Repeater {
            model: root.dayNames
            Item {
                required property string modelData
                width: root.cellW; height: 26
                Text {
                    anchors.centerIn: parent
                    text: parent.modelData
                    color: Theme.inkSoft
                    font.family: Theme.font
                    font.pixelSize: Theme.smallFontSize + 1
                    font.letterSpacing: 1
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.ink }
            }
        }
    }

    // ---- days ----
    Grid {
        id: grid
        y: names.y + names.height + 2
        columns: 7
        Repeater {
            model: root.days
            Item {
                id: cell
                required property var modelData
                width: root.cellW; height: root.cellH
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    color: cell.modelData.today ? Theme.ink : "transparent"
                }
                Text {
                    anchors.centerIn: parent
                    text: cell.modelData.n
                    color: cell.modelData.today ? Theme.paper : (cell.modelData.inMonth ? Theme.ink : Theme.inkSoft)
                    opacity: cell.modelData.inMonth || cell.modelData.today ? 1 : 0.5
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    font.bold: cell.modelData.today
                }
            }
        }
    }

    Text {
        id: caption
        y: grid.y + grid.height + 14
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: Qt.formatDate(root.today, "dddd d MMMM yyyy").toUpperCase()
        color: Theme.inkSoft
        font.family: Theme.font
        font.pixelSize: Theme.smallFontSize + 1
        font.letterSpacing: 2
    }
}
