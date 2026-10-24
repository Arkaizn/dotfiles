pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// pywal colors, read live from ~/.cache/wal/colors.json (which `wal` writes);
// QS_COLORS_FILE replaces that path (the login screen reads its copy in
// /var/lib/quickshell-greeter/theme, tests a light scheme).
// A JSON file instead of a generated QML file: a new wallpaper doesn't change
// any QML, so the shell isn't reloaded (open windows stay) and the colors
// just fade over. The values below are only used until the file is read.
Singleton {
    id: root

    property color background: "#1d150c"
    property color foreground: "#c6c4c2"

    property color color0: "#1d150c"
    property color color1: "#C99348"
    property color color2: "#E39B66"
    property color color3: "#6F7489"
    property color color4: "#907781"
    property color color5: "#A98D86"
    property color color6: "#DDAD90"
    property color color7: "#c6c4c2"
    property color color8: "#70655c"
    property color color9: "#C99348"
    property color color10: "#E39B66"
    property color color11: "#6F7489"
    property color color12: "#907781"
    property color color13: "#A98D86"
    property color color14: "#DDAD90"
    property color color15: "#c6c4c2"

    // ── Theme tokens (use these instead of fixed white / pastel colors) ──────
    // light: a light pywal scheme (wal -l) is active, judged by the background
    readonly property bool light: 0.2126 * background.r + 0.7152 * background.g + 0.0722 * background.b > 0.5
    // text and icons; fade(a) = the same with alpha, for dim text, hover tints, borders
    readonly property color ink: light ? "#18171d" : "#ffffff"
    function fade(a) { return Qt.rgba(ink.r, ink.g, ink.b, a) }
    // status colors: pastel on dark, deeper on light so they stay readable
    readonly property color red: light ? "#c4253c" : "#f38ba8"
    readonly property color yellow: light ? "#a8650b" : "#f9e2af"
    readonly property color green: light ? "#2e7d32" : "#a6e3a1"
    readonly property color blue: light ? "#1f5fd1" : "#89b4fa"
    readonly property color teal: light ? "#127a77" : "#94e2d5"
    readonly property color orange: light ? "#c25010" : "#fab387"
    // inner cards on a panel
    readonly property color card: light ? Qt.rgba(1, 1, 1, 0.5) : "#27000000"
    // a dark tint of strength a on dark themes; on light ones a white one (cards, wells)
    function shade(a) { return light ? Qt.rgba(1, 1, 1, Math.min(0.85, a * 1.6)) : Qt.rgba(0, 0, 0, a) }

    function apply(text) {
        let j
        try { j = JSON.parse(text) } catch (e) { return }   // half-written file: wait for the next change
        if (j.special) {
            if (j.special.background) background = j.special.background
            if (j.special.foreground) foreground = j.special.foreground
        }
        const bg = Qt.color(j.special?.background ?? background)
        const lightScheme = lum(bg) > 0.5
        for (let i = 0; i < 16; i++) {
            const c = j.colors?.["color" + i]
            // light schemes keep the wallpaper's pale accents: darken them (same hue)
            // until they read on the light background; colors.json stays as it is
            if (c) root["color" + i] = lightScheme && i !== 0 && i !== 7 && i !== 15 ? readable(Qt.color(c)) : c
        }
    }

    function lum(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
    function readable(c) {
        let l = c.hslLightness
        for (let n = 0; n < 20 && lum(Qt.hsla(c.hslHue, c.hslSaturation, l, 1)) > 0.32; n++) l -= 0.04
        return Qt.hsla(c.hslHue, Math.min(1, c.hslSaturation * 1.15), Math.max(0.12, l), 1)
    }

    FileView {
        id: file
        path: Quickshell.env("QS_COLORS_FILE") || Quickshell.env("HOME") + "/.cache/wal/colors.json"
        watchChanges: true
        blockLoading: true          // colors are there before the first frame
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
    Component.onCompleted: apply(file.text())

    // a new wallpaper fades the whole shell over to its colors
    Behavior on background { ColorAnimation { duration: 600 } }
    Behavior on foreground { ColorAnimation { duration: 600 } }
    Behavior on color0 { ColorAnimation { duration: 600 } }
    Behavior on color1 { ColorAnimation { duration: 600 } }
    Behavior on color2 { ColorAnimation { duration: 600 } }
    Behavior on color3 { ColorAnimation { duration: 600 } }
    Behavior on color4 { ColorAnimation { duration: 600 } }
    Behavior on color5 { ColorAnimation { duration: 600 } }
    Behavior on color6 { ColorAnimation { duration: 600 } }
    Behavior on color7 { ColorAnimation { duration: 600 } }
    Behavior on color8 { ColorAnimation { duration: 600 } }
    Behavior on color9 { ColorAnimation { duration: 600 } }
    Behavior on color10 { ColorAnimation { duration: 600 } }
    Behavior on color11 { ColorAnimation { duration: 600 } }
    Behavior on color12 { ColorAnimation { duration: 600 } }
    Behavior on color13 { ColorAnimation { duration: 600 } }
    Behavior on color14 { ColorAnimation { duration: 600 } }
    Behavior on color15 { ColorAnimation { duration: 600 } }
}
