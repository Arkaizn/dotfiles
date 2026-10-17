pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// pywal colors, read live from ~/.cache/wal/colors.json (which `wal` writes).
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

    function apply(text) {
        let j
        try { j = JSON.parse(text) } catch (e) { return }   // half-written file: wait for the next change
        if (j.special) {
            if (j.special.background) background = j.special.background
            if (j.special.foreground) foreground = j.special.foreground
        }
        for (let i = 0; i < 16; i++) {
            const c = j.colors?.["color" + i]
            if (c) root["color" + i] = c
        }
    }

    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.cache/wal/colors.json"
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
