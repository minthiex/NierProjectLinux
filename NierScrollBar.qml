import QtQuick

// Slim scrollbar in the screen's style: a tan rail with a dark thumb. Drag the thumb or click the rail.
Item {
    id: bar
    property var view                      // the ListView / Flickable it scrolls
    readonly property real span: view ? Math.max(0, view.contentHeight - view.height) : 0

    width: 8
    visible: span > 1

    Rectangle { anchors.fill: parent; color: Theme.paperDark }

    Rectangle {
        id: thumb
        width: parent.width
        height: view ? Math.max(36, Math.min(bar.height, bar.height * view.height / Math.max(1, view.contentHeight))) : 36
        y: bar.span > 0 ? Math.max(0, Math.min(bar.height - height, (view.contentY - view.originY) / bar.span * (bar.height - height))) : 0
        color: hit.pressed || hit.containsMouse ? Theme.accent : Theme.ink
        Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
    }

    MouseArea {
        id: hit
        anchors.fill: parent
        anchors.leftMargin: -4                   // a little easier to hit
        hoverEnabled: true
        property real grab: 0

        function moveTo(my) {
            var room = bar.height - thumb.height
            if (room <= 0) return
            var ty = Math.max(0, Math.min(room, my - grab))
            bar.view.contentY = bar.view.originY + ty / room * bar.span
        }
        onPressed: mouse => {
            grab = (mouse.y >= thumb.y && mouse.y <= thumb.y + thumb.height) ? mouse.y - thumb.y : thumb.height / 2
            moveTo(mouse.y)
        }
        onPositionChanged: mouse => { if (pressed) moveTo(mouse.y) }
    }
}
