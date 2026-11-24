import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Idle handling: locks the screen / suspends after N idle minutes (0 = never).
// Settings: ~/.config/projectnier/idle.json  { "lock": minutes, "sleep": minutes }, edited by System → Idle & Lock.
Scope {
    id: root
    signal lockRequested()
    property int lockMin: 10
    property int sleepMin: 30

    FileView {
        path: Quickshell.env("HOME") + "/.config/projectnier/idle.json"
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                var d = JSON.parse(text())
                root.lockMin = Number(d.lock) || 0
                root.sleepMin = Number(d.sleep) || 0
            } catch (e) {}
        }
    }

    IdleMonitor {
        enabled: root.lockMin > 0
        timeout: root.lockMin * 60
        onIsIdleChanged: if (isIdle) root.lockRequested()
    }

    IdleMonitor {
        enabled: root.sleepMin > 0
        timeout: root.sleepMin * 60
        onIsIdleChanged: if (isIdle) {
            root.lockRequested()
            Quickshell.execDetached(["systemctl", "suspend"])
        }
    }
}
