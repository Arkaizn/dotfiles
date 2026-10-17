import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Syntax page: everything the shell writes into the compositor config
// (services/Syntax.qml) — the names the compositor uses ("words"), the
// templates for settings, keybinds, autostart, windows, monitors and the
// include line, and the option path of every setting. For when an update
// renames or reshapes something. Every write is still validated, so a broken
// template is rejected (shown at the bottom), never written.
ColumnLayout {
    id: page
    spacing: 16

    readonly property bool hypr: Compositor.isHyprland
    readonly property var svc: hypr ? HyprSettings : NiriSettings
    readonly property string store: hypr ? "hyprland" : "niri"
    readonly property string lang: hypr ? "hypr" : "niri"
    property bool showOther: false

    readonly property var groups: ({
        niri: [
            { title: "Settings", icon: "󰒓", names: ["niri.option", "niri.flagOn", "niri.flagOff", "niri.section", "niri.sectionOn", "niri.sectionOff"] },
            { title: "Keybinds", icon: "󰌌", names: ["niri.bindsBlock", "niri.bind", "niri.title", "niri.spawnSh", "niri.disable", "niri.keyJoin"] },
            { title: "Autostart", icon: "󰐊", names: ["niri.autostart"] },
            { title: "Settings / calendar windows", icon: "󰖲", names: ["niri.windowRule", "niri.windowBlur"] },
            { title: "Monitors", icon: "󰍹", names: ["niri.output", "niri.outputOff", "niri.outputMode", "niri.outputScale", "niri.outputTransform", "niri.outputPosition", "niri.outputVrr"] },
            { title: "Include line", icon: "󰈙", names: ["niri.include"] }
        ],
        hypr: [
            { title: "Settings", icon: "󰒓", names: ["hypr.config"] },
            { title: "Keybinds", icon: "󰌌", names: ["hypr.bind", "hypr.exec", "hypr.unbind", "hypr.keyJoin"] },
            { title: "Autostart", icon: "󰐊", names: ["hypr.autostart"] },
            { title: "Settings / calendar windows", icon: "󰖲", names: ["hypr.windowRule"] },
            { title: "Monitors", icon: "󰍹", names: ["hypr.monitor", "hypr.monitorOff"] }
        ]
    })

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 6
        text: "Everything the shell writes into " + (hypr ? "Hyprland's" : "niri's") + " config. Templates use two kinds of placeholders: "
              + "{@word} is a name " + (hypr ? "Hyprland" : "niri") + " uses (edit it under Words), {value} is filled in by the shell "
              + "(strings come quoted). Example: if spawn-sh-at-startup \"x\" became spawn-shell-at-startup=\"x\", set the autostart "
              + "template to {@autostart}={cmd} and the word autostart to spawn-shell-at-startup."
        color: Qt.rgba(1, 1, 1, 0.5)
        font.pixelSize: 11
        font.family: Properties.fontFamily
        wrapMode: Text.WordWrap
    }

    // ── Words ───────────────────────────────────────────────────────────────

    // ── Templates ───────────────────────────────────────────────────────────


    SyntaxWords { lg: page.lang }
    SyntaxTemplates { lg: page.lang; groups: page.groups[page.lang] }

    // ── Option paths ────────────────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        title: "Option paths  ·  " + page.svc.schema.length + (page.hypr ? "  (section.option)" : "  (section/option)")
        icon: "󰘦"
        Repeater {
            model: page.svc.schema
            NetRow {
                id: pr
                required property var modelData
                required property int index
                readonly property string cur: Syntax.path(page.store, modelData.key, modelData.path)
                first: index === 0
                label: modelData.label
                desc: modelData.path === "" ? "(not a config option)" : ""
                changed: cur !== modelData.path
                SearchField {
                    implicitWidth: 300
                    implicitHeight: Properties.buttonHeight
                    icon: ""
                    clearable: false
                    font.pixelSize: 12
                    enabled: pr.modelData.path !== ""
                    text: pr.cur
                    onEditingFinished: if (text !== pr.cur) Syntax.setPath(page.store, pr.modelData.key, text.trim(), pr.modelData.path)
                }
                IconButton {
                    icon: "󰑓"
                    tooltip: "Back to default: " + pr.modelData.path
                    opacity: pr.changed ? 1 : 0
                    visible: opacity > 0
                    onClicked: Syntax.setPath(page.store, pr.modelData.key, pr.modelData.path, pr.modelData.path)
                }
            }
        }
    }

    // the other compositor's syntax (the shell writes both files)
    ActionButton {
        Layout.alignment: Qt.AlignLeft
        icon: page.showOther ? "󰅃" : "󰅀"
        text: (page.showOther ? "Hide " : "Show ") + (page.hypr ? "niri" : "Hyprland") + " syntax"
        onClicked: page.showOther = !page.showOther
    }
    Reveal {
        open: page.showOther
        spacing: 16
        SyntaxWords { lg: page.hypr ? "niri" : "hypr" }
        SyntaxTemplates { lg: page.hypr ? "niri" : "hypr"; groups: page.groups[page.hypr ? "niri" : "hypr"] }
    }

    // ── Preview ─────────────────────────────────────────────────────────────

    Text {
        Layout.leftMargin: 6
        Layout.topMargin: 4
        text: "What gets written"
        color: Qt.rgba(1, 1, 1, 0.55)
        font.pixelSize: 12
        font.bold: true
        font.family: Properties.fontFamily
    }
    SyntaxPreview {
        file: page.svc.overridePath
        body: { Settings.syntax; Settings.keybinds; Settings.autostart; Settings[page.store]; return page.svc.generate() }
        error: page.svc.error
    }
    SyntaxPreview {
        file: page.hypr ? HyprSettings.monitorsPath : Monitors.outputsPath
        body: { Settings.syntax; Settings.monitors; return page.hypr ? Monitors.generateHypr() : Monitors.generate() }
        error: Monitors.error
    }
}
