pragma Singleton
import QtQuick
import qs.services

Rectangle {
    id: root

    // properties / settings
    property int iconSize: 18
    property int spacing: 5
    property int radius: 8
    property int interval: 500 // interval update components in bar
    property int bDuration: 140

    // Button Background
    property bool hovered: false
    property string iconText: ""
    property color color: Colors.ink
    

    // Text / Font
    property int pixelSize: 13
    property string fontFamily: "JetBrainsMono Nerd Font"
    property bool fontBold: false   

    // Margin
    property int barMarginBottom: 0
    property int barMarginTop: 0
    property int barMarginLeft: 10
    property int barMarginRight: 10

    // Scale
    property double onEnteredTextScale: 1.2
    property double onExitedTextScale: 1.0
    property double onEnteredButtonScale: 1.1
    property double onExitedButtonScale: 1.0
    property double onPressedButtonScale: 0.92   // while a button is held down

    // Panels — the bar and every popup attached to it (BarPopup)
    // (defaults follow the pywal colors and light / dark: see themeDefaults below)
    property color panelColor: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.86)
    property color panelBorder: Colors.fade(0.13)
    property real panelBorderWidth: 1
    property color cardBorder: Colors.fade(0.10)   // outline of inner cards (dashboard, notif center)
    property int barRadius: 15       // bar corners
    property int popupRadius: 12     // notification popup cards
    property int panelRadius: 30     // big widgets: dashboard, notification center, wallpapers, launcher
    property int flareRadius: 30     // inverted corners where a popup meets the bar
    property int barInset: 10        // gap between screen edge and the bar

    // Button settings
    property int buttonHeight: 32
    property int buttonWidth: 20
    property int buttonradius: 10


    // Colors
    property color colorfg: Qt.rgba(0, 0, 0, 0.54)
    property color colorfgHovered: Qt.rgba(0.12, 0.12, 0.12, 0.1) 
    property color buttonColorIfHovered: root.hovered ? Qt.rgba(0, 0, 0, 0.31) : Qt.rgba(0, 0, 0, 0.3)
    property color textColorIfHovered: root.hovered ? Colors.color6 : Colors.foreground


    // ── Settings app ─────────────────────────────────────────────────────────
    // The values above are the defaults. The settings app stores changes in
    // settings.json (services/Settings.qml); they're applied on top of these
    // and reverting one puts the default back.
    readonly property var settingKeys: [
        "iconSize", "spacing", "radius", "interval", "bDuration", "color",
        "pixelSize", "fontFamily", "fontBold",
        "barMarginLeft", "barMarginRight",
        "onEnteredTextScale", "onEnteredButtonScale", "onPressedButtonScale",
        "panelColor", "panelBorder", "panelBorderWidth", "cardBorder",
        "barRadius", "popupRadius", "panelRadius", "flareRadius", "barInset",
        "buttonHeight", "buttonWidth", "buttonradius"
    ]
    property var defaults: ({})
    property var walLinked: ({})   // keys currently bound to a pywal color
    // defaults that follow the theme (the panel look of the settings app: the
    // pywal background at 86 %, text and borders in the light / dark ink)
    readonly property var themeDefaults: ({
        panelColor: { wal: "background", alpha: 0.86 },
        panelBorder: { wal: "ink", alpha: 0.13 },
        cardBorder: { wal: "ink", alpha: 0.10 },
        color: { wal: "ink" }
    })

    // A color setting can be a hex string or a link to a pywal color:
    //   { "wal": "color4", "alpha": 0.8 }   (alpha optional)
    // A link is a binding, so it follows Colors on every wallpaper change.
    function walColor(link) {
        const c = Colors[link.wal] ?? Colors.foreground
        return Qt.rgba(c.r, c.g, c.b, link.alpha ?? 1)
    }

    function applySettings() {
        if (Object.keys(defaults).length === 0) {
            const d = {}
            // colors read from a property are live references to it, so copy them;
            // otherwise the "default" changes along with the property
            for (const k of settingKeys) {
                const v = root[k]
                d[k] = typeof v === "object" ? Qt.rgba(v.r, v.g, v.b, v.a) : v
            }
            defaults = d
        }
        const o = Settings.properties
        const linked = {}
        for (const k of settingKeys) {
            const v = o[k] !== undefined ? o[k] : (themeDefaults[k] ?? defaults[k])
            if (v?.wal !== undefined) {
                root[k] = Qt.binding(() => root.walColor(v))
                linked[k] = true
            } else if (walLinked[k] || root[k] !== v) {
                root[k] = v   // also drops a previous pywal binding
            }
        }
        walLinked = linked
    }

    Component.onCompleted: applySettings()
    Connections {
        target: Settings
        function onPropertiesChanged() { root.applySettings() }
    }
}

