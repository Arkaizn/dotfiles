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
Item {
    id: root

    required property var spec
    required property string store
    property bool sub: false             // option of the toggle above it
    property bool parentOn: true         // that toggle is on

    readonly property bool isNiri: store === "niri"
    readonly property var current: isNiri ? NiriSettings.value(spec.key) : Properties[spec.key]
    readonly property bool changed: (isNiri ? Settings.niri : Settings.properties)[spec.key] !== undefined

    function hex2(x) { return Math.round(x * 255).toString(16).padStart(2, "0") }

    function set(v) {
        if (spec.type === "color") {
            const c = Qt.color(v)
            v = "#" + (c.a < 1 ? hex2(c.a) : "") + hex2(c.r) + hex2(c.g) + hex2(c.b)
        }
        if (isNiri) NiriSettings.set(spec.key, v)
        else Settings.set("properties", spec.key, v)
    }

    function reset() {
        if (isNiri) NiriSettings.reset(spec.key)
        else Settings.reset("properties", spec.key)
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
            tooltip: root.isNiri ? "Back to your niri config" : "Back to default"
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
            onEdited: v => root.set(v)
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
