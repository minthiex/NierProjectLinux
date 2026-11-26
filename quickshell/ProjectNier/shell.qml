//@ pragma UseQApplication
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

ShellRoot {
    Notifications {}
    VolumePopup {}
    Lock { id: lock }
    QuickSettings { id: quick; onLockRequested: lock.lockNow() }
    Idle { onLockRequested: lock.lockNow() }
    // Configuration -> Startup Apps: start the switched-on apps of ~/.config/autostart, once per Hyprland session
    Process { running: true; command: ["python3", Quickshell.shellPath("scripts/startup.py"), "run"] }
    // Archive → Clipboard: one detached `wl-paste --watch cliphist store` (a child of the shell would race the live
    // reload: the new config starts before the old one's children are killed); checked again every 5 minutes
    Timer {
        interval: 300000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: Quickshell.execDetached(["sh", "-c", "command -v cliphist >/dev/null || exit 0; " +
            "pgrep -x -f 'wl-paste --watch cliphist store' >/dev/null || exec wl-paste --watch cliphist store"])
    }

    // System → Backups: a copy of the settings outside the dotfiles repo once a day (scripts/backup.sh)
    Timer {
        interval: 3600000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: Quickshell.execDetached(["sh", Quickshell.shellPath("scripts/backup.sh"), "auto"])
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "projectnier-screen"
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"

            // On demand: a click on the bare screen (outside every window) takes keyboard focus away from the window.
            // A click on a window is reported by a Hyprland bind (qs ipc call focus click): the screen then lets go
            // of the keyboard for a moment and Hyprland gives it to the window (a click alone does not, the window
            // is still "active" as far as Hyprland is concerned).
            property bool letGo: false
            WlrLayershell.keyboardFocus: win.letGo ? WlrKeyboardFocus.None : WlrKeyboardFocus.OnDemand
            Timer { id: giveBack; interval: 80; onTriggered: win.letGo = false }
            HoverHandler { id: over }
            IpcHandler {
                target: "focus"
                function click(): void {
                    if (!over.hovered) { win.letGo = true; giveBack.restart() }   // pointer is on a window, not the bare screen
                }
            }

            NierScreen {
                id: screenView
                anchors.fill: parent
                onReleaseKeys: { win.letGo = true; giveBack.restart() }
                onQuickRequested: quick.toggle()
            }
        }
    }
}
