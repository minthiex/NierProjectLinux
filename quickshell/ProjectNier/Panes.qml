pragma Singleton
import Quickshell
import QtQuick

// What every sub-function shows on the right of the screen, keyed "<Tab>/<Name>".
//  script / args : scripts/<script> <args...>, prints  key <TAB> value [<TAB> percent [<TAB> click]]
//  interval      : refresh every N ms (0 = only when opened or refreshed by hand)
//  delay         : ms to wait after an action before refreshing (default 700; 0 = refresh as soon as the command finishes)
//  rows          : static [key, value] rows
//  input         : { placeholder, cmd, term? }   a text field; Enter runs cmd + [text]
//  actions       : buttons { label, cmd, term?, quiet?, confirm? }
//                  term  = open in the small themed terminal window
//                  quiet = run silently, then refresh the panel
//                  confirm = needs a second click
QtObject {
    readonly property string home: Quickshell.env("HOME")
    readonly property string dataDir: home + "/.local/share/ProjectNier"
    // the Hyprland settings live in projectnier.lua (hyprland.lua only loads it; local.lua is this machine's extras)
    readonly property string hyprConf: home + "/.config/hypr/projectnier.lua"

    function script(name) { return Quickshell.shellPath("scripts/" + name) }
    function sh(name, args) { return ["sh", script(name)].concat(args) }

    function termOpts() {
        var o = []
        var opts = [
            ["background", Theme.paper], ["foreground", Theme.ink],
            ["cursor", Theme.ink], ["cursor_text_color", Theme.paper],
            ["selection_background", Theme.ink], ["selection_foreground", Theme.paper],
            ["font_family", Theme.font], ["font_size", "11"],
            ["window_padding_width", "10"], ["confirm_os_window_close", "0"],
            ["background_opacity", "1"], ["hide_window_decorations", "yes"],
            ["color0", Theme.ink], ["color8", Theme.inkSoft],
            ["color1", Theme.termRed], ["color9", Theme.termRed],
            ["color2", Theme.termGreen], ["color10", Theme.termGreen],
            ["color3", Theme.termYellow], ["color11", Theme.termYellow],
            ["color4", Theme.termBlue], ["color12", Theme.termBlue],
            ["color5", Theme.termMagenta], ["color13", Theme.termMagenta],
            ["color6", Theme.termCyan], ["color14", Theme.termCyan],
            ["color7", Theme.termWhite], ["color15", Theme.ink],
            ["tab_bar_edge", "top"], ["tab_bar_style", "separator"], ["tab_separator", " | "],
            ["tab_bar_background", Theme.paper],
            ["active_tab_background", Theme.ink], ["active_tab_foreground", Theme.paper],
            ["inactive_tab_background", Theme.paperDark], ["inactive_tab_foreground", Theme.ink]
        ]
        for (var i = 0; i < opts.length; i++) o = o.concat(["-o", opts[i][0] + "=" + String(opts[i][1])])
        return o
    }

    // command that puts `args` into the content window of one sub-function (its own kitty window; a new tab if it is already open)
    function openIn(slug, title, args) {
        var opts = termOpts()
        return ["bash", script("term.sh"), slug, title, String(opts.length)].concat(opts).concat(args)
    }

    // plain themed kitty command (used by the timers' pop-up, which is its own window)
    function term(args) {
        var cmd = ["kitty", "--class", "projectnier-term"].concat(termOpts())
        return args.length > 0 ? cmd.concat(["-e"]).concat(args) : cmd
    }

    // btop in the shell's colours
    function btop() {
        return sh("btop.sh", [Theme.paper, Theme.paperDark, Theme.ink, Theme.inkSoft, Theme.accent,
                              Theme.termRed, Theme.termGreen, Theme.termYellow, Theme.termBlue, Theme.termCyan])
    }
    function edit(path) { return ["micro", path] }
    function timer(kind, secs, msg) { return sh("timer.sh", [kind, String(secs), msg]).concat(termOpts()) }
    function dolphin(path) { return ["dolphin", path] }
    function info(topic, arg) { return arg === undefined ? [topic] : [topic, arg] }
    function dirSpec(path) {
        return { script: "info.sh", args: ["dir", path], interval: 8000 }
    }
    function apps(list) { return ["apps"].concat(list) }
    function confirmAct(label, cmd) { return { label: label, cmd: cmd, confirm: true } }

    readonly property var specs: ({
        // ========================================================= ENTERTAINMENT
        "Entertainment/Browser": {
            script: "info.sh", args: apps(["Firefox|firefox|gui", "Chromium|chromium|gui"]), interval: 0,
            input: { placeholder: "Web address or search, then Enter", cmd: ["firefox"], launch: true },
            actions: [
                { label: "Open Firefox", cmd: ["firefox"], launch: true },
                { label: "Open Chromium", cmd: sh("chromium.sh", []), launch: true }
            ]
        },
        "Entertainment/Music Player": {
            script: "info.sh", args: ["nowplaying"], interval: 2000,
            actions: [
                { label: "Open Drift Music Player", cmd: ["drift"], term: true },
                { label: "Play / Pause", cmd: ["playerctl", "play-pause"], quiet: true },
                { label: "Next Track", cmd: ["playerctl", "next"], quiet: true },
                { label: "Previous Track", cmd: ["playerctl", "previous"], quiet: true }
            ]
        },
        "Entertainment/Gaming": {
            script: "info.sh", args: apps(["Steam|steam|gui", "Lutris|lutris|gui", "Heroic|heroic|gui"]), interval: 0,
            actions: [
                { label: "Open Steam", cmd: ["steam"] },
                { label: "Open Lutris", cmd: ["lutris"] },
                { label: "Open Heroic", cmd: ["heroic"] }
            ]
        },
        "Entertainment/Game Library": {
            script: "info.sh", args: ["gamelib"], interval: 10000
        },
        "Entertainment/Switch Tools": {
            script: "info.sh", args: apps(["DBI Backend|dbibackend|cli"]), interval: 3000,
            actions: [{ label: "Start DBI Backend", cmd: ["dbibackend", home + "/Documents/Switch Games"], term: true }]
        },
        "Entertainment/Gallery": dirSpec(home + "/Pictures"),
        "Entertainment/Image Viewer": {
            script: "info.sh", args: apps(["Gwenview|gwenview|gui"]), interval: 0,
            actions: [{ label: "Open Gwenview", cmd: ["gwenview"], launch: true }]
        },

        // ============================================================== MISSIONS
        "Missions/Mission Board": { delay: 0,
            script: "info.sh", args: ["todo"], interval: 3000,
            input: { placeholder: "New task, then Enter", cmd: sh("todo.sh", ["add"]) },
            actions: [
                { label: "Clear Completed", cmd: sh("todo.sh", ["clear"]), quiet: true },
                { label: "Edit Task File", cmd: edit(dataDir + "/todo.txt"), term: true }
            ]
        },
        "Missions/Calendar": { delay: 0,
            calendar: true,
            actions: [{ label: "Show Three Months", cmd: ["sh", "-c", "cal -3; echo; printf 'press Enter'; read -r _"], term: true }]
        },
        "Missions/Reminders": { delay: 0,
            script: "info.sh", args: ["reminders"], interval: 5000,
            actions: [
                { label: "Remind Me in 10 Minutes", cmd: timer("remind", 600, "Reminder"), quiet: true },
                { label: "Remind Me in 30 Minutes", cmd: timer("remind", 1800, "Reminder"), quiet: true },
                { label: "Remind Me in 1 Hour", cmd: timer("remind", 3600, "Reminder"), quiet: true }
            ]
        },
        "Missions/Notes": { delay: 0,
            script: "info.sh", args: ["notes"], interval: 8000,
            actions: [
                { label: "New Note", cmd: ["sh", "-c", "micro \"$HOME/Notes/note-$(date +%Y%m%d-%H%M).md\""], term: true }
            ]
        },

        "Missions/Screen Recording": { delay: 300,
            script: "record.sh", args: ["status"], interval: 1000,
            actions: [
                { label: "Start / Stop Recording", cmd: sh("record.sh", ["toggle"]), quiet: true },
                { label: "Record Selected Area", cmd: sh("record.sh", ["area"]), quiet: true },
                { label: "Open Recordings Folder", cmd: dolphin(home + "/Videos/Recordings") }
            ]
        },

        "Missions/Claude": { delay: 0,
            rows: [["ASSISTANT", "Claude Code"], ["MODEL", "Sonnet"], ["FOLDER", "~/.config"]],
            actions: [
                { label: "Open Claude in ~/.config", cmd: ["sh", "-c", "cd \"$HOME/.config\" && exec claude --model sonnet"], term: true }
            ]
        },

        // ======================================================== COMMUNICATION
        "Communication/Messages": {
            rows: [["APPLICATION", "Facebook Messenger"], ["CLIENT", "built in, in the content window"]],
            actions: [{ label: "Open Messenger", app: "messenger" }]
        },
        "Communication/Email": {
            rows: [["APPLICATION", "Google Mail"], ["CLIENT", "built in, in the content window"]],
            actions: [{ label: "Open Email", app: "email" }]
        },
        "Communication/Webmail": {
            script: "info.sh", args: apps(["Gmail|chromium|gui"]), interval: 0,
            actions: [{ label: "Open Gmail", cmd: sh("gmail.sh", []), launch: true }]
        },
        "Communication/Discord": {
            rows: [["APPLICATION", "Discord"], ["PROCESS", "starts when opened"]],
            actions: [{ label: "Open Discord", cmd: ["discord"] }]
        },
        "Communication/Quick Share": {
            script: "info.sh", args: ["share"], interval: 8000,
            actions: [
                { label: "Open Share Folder", cmd: dolphin(home + "/Public") },
                { label: "Serve Folder on the Network", cmd: ["sh", "-c", "cd \"$HOME/Public\" && python3 -m http.server 8000"], term: true }
            ]
        },

        // ================================================================ CONSOLE
        "Console/Terminal": {
            rows: [["EMULATOR", "kitty"], ["SHELL", "fish"]],
            actions: [{ label: "Open Terminal", cmd: [], term: true }]
        },
        "Console/Root Terminal": {
            rows: [["EMULATOR", "kitty"], ["SESSION", "sudo -i"], ["NOTE", "asks for your password in the terminal"]],
            actions: [{ label: "Open Root Terminal", cmd: ["sudo", "-i"], term: true }]
        },
        "Console/System Monitor":       { script: "monitor.sh",   interval: 2000 },
        "Console/Process Manager":      { script: "processes.sh", interval: 2000 },
        "Console/Update Manager": {
            script: "updates.sh", interval: 0,
            actions: [{ label: "Run System Update", cmd: ["sudo", "pacman", "-Syu"], term: true }]
        },
        "Console/Disk Analyzer":        { script: "disks.sh",     interval: 15000 },
        "Console/Hardware Information": { script: "hardware.sh",  interval: 0 },
        "Console/Configuration Editor": {
            rows: [["EDITOR", "micro (in the small terminal)"]],
            actions: [
                { label: "Hyprland (projectnier.lua)", cmd: edit(hyprConf), term: true },
                { label: "Shell (shell.qml)",       cmd: edit(home + "/.config/quickshell/ProjectNier/shell.qml"), term: true },
                { label: "Theme (Theme.qml)",       cmd: edit(home + "/.config/quickshell/ProjectNier/Theme.qml"), term: true },
                { label: "Fish (config.fish)",      cmd: edit(home + "/.config/fish/config.fish"), term: true }
            ]
        },

        // =============================================================== ARCHIVE
        "Archive/File Manager": {
            script: "info.sh", args: ["places"], interval: 15000,
            actions: [{ label: "Open File Manager", cmd: ["dolphin"] }]
        },
        "Archive/Home Directory": dirSpec(home),
        "Archive/Documents": dirSpec(home + "/Documents"),
        "Archive/Downloads": dirSpec(home + "/Downloads"),
        "Archive/Pictures": dirSpec(home + "/Pictures"),
        "Archive/Videos": dirSpec(home + "/Videos"),
        "Archive/Music": dirSpec(home + "/Music"),
        "Archive/Screenshots": dirSpec(home + "/Pictures/Screenshots"),
        "Archive/Recent Files": { script: "info.sh", args: ["recent"], interval: 15000 },
        "Archive/Bookmarks": { script: "info.sh", args: ["places"], interval: 15000 },
        "Archive/External Storage": {
            script: "info.sh", args: ["external"], interval: 10000
        },
        "Archive/Trash": {
            script: "info.sh", args: ["trash"], interval: 8000,
            actions: [
                { label: "Empty Trash", cmd: ["sh", "-c", "rm -rf \"$HOME\"/.local/share/Trash/files/* \"$HOME\"/.local/share/Trash/info/*"], quiet: true, confirm: true }
            ]
        },
        "Archive/Compressed Files": {
            script: "info.sh", args: ["compressed"], interval: 15000
        },

        // =============================================================== NETWORK
        "Network/Wi-Fi": {
            script: "info.sh", args: ["wifi"], interval: 10000,
            actions: [
                { label: "Toggle Wi-Fi Radio", cmd: ["sh", "-c", "nmcli radio wifi | grep -q enabled && nmcli radio wifi off || nmcli radio wifi on"], quiet: true },
                { label: "Rescan Networks", cmd: ["nmcli", "device", "wifi", "rescan"], quiet: true, delay: 6000 }     // the scan runs on after the command returns
            ]
        },
        "Network/Bluetooth": {
            script: "info.sh", args: ["bluetooth"], interval: 6000,
            actions: [
                { label: "Open Bluetooth Manager", app: "bluetooth" },     // pair, connect, trust, forget (Bluetooth.qml)
                { label: "Toggle Bluetooth Power", cmd: ["sh", "-c", "bluetoothctl show | grep -q 'Powered: yes' && bluetoothctl power off || bluetoothctl power on"], quiet: true },
                { label: "Open Bluetooth Console", cmd: ["bluetoothctl"], term: true }
            ]
        },
        "Network/Ethernet": { script: "info.sh", args: ["ethernet"], interval: 6000 },
        "Network/VPN": {
            script: "info.sh", args: ["vpn"], interval: 8000,
            actions: [{ label: "List All Connections", cmd: ["sh", "-c", "nmcli connection show; echo; printf 'press Enter'; read -r _"], term: true }]
        },
        "Network/Network Monitor": {
            script: "info.sh", args: ["netmon"], interval: 2000,
            actions: [{ label: "Open System Monitor (btop)", cmd: btop(), term: true }]
        },
        "Network/Connection Status": { script: "info.sh", args: ["connstatus"], interval: 6000 },
        "Network/IP Information": { script: "info.sh", args: ["ip"], interval: 30000 },
        "Network/DNS Settings": {
            script: "info.sh", args: ["dns"], interval: 15000,
            actions: [{ label: "Show Full DNS Status", cmd: ["sh", "-c", "resolvectl status | less"], term: true }]
        },
        "Network/Firewall": {
            script: "info.sh", args: ["firewall"], interval: 10000
        },
        "Network/Nearby Devices": { script: "info.sh", args: ["nearby"], interval: 10000 },
        "Network/Data Usage": { script: "info.sh", args: ["datausage"], interval: 6000 },

        // ========================================================== CONFIGURATION
        "Configuration/Wallpaper": {
            script: "info.sh", args: ["wallpaper"], interval: 15000,
            actions: [{ label: "Open Wallpaper Folder", cmd: dolphin(home + "/Pictures/Wallpaper") }]
        },
        "Configuration/Theme Selector": {
            script: "info.sh", args: ["theme"], interval: 5000,
            actions: [
                { label: "Prefer Dark", cmd: ["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", "prefer-dark"], quiet: true },
                { label: "Prefer Light", cmd: ["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", "prefer-light"], quiet: true },
                { label: "System Default", cmd: ["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", "default"], quiet: true }
            ]
        },
        "Configuration/Color Scheme": {
            rows: [
                ["PAPER", String(Theme.paper)], ["PAPER DARK", String(Theme.paperDark)],
                ["INK", String(Theme.ink)], ["INK SOFT", String(Theme.inkSoft)],
                ["ACCENT", String(Theme.accent)], ["FONT", Theme.font]
            ],
            actions: [{ label: "Edit Theme.qml", cmd: edit(home + "/.config/quickshell/ProjectNier/Theme.qml"), term: true }]
        },
        "Configuration/Icon Theme": { script: "info.sh", args: ["icon"], interval: 15000 },
        "Configuration/Cursor Theme": { script: "info.sh", args: ["cursor"], interval: 15000 },
        "Configuration/Font Manager": {
            script: "info.sh", args: ["fonts"], interval: 15000,
            actions: [{ label: "List Installed Fonts", cmd: ["sh", "-c", "fc-list : family | sort -u | less"], term: true }]
        },
        "Configuration/Waybar Settings": {
            script: "info.sh", args: ["shellcfg"], interval: 10000,
            actions: [
                { label: "Edit shell.qml", cmd: edit(home + "/.config/quickshell/ProjectNier/shell.qml"), term: true },
                { label: "Open Config Folder", cmd: dolphin(home + "/.config/quickshell/ProjectNier") }
            ]
        },
        "Configuration/Hyprland Settings": {
            script: "info.sh", args: ["hyprland"], interval: 10000,
            actions: [
                { label: "Edit projectnier.lua", cmd: edit(hyprConf), term: true },
                { label: "Edit local.lua (this machine)", cmd: edit(home + "/.config/hypr/local.lua"), term: true },
                { label: "Check Config", cmd: ["sh", "-c", "Hyprland --verify-config -c \"$HOME/.config/hypr/hyprland.lua\"; printf '\\nPress Enter to close. '; read x"], term: true },
                { label: "Reload Hyprland Config", cmd: ["hyprctl", "reload"], quiet: true }
            ]
        },
        "Configuration/Animations": {
            script: "info.sh", args: ["animations"], interval: 10000,
            actions: [{ label: "Edit projectnier.lua", cmd: edit(hyprConf), term: true }]
        },
        "Configuration/Window Rules": {
            script: "info.sh", args: ["winrules"], interval: 15000,
            actions: [{ label: "Edit projectnier.lua", cmd: edit(hyprConf), term: true }]
        },
        "Configuration/Keybindings": {
            script: "info.sh", args: ["binds"], interval: 15000,
            actions: [{ label: "Edit projectnier.lua", cmd: edit(hyprConf), term: true }]
        },
        "Configuration/Notification Style": { script: "info.sh", args: ["notifstyle"], interval: 10000 },
        "Configuration/Lock Screen": {
            script: "info.sh", args: ["lockscreen"], interval: 10000,
            actions: [
                { label: "Lock Now", cmd: ["qs", "-c", "ProjectNier", "ipc", "call", "lock", "now"], quiet: true },
                { label: "Edit LockView.qml", cmd: edit(home + "/.config/quickshell/ProjectNier/LockView.qml"), term: true }]
        },
        "Configuration/Transparency": {
            script: "info.sh", args: ["transparency"], interval: 10000,
            actions: [{ label: "Edit projectnier.lua", cmd: edit(hyprConf), term: true }]
        },
        "Configuration/Layout Settings": {
            script: "info.sh", args: ["layout"], interval: 10000,
            actions: [{ label: "Edit projectnier.lua", cmd: edit(hyprConf), term: true }]
        },
        "Configuration/Startup Apps": {
            script: "info.sh", args: ["startup"], interval: 0, delay: 0,
            input: { placeholder: "Add an app (name or command) and press Enter", cmd: ["python3", script("startup.py"), "add"] },
            actions: [
                { label: "Start Them Now", cmd: ["python3", script("startup.py"), "run", "--now"], quiet: true },
                { label: "Open Startup Folder", cmd: dolphin(home + "/.config/autostart") },
                confirmAct("Remove Switched-Off Apps", ["python3", script("startup.py"), "prune"])
            ]
        },

        // ================================================================ SYSTEM
        "System/Display": { script: "info.sh", args: ["display"], interval: 10000 },
        "System/Brightness": { script: "info.sh", args: ["brightness"], interval: 6000 },
        "System/Audio": {
            script: "info.sh", args: ["audio"], interval: 3000,
            actions: [
                { label: "Volume Up", cmd: ["wpctl", "set-volume", "-l", "1", "@DEFAULT_AUDIO_SINK@", "5%+"], quiet: true },
                { label: "Volume Down", cmd: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%-"], quiet: true },
                { label: "Toggle Mute", cmd: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"], quiet: true },
                { label: "Open Mixer", cmd: ["pavucontrol"] }
            ]
        },
        "System/Microphone": {
            script: "info.sh", args: ["mic"], interval: 3000,
            actions: [
                { label: "Input Up", cmd: ["pactl", "set-source-volume", "@DEFAULT_SOURCE@", "+5%"], quiet: true },
                { label: "Input Down", cmd: ["pactl", "set-source-volume", "@DEFAULT_SOURCE@", "-5%"], quiet: true },
                { label: "Toggle Mute", cmd: ["pactl", "set-source-mute", "@DEFAULT_SOURCE@", "toggle"], quiet: true }
            ]
        },
        "System/Power Management": {
            script: "info.sh", args: ["power"], interval: 5000,
            actions: [
                { label: "Balanced Profile", cmd: ["powerprofilesctl", "set", "balanced"], quiet: true },
                { label: "Power Saver Profile", cmd: ["powerprofilesctl", "set", "power-saver"], quiet: true }
            ]
        },
        "System/Idle & Lock": {
            script: "info.sh", args: ["idle"], interval: 3000,
            actions: [
                { label: "Lock +1 min", cmd: sh("idle.sh", ["lock", "+1"]), quiet: true, delay: 0 },
                { label: "Lock -1 min", cmd: sh("idle.sh", ["lock", "-1"]), quiet: true, delay: 0 },
                { label: "Lock +5 min", cmd: sh("idle.sh", ["lock", "+5"]), quiet: true, delay: 0 },
                { label: "Lock -5 min", cmd: sh("idle.sh", ["lock", "-5"]), quiet: true, delay: 0 },
                { label: "Lock: Never", cmd: sh("idle.sh", ["lock", "off"]), quiet: true, delay: 0 },
                { label: "Lock: Default (10)", cmd: sh("idle.sh", ["lock", "on"]), quiet: true, delay: 0 },
                { label: "Sleep +5 min", cmd: sh("idle.sh", ["sleep", "+5"]), quiet: true, delay: 0 },
                { label: "Sleep -5 min", cmd: sh("idle.sh", ["sleep", "-5"]), quiet: true, delay: 0 },
                { label: "Sleep: Never", cmd: sh("idle.sh", ["sleep", "off"]), quiet: true, delay: 0 },
                { label: "Sleep: Default (30)", cmd: sh("idle.sh", ["sleep", "on"]), quiet: true, delay: 0 }
            ]
        },
        "System/Battery Status": { script: "info.sh", args: ["battery"], interval: 10000 },
        "System/Input Devices": { script: "info.sh", args: ["input"], interval: 10000 },
        "System/Printers": { script: "info.sh", args: ["printers"], interval: 15000 },
        "System/USB Devices": { script: "info.sh", args: ["usb"], interval: 6000 },
        "System/Language": { script: "info.sh", args: ["language"], interval: 0 },
        "System/Date & Time": { script: "info.sh", args: ["datetime"], interval: 5000 },
        "System/Notifications": { script: "info.sh", args: ["notifications"], interval: 5000 },
        "System/Session Manager": { script: "info.sh", args: ["session"], interval: 8000 },
        "System/Resource Status": { script: "monitor.sh", interval: 2000 },
        // runs every pane script once (takes ~12 s): only when opened or refreshed by hand
        "System/Self Check": { script: "selfcheck.sh", interval: 0,
            // the standard fixes for what the health light (top right) watches; the check runs again when it is done
            actions: [{ label: "Repair", cmd: sh("repair.sh"), quiet: true, delay: 0, confirm: true }] },

        // ================================================================ LOGOUT
        "Logout/Lock Unit": {
            rows: [["LOCKER", "ProjectNier (Lock.qml, PAM login)"], ["EFFECT", "locks the screen, session keeps running"]],
            actions: [{ label: "Lock Now", cmd: ["qs", "-c", "ProjectNier", "ipc", "call", "lock", "now"], quiet: true }]
        },
        "Logout/Switch User": {
            rows: [["LOGIN SCREEN", "sddm"], ["EFFECT", "ends this session and returns to the login screen"]],
            actions: [confirmAct("Return to Login Screen", ["sh", "-c", "loginctl terminate-session \"$XDG_SESSION_ID\""])]
        },
        "Logout/Logout": {
            rows: [["EFFECT", "closes your applications and ends the session"]],
            actions: [confirmAct("Log Out", ["sh", "-c", "command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"])]
        },
        "Logout/Suspend": {
            rows: [["EFFECT", "sleeps; wake with a key or the mouse"]],
            actions: [confirmAct("Suspend", ["systemctl", "suspend"])]
        },
        "Logout/Hibernate": {
            rows: [["EFFECT", "writes memory to swap and powers off"], ["NOTE", "needs a swap area large enough"]],
            actions: [confirmAct("Hibernate", ["systemctl", "hibernate"])]
        },
        "Logout/Restart Unit": {
            rows: [["EFFECT", "reboots the computer"]],
            actions: [confirmAct("Restart", ["systemctl", "reboot"])]
        },
        "Logout/Shutdown": {
            rows: [["EFFECT", "powers the computer off"]],
            actions: [confirmAct("Shut Down", ["systemctl", "poweroff"])]
        },
        "Logout/Restart Interface": {
            rows: [["EFFECT", "restarts this screen (Quickshell); applications keep running"]],
            actions: [confirmAct("Restart Interface", ["sh", "-c", "sleep 0.4; qs kill -c ProjectNier; sleep 0.6; pkill -x quickshell; env -u PROJECTNIER_LOCK qs -c ProjectNier -d"])]
        },
        "Logout/Emergency Exit": {
            rows: [["EFFECT", "ends the graphical session immediately"], ["WARNING", "unsaved work in open windows is lost"]],
            actions: [confirmAct("Terminate Session Now", ["sh", "-c", "loginctl terminate-session \"$XDG_SESSION_ID\""])]
        }
    })
}
