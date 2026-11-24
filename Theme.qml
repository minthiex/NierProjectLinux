pragma Singleton
import QtQuick

// NieR: Automata inspired: warm paper beige, dark olive-brown ink, thin lines.
QtObject {
    // palette
    readonly property color paper: "#cdc8b0"
    readonly property color paperDark: "#bab5a1"
    readonly property color ink: "#454138"
    readonly property color inkSoft: "#78735f"
    readonly property color accent: "#b5482f"

    // terminal ANSI tones (muted, to sit on paper)
    readonly property color termWhite: "#5c584b"   // "white" on a light ground has to be dark
    readonly property color termRed: "#7a5a44"
    readonly property color termGreen: "#5f6b3c"
    readonly property color termYellow: "#8a6d2a"
    readonly property color termBlue: "#4a5d6b"
    readonly property color termMagenta: "#6b4f63"
    readonly property color termCyan: "#3f6b66"

    // font
    readonly property string font: "JetBrainsMono Nerd Font"
    readonly property int fontSize: 13
    readonly property int smallFontSize: 11
    readonly property int dateSize: 14
    readonly property int titleSize: 30

    // top bar
    readonly property int clockSize: 22
    readonly property int menuTop: 100
    readonly property int menuH: 28
    readonly property int menuGap: 18
    readonly property int ruleGap: 14
    readonly property int menuPad: 12
    readonly property int hoverMs: 160
    readonly property int iconBox: 20
    readonly property int tabInset: 40
    readonly property int bandH: 16

    // screen frame
    readonly property int frameMargin: 20
    readonly property int frameWidth: 1
    readonly property int markSize: 6
    readonly property int pad: 14
}
