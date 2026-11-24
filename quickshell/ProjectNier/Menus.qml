pragma Singleton
import QtQuick

// Keeps track of the one context menu that may be open, so it can be dismissed from anywhere.
QtObject {
    property var current: null

    function show(menu) {
        if (current && current !== menu) current.visible = false
        current = menu
        menu.visible = true
    }

    function closeAll() {
        if (current) current.visible = false
        current = null
    }
}
