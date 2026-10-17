import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// One setting: label + description on the left, the control on the right,
// and a revert button once it differs from the default.
//
//   spec:  { key, label, desc, type: int|real|bool|color|string|choice|font,
//            min, max, step, options }
//   store: "properties" → Properties.qml values
//          "niri"       → niri config (NiriSettings)
//          "hyprland"   → Hyprland config (HyprSettings)
//          "calendar"   → calendar app options (Settings.calendar, default = spec.def)
Item {
    id: root

    required property var spec
    required property string store
    property bool sub: false             // option of the toggle above it
    property bool parentOn: true         // that toggle is on

    // a compositor setting: its settings service (NiriSettings / HyprSettings)
    readonly property var wm: store === "niri" ? NiriSettings : store === "hyprland" ? HyprSettings : null
    readonly property var current: wm ? wm.value(spec.key)
                                 : store === "calendar" ? (Settings.calendar[spec.key] ?? spec.def)
                                 : Properties[spec.key]
    readonly property bool changed: Settings[store][spec.key] !== undefined

    function hex2(x) { return Math.round(x * 255).toString(16).padStart(2, "0") }

    function set(v) {
        if (spec.type === "color") {
            const c = Qt.color(v)
            v = "#" + (c.a < 1 ? hex2(c.a) : "") + hex2(c.r) + hex2(c.g) + hex2(c.b)
        }
        if (wm) wm.set(spec.key, v)
        else Settings.set(store, spec.key, v)
    }

    // follow a pywal color (see Properties.walColor)
    function setLink(name, alpha) {
        Settings.set(store, spec.key, alpha < 1 ? { wal: name, alpha: alpha } : { wal: name })
    }

    function reset() {
        if (wm) wm.reset(spec.key)
        else Settings.reset(store, spec.key)
    }

    implicitHeight: Math.max(52, row.implicitHeight + 18)
    opacity: parentOn ? 1 : 0.4
    enabled: parentOn
    Behavior on opacity { NumberAnimation { duration: 150 } }

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: root.sub ? 30 : 16
        anchors.rightMargin: 12
        spacing: 12

        // sub-options hang off the toggle above with a little line
        Rectangle {
            visible: root.sub
            Layout.preferredWidth: 2
            Layout.preferredHeight: 18
            Layout.leftMargin: -14
            radius: 1
            color: Qt.rgba(1, 1, 1, 0.12)
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                spacing: 6
                Text {
                    text: root.spec.label
                    color: "white"
                    font.pixelSize: 13
                    font.bold: true
                    font.family: Properties.fontFamily
                }
                // changed-marker
                Rectangle {
                    visible: root.changed
                    width: 6; height: 6; radius: 3
                    color: Colors.color6
                }
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.spec.desc ?? ""
                color: Qt.rgba(1, 1, 1, 0.5)
                font.pixelSize: 11
                font.family: Properties.fontFamily
                wrapMode: Text.WordWrap
            }
        }

        IconButton {
            implicitWidth: 28
            implicitHeight: 28
            iconSize: 13
            icon: "󰑓"
            tooltip: root.wm ? "Back to your " + (root.store === "hyprland" ? "Hyprland" : "niri") + " config" : "Back to default"
            opacity: root.changed ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            onClicked: root.reset()
        }

        Loader {
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            sourceComponent: {
                switch (root.spec.type) {
                case "bool": return toggle
                case "int":
                case "real": return number
                case "color": return colorPicker
                case "choice": return choice
                default: return textField
                }
            }
        }
    }

    Component {
        id: toggle
        ToggleSwitch {
            checked: !!root.current
            onToggled: v => root.set(v)
        }
    }
    Component {
        id: number
        NumberControl {
            from: root.spec.min ?? 0
            to: root.spec.max ?? 100
            step: root.spec.type === "int" ? 1 : (root.spec.step ?? 0.1)
            value: Number(root.current)
            onEdited: v => root.set(v)
        }
    }
    Component {
        id: colorPicker
        ColorControl {
            value: root.current
            canLink: root.store === "properties"   // only Properties resolves links
            link: canLink ? (Settings.properties[root.spec.key]?.wal ?? "") : ""
            onEdited: v => root.set(v)
            onLinked: (name, alpha) => root.setLink(name, alpha)
        }
    }
    Component {
        id: choice
        ChoiceControl {
            options: root.spec.options
            value: root.current
            onEdited: v => root.set(v)
        }
    }
    Component {
        id: textField
        TextControl {
            value: root.current
            suggestions: root.spec.type === "font" ? Qt.fontFamilies() : []
            onEdited: v => root.set(v)
        }
    }
}
