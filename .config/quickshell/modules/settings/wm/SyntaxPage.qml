import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Syntax page: the config syntax the shell writes (services/Syntax.qml) —
// templates for binds / autostart / …, and the option path of every niri /
// Hyprland setting. For when a compositor update renames something small.
// Every write is still validated, so a broken template is rejected (shown at
// the bottom), never written.
ColumnLayout {
    id: page
    spacing: 16

    readonly property bool hypr: Compositor.isHyprland
    readonly property var svc: hypr ? HyprSettings : NiriSettings
    readonly property string store: hypr ? "hyprland" : "niri"
    readonly property var templateNames: Object.keys(Syntax.defaults).filter(n => n.startsWith(hypr ? "hypr." : "niri."))
    readonly property var otherNames: Object.keys(Syntax.defaults).filter(n => !n.startsWith(hypr ? "hypr." : "niri."))
    property bool showOther: false

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 6
        text: "How the shell writes " + (hypr ? "Hyprland's" : "niri's") + " config (" + svc.overridePath.replace(Quickshell.env("HOME"), "~")
              + "). If an update renames something, change it here. {placeholders} are filled in; strings come already quoted."
        color: Qt.rgba(1, 1, 1, 0.5)
        font.pixelSize: 11
        font.family: Properties.fontFamily
        wrapMode: Text.WordWrap
    }

    component TemplateRow: NetRow {
        id: tr
        required property string name
        wide: true
        label: name
        desc: Syntax.docs[name] ?? ""
        changed: Syntax.templates[name] !== undefined
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            SearchField {
                Layout.fillWidth: true
                implicitHeight: Properties.buttonHeight
                icon: ""
                clearable: false
                font.pixelSize: 12
                text: Syntax.template(tr.name)
                onEditingFinished: if (text !== Syntax.template(tr.name)) Syntax.setTemplate(tr.name, text)
            }
            IconButton {
                icon: "󰑓"
                tooltip: "Back to default: " + Syntax.defaults[tr.name]
                opacity: tr.changed ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
                onClicked: Syntax.setTemplate(tr.name, Syntax.defaults[tr.name])
            }
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: (page.hypr ? "Hyprland" : "niri") + " templates"
        icon: "󰅩"
        Repeater {
            model: page.templateNames
            TemplateRow { required property string modelData; required property int index; name: modelData; first: index === 0 }
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "Option paths  ·  " + page.svc.schema.length
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

    // the other compositor's templates (the shell writes both files)
    ActionButton {
        Layout.alignment: Qt.AlignLeft
        icon: page.showOther ? "󰅃" : "󰅀"
        text: (page.showOther ? "Hide " : "Show ") + (page.hypr ? "niri" : "Hyprland") + " templates"
        onClicked: page.showOther = !page.showOther
    }
    Reveal {
        open: page.showOther
        NetCard {
            Layout.fillWidth: true
            title: (page.hypr ? "niri" : "Hyprland") + " templates"
            icon: "󰅩"
            Repeater {
                model: page.otherNames
                TemplateRow { required property string modelData; required property int index; name: modelData; first: index === 0 }
            }
        }
    }

    // ── Preview ─────────────────────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        title: "What gets written"
        icon: "󰈙"
        header: [
            Text {
                text: page.svc.error !== "" ? "rejected" : "valid"
                color: page.svc.error !== "" ? "#f38ba8" : Colors.color6
                font.pixelSize: 11
                font.bold: true
                font.family: Properties.fontFamily
            }
        ]
        Text {
            Layout.fillWidth: true
            Layout.margins: 14
            visible: page.svc.error !== ""
            text: "󰀦  " + (page.hypr ? "Hyprland" : "niri") + " rejected it, the old file stays:\n" + page.svc.error
            color: "#f38ba8"
            font.pixelSize: 11
            font.family: Properties.fontFamily
            wrapMode: Text.Wrap
        }
        Text {
            Layout.fillWidth: true
            Layout.margins: 14
            text: { Settings.syntax; Settings.keybinds; Settings.autostart; Settings[page.store]; return page.svc.generate() }
            color: Qt.rgba(1, 1, 1, 0.75)
            font.pixelSize: 11
            font.family: Properties.fontFamily
            wrapMode: Text.WrapAnywhere
            textFormat: Text.PlainText
        }
    }
}
