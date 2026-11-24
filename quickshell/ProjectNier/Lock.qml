import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import QtQuick

// Session lock (ext-session-lock): one LockView per screen, passphrase checked through PAM.
//   qs -c ProjectNier ipc call lock now      locks the screen
// With PROJECTNIER_LOCK=1 in the environment the shell starts locked (login screen, replaces hyprlock autostart).
Scope {
    id: root
    property string status: "ready"     // ready | verifying | failed | granted
    readonly property string user: Quickshell.env("USER") || "user"
    property string host: ""

    function lockNow() {
        if (session.locked) return
        status = "ready"
        session.locked = true
    }

    // PROJECTNIER_LOCK stays in the environment for the life of the process: honour it only on the very first load,
    // not on every live reload. A reload while locked locks again at once (the old lock object is gone).
    PersistentProperties {
        id: persist
        reloadableId: "projectnierLock"
        property bool booted: false
        property bool wasLocked: false
        onLoaded: {
            var boot = !booted && Quickshell.env("PROJECTNIER_LOCK") === "1"
            booted = true
            if (boot || wasLocked) root.lockNow()
        }
    }

    IpcHandler {
        target: "lock"
        function now(): void { root.lockNow() }
        function isLocked(): bool { return session.locked }
    }

    Process {
        running: true
        command: ["hostname"]
        stdout: StdioCollector { onStreamFinished: root.host = text.trim() }
    }

    property string pending: ""
    PamContext {
        id: pam
        config: "login"
        onPamMessage: {
            if (responseRequired) respond(root.pending)
        }
        onCompleted: result => {
            root.pending = ""
            root.status = result === PamResult.Success ? "granted" : "failed"
        }
    }

    WlSessionLock {
        id: session
        locked: false
        onLockedChanged: persist.wasLocked = locked

        WlSessionLockSurface {
            LockView {
                anchors.fill: parent
                status: root.status
                user: root.user
                host: root.host
                onSubmitted: secret => {
                    if (root.status === "verifying" || root.status === "granted") return
                    root.pending = secret
                    root.status = "verifying"
                    pam.start()
                }
                onTouched: if (root.status === "failed") root.status = "ready"
                onRestartRequested: Quickshell.execDetached(["systemctl", "reboot"])
                onShutdownRequested: Quickshell.execDetached(["systemctl", "poweroff"])
                onFinished: session.locked = false
            }
        }
    }
}
