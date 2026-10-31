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

    // ── Roles (DESIGN.md → Colour) ───────────────────────────────────────────
    // Modules take these instead of picking an alpha or a hex value: the same
    // job then looks the same everywhere, and light schemes keep working.
    // any colour at alpha a (instead of Qt.rgba(Colors.x.r, Colors.x.g, Colors.x.b, a))
    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    // the highlight colour of the shell: selection, links, active toggles
    readonly property color accent: color6
    readonly property color onAccent: lum(color6) > 0.5 ? "#18171d" : "#ffffff"   // text on an accent fill
    readonly property color focus: color6          // keyboard focus ring
    readonly property color danger: red            // destructive actions, errors
    readonly property color warning: yellow
    readonly property color success: green
    readonly property color info: blue
    // a status colour as a quiet background (banners, error rows)
    function tint(c, a) { return alpha(c, a ?? 0.14) }
    // text
    readonly property color textPrimary: ink
    readonly property color textStrong: fade(0.87)
    readonly property color textSecondary: fade(0.7)
    readonly property color textMuted: fade(0.55)
    readonly property color textFaint: fade(0.42)
    readonly property color textDisabled: fade(0.3)
    // fills on a panel / card
    readonly property color fillSubtle: fade(0.05)
    readonly property color fillHover: fade(0.08)
    readonly property color fillPressed: fade(0.12)   // also "selected"
    readonly property color fillStrong: fade(0.18)
    // lines
    readonly property color divider: fade(0.06)
    readonly property color lineSubtle: fade(0.10)
    readonly property color lineControl: fade(0.18)
    readonly property color lineHover: fade(0.28)
    // surfaces
    readonly property color surfacePopover: alpha(background, 0.97)   // menus, dropdowns, tooltips
    readonly property color surfaceCardRaised: shade(0.27)            // the darker dashboard / keybinds card
    readonly property color surfaceWell: shade(0.23)                  // inside of a text field
    readonly property color scrim: shade(0.4)                         // behind a modal
    // fixed greys that don't follow the scheme: l = 0 black … 1 white
    function neutral(l, a) { return Qt.rgba(l, l, l, a ?? 1) }
    // what sits on the wallpaper (lockscreen, greeter, desktop): always white,
    // whatever the scheme — the wallpaper is the background, not `background`
    function onWallpaper(a) { return neutral(1, a) }
    // black at alpha a on any scheme: scrims over a whole screen, shades over
    // album art / photos (over a panel use shade(), it turns white on light schemes)
    function dim(a) { return neutral(0, a) }
    // ── Deliberate fixed palettes (exceptions, DESIGN.md) ────────────────────
    // dashboard gauges: their own saturated set, the same on every wallpaper
    readonly property color chartRed: "#e05252"
    readonly property color chartOrange: "#f0a040"
    readonly property color chartAmber: "#e0a052"
    readonly property color chartBlue: "#52aaee"
    readonly property color chartPurple: "#a06ae0"
    readonly property color chartGreen: "#52e0a0"
    // mail bodies render on "paper" (HTML mail is written for white pages)
    readonly property color paperLight: "#fbfaf8"
    readonly property color paperLightText: "#1d1d1f"
    readonly property color paperLightSelection: "#a8c7fa"
    readonly property color paperLightLink: "#2a62c9"
    readonly property color paperDark: "#1c1c21"
    readonly property color paperDarkText: "#e2e2e6"
    readonly property color paperDarkSelection: "#4a5568"
    // text colours offered in the mail composer: they end up in the sent mail
    readonly property var mailTextSwatches: ["#000000", "#5f6368", "#d93025", "#e8710a", "#188038", "#1a73e8", "#9334e6"]
    // the checkerboard behind a colour swatch, so transparency shows
    readonly property color checkerLight: "#9a9a9a"
    readonly property color checkerDark: "#5a5a5a"
    // account colours (mail, calendar): fixed, so an account keeps its colour
    // across wallpapers (tokyonight)
    readonly property var accountPalette: ["#7aa2f7", "#9ece6a", "#e0af68", "#f7768e", "#bb9af7", "#7dcfff", "#ff9e64", "#73daca"]

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
    Behavior on background { ColorAnimation { duration: Anim.theme } }
    Behavior on foreground { ColorAnimation { duration: Anim.theme } }
    Behavior on color0 { ColorAnimation { duration: Anim.theme } }
    Behavior on color1 { ColorAnimation { duration: Anim.theme } }
    Behavior on color2 { ColorAnimation { duration: Anim.theme } }
    Behavior on color3 { ColorAnimation { duration: Anim.theme } }
    Behavior on color4 { ColorAnimation { duration: Anim.theme } }
    Behavior on color5 { ColorAnimation { duration: Anim.theme } }
    Behavior on color6 { ColorAnimation { duration: Anim.theme } }
    Behavior on color7 { ColorAnimation { duration: Anim.theme } }
    Behavior on color8 { ColorAnimation { duration: Anim.theme } }
    Behavior on color9 { ColorAnimation { duration: Anim.theme } }
    Behavior on color10 { ColorAnimation { duration: Anim.theme } }
    Behavior on color11 { ColorAnimation { duration: Anim.theme } }
    Behavior on color12 { ColorAnimation { duration: Anim.theme } }
    Behavior on color13 { ColorAnimation { duration: Anim.theme } }
    Behavior on color14 { ColorAnimation { duration: Anim.theme } }
    Behavior on color15 { ColorAnimation { duration: Anim.theme } }
}
