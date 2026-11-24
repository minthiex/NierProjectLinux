import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects

// System tray: one small tan plate per tray icon. Left click = activate,
// middle click = secondary action, right click = the app's own menu.
Item {
    id: root

    Text {
        id: label
        text: "TRAY"
        color: Theme.inkSoft
        font.family: Theme.font
        font.pixelSize: Theme.smallFontSize
        font.letterSpacing: 3
        font.bold: true
    }

    Row {
        id: row
        y: label.height + 6
        spacing: 8

        Repeater {
            model: SystemTray.items

            Item {
                id: slot
                required property var modelData
                readonly property bool lit: hit.containsMouse

                width: 34
                height: 24

                // tan plate, dark icon box (like the top tabs); hover wipes the plate dark and inverts the box
                Rectangle { anchors.fill: parent; color: Theme.paperDark }
                Rectangle {
                    height: parent.height
                    width: slot.lit ? parent.width : 0
                    color: Theme.ink
                    Behavior on width { NumberAnimation { duration: Theme.hoverMs; easing.type: Easing.OutCubic } }
                }
                Rectangle {
                    id: box
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    color: slot.lit ? Theme.paper : Theme.ink
                    Behavior on color { ColorAnimation { duration: Theme.hoverMs } }

                    // the app's icon, flattened to a single colour so it matches the theme
                    IconImage {
                        id: raw
                        anchors.centerIn: parent
                        implicitSize: 14
                        // the theme can't always draw an item's own icon (KeePassXC's monochrome ones come out as a checkerboard):
                        // try plain files from hicolor first (a missing file reports an error), the theme's icon last
                        property int tries: 0
                        readonly property var names: {
                            var raw = String(slot.modelData.icon)
                            if (raw.indexOf("image://icon/") !== 0) return [raw]        // a pixmap the app drew itself
                            var n = raw.replace(/^image:\/\/icon\//, "")
                            // an app with its own icon folder (Steam): "name?path=/folder" -> the plain file in that folder
                            var q = n.indexOf("?path=")
                            if (q >= 0) {
                                var own = "file://" + n.substring(q + 6) + "/" + n.substring(0, q)
                                return [own + ".png", own + ".svg", slot.modelData.icon]
                            }
                            var plain = n.replace(/-monochrome-(light|dark)/, "")
                            var dir = "file:///usr/share/icons/hicolor/scalable/apps/"
                            return [dir + n + ".svg", dir + plain + ".svg", dir + plain.replace(/-(un)?locked$/, "") + ".svg", slot.modelData.icon]
                        }
                        source: names[Math.min(tries, names.length - 1)]
                        onStatusChanged: if (status === Image.Error && tries < names.length - 1) tries++
                        visible: false
                        layer.enabled: true
                    }
                    MultiEffect {
                        anchors.fill: raw
                        source: raw
                        brightness: 1.0
                        colorization: 1.0
                        colorizationColor: slot.lit ? Theme.ink : Theme.paper
                        Behavior on colorizationColor { ColorAnimation { duration: Theme.hoverMs } }
                    }
                }

                // the app's own menu, drawn in the screen's style (submenus open in place)
                property var curMenu: modelData.menu
                QsMenuOpener { id: opener; menu: slot.curMenu }

                readonly property var menuItems: {
                    var out = []
                    if (slot.curMenu !== slot.modelData.menu)
                        out.push({ text: "Back", keepOpen: true, run: () => { slot.curMenu = slot.modelData.menu } })
                    var kids = opener.children ? opener.children.values : []
                    for (var i = 0; i < kids.length; i++) {
                        var e = kids[i]
                        if (e.isSeparator) { out.push({ separator: true }); continue }
                        out.push({
                            text: String(e.text).replace(/&/g, ""),
                            enabled: e.enabled,
                            checked: e.checkState === Qt.Checked,
                            hasChildren: e.hasChildren,
                            keepOpen: e.hasChildren,
                            run: (function (en) { return function () {
                                if (en.hasChildren) slot.curMenu = en
                                else en.triggered()
                            } })(e)
                        })
                    }
                    return out
                }

                ThemedMenu {
                    id: popup
                    target: slot
                    items: slot.menuItems
                    onVisibleChanged: if (!visible) slot.curMenu = slot.modelData.menu
                }

                MouseArea {
                    id: hit
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        if (mouse.button === Qt.LeftButton && !slot.modelData.onlyMenu) slot.modelData.activate()
                        else if (mouse.button === Qt.MiddleButton) slot.modelData.secondaryActivate()
                        else if (slot.modelData.hasMenu) popup.open()
                    }
                }
            }
        }

        Text {
            visible: SystemTray.items.values.length === 0
            anchors.verticalCenter: parent.verticalCenter
            text: "EMPTY"
            color: Theme.paperDark
            font.family: Theme.font
            font.pixelSize: Theme.smallFontSize + 1
            font.letterSpacing: 2
        }
    }
}
