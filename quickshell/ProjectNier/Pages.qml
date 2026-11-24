pragma Singleton
import QtQuick

// Menu content: one entry per top tab, each with its sub-functions and descriptions.
QtObject {
    readonly property var list: [
        {
            icon: "\uf11b", label: "Entertainment",
            subtitle: "MEDIA PLAYBACK // RECREATION // LEISURE",
            purpose: "For media, gaming, and leisure.",
            subs: [
                { name: "Browser", desc: "Firefox, Chromium" },
                { name: "Music Player", desc: "Spotify, Strawberry, Elisa" },
                { name: "Gaming", desc: "Steam, Lutris, Heroic" },
                { name: "Game Library", desc: "Installed games" },
                { name: "Switch Tools", desc: "DBI USB install to Nintendo Switch" },
                { name: "Gallery", desc: "Photo collections" },
                { name: "Image Viewer", desc: "Every image opens here" }
            ]
        },
        {
            icon: "\uf140", label: "Missions",
            subtitle: "MISSION MANAGEMENT / OPERATIONAL RECORDS",
            purpose: "For daily activities, productivity, and task tracking.",
            subs: [
                { name: "Mission Board", desc: "To-do list and active tasks" },
                { name: "Calendar", desc: "Events and schedules" },
                { name: "Reminders", desc: "Scheduled notifications" },
                { name: "Notes", desc: "Personal notes and memos" },
                { name: "Screen Recording", desc: "Record the screen to video" },
                { name: "Claude", desc: "Claude (Sonnet) in ~/.config" }
            ]
        },
        {
            icon: "\uf075", label: "Communication",
            subtitle: "COMMUNICATIONS / SIGNAL TRANSMISSION",
            purpose: "For messaging, calls, and external communication.",
            subs: [
                { name: "Messages", desc: "Messaging applications" },
                { name: "Email", desc: "Email client" },
                { name: "Webmail", desc: "Gmail in its own window" },
                { name: "Discord", desc: "Discord" },
                { name: "Quick Share", desc: "File sharing" }
            ]
        },
        {
            icon: "\uf120", label: "Console",
            subtitle: "OPERATOR TERMINAL / SYSTEM UTILITIES",
            purpose: "For command-line operations and technical utilities.",
            subs: [
                { name: "Terminal", desc: "Default terminal emulator" },
                { name: "Root Terminal", desc: "Administrative terminal" },
                { name: "System Monitor", desc: "CPU, GPU, RAM usage" },
                { name: "Process Manager", desc: "Running processes" },
                { name: "Update Manager", desc: "System updates" },
                { name: "Disk Analyzer", desc: "Storage usage" },
                { name: "Hardware Information", desc: "CPU, GPU, motherboard" },
                { name: "Configuration Editor", desc: "Edit system configuration" }
            ]
        },
        {
            icon: "\uf187", label: "Archive",
            subtitle: "DATA ARCHIVE / STORAGE MANAGEMENT",
            purpose: "For files, documents, and stored information.",
            subs: [
                { name: "File Manager", desc: "Browse files" },
                { name: "Home Directory", desc: "Personal directory" },
                { name: "Documents", desc: "Document folder" },
                { name: "Downloads", desc: "Download folder" },
                { name: "Pictures", desc: "Image collection" },
                { name: "Videos", desc: "Video collection" },
                { name: "Music", desc: "Music library" },
                { name: "Screenshots", desc: "Captured screenshots" },
                { name: "Recent Files", desc: "Recently accessed files" },
                { name: "Bookmarks", desc: "Favorite directories" },
                { name: "External Storage", desc: "USB and mounted drives" },
                { name: "Trash", desc: "Deleted files" },
                { name: "Compressed Files", desc: "Archive management" }
            ]
        },
        {
            icon: "\uf0ac", label: "Network",
            subtitle: "BUNKER CONNECTION / NETWORK OPERATIONS",
            purpose: "For internet connectivity and network information.",
            subs: [
                { name: "Wi-Fi", desc: "Wireless connection" },
                { name: "Bluetooth", desc: "Bluetooth devices" },
                { name: "Ethernet", desc: "Wired connection" },
                { name: "VPN", desc: "VPN management" },
                { name: "Network Monitor", desc: "Live network activity" },
                { name: "Connection Status", desc: "Connection information" },
                { name: "IP Information", desc: "Local and public IP" },
                { name: "DNS Settings", desc: "DNS configuration" },
                { name: "Firewall", desc: "Firewall controls" },
                { name: "Nearby Devices", desc: "Local network devices" },
                { name: "Data Usage", desc: "Upload/download statistics" }
            ]
        },
        {
            icon: "\uf013", label: "Configuration",
            subtitle: "UNIT CUSTOMIZATION / INTERFACE SETTINGS",
            purpose: "For customizing the appearance and behavior of the desktop.",
            subs: [
                { name: "Wallpaper", desc: "Change desktop wallpaper" },
                { name: "Theme Selector", desc: "Light/dark themes" },
                { name: "Color Scheme", desc: "YoRHa color palette" },
                { name: "Icon Theme", desc: "Application icons" },
                { name: "Cursor Theme", desc: "Mouse cursor" },
                { name: "Font Manager", desc: "System fonts" },
                { name: "Waybar Settings", desc: "Panel configuration" },
                { name: "Hyprland Settings", desc: "Window manager configuration" },
                { name: "Animations", desc: "Window animations" },
                { name: "Window Rules", desc: "Window behavior" },
                { name: "Keybindings", desc: "Keyboard shortcuts" },
                { name: "Notification Style", desc: "Notification appearance" },
                { name: "Lock Screen", desc: "Lock screen appearance" },
                { name: "Transparency", desc: "Blur and opacity" },
                { name: "Layout Settings", desc: "Gaps, borders, rounding" },
                { name: "Restore Functions", desc: "Bring back removed sub-functions" }
            ]
        },
        {
            icon: "\uf2db", label: "System",
            subtitle: "UNIT MANAGEMENT / HARDWARE CONTROL",
            purpose: "For controlling the physical machine and session.",
            subs: [
                { name: "Display", desc: "Resolution and refresh rate" },
                { name: "Brightness", desc: "Screen brightness" },
                { name: "Audio", desc: "Volume and audio devices" },
                { name: "Microphone", desc: "Input volume and devices" },
                { name: "Power Management", desc: "Battery and power settings" },
                { name: "Idle & Lock", desc: "Minutes until lock screen and sleep" },
                { name: "Battery Status", desc: "Battery percentage and health" },
                { name: "Input Devices", desc: "Keyboard and mouse" },
                { name: "Printers", desc: "Printer management" },
                { name: "USB Devices", desc: "Connected peripherals" },
                { name: "Language", desc: "Keyboard and system language" },
                { name: "Date & Time", desc: "Clock and timezone" },
                { name: "Notifications", desc: "Notification settings" },
                { name: "Session Manager", desc: "Desktop session controls" },
                { name: "Resource Status", desc: "CPU, RAM and GPU status" },
                { name: "Self Check", desc: "Is this screen healthy? Panes, scripts, log, bridge" }
            ]
        },
        {
            icon: "\uf08b", label: "Logout",
            subtitle: "UNIT TERMINATION / SESSION CONTROL",
            purpose: "For ending, locking and restarting the session.",
            subs: [
                { name: "Lock Unit", desc: "Lock screen" },
                { name: "Switch User", desc: "Change user" },
                { name: "Logout", desc: "End current session" },
                { name: "Suspend", desc: "Sleep" },
                { name: "Hibernate", desc: "Hibernate system" },
                { name: "Restart Unit", desc: "Reboot" },
                { name: "Shutdown", desc: "Power off" },
                { name: "Restart Interface", desc: "Restart this screen (Quickshell)" },
                { name: "Emergency Exit", desc: "Terminate the graphical session" }
            ]
        }
    ]
}
