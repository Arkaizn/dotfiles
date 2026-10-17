import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "SettingsSearch.js" as SI

// One setting: label + description on the left, the control on the right,
// and a revert button once it differs from the default.
//
//   spec:  { key, label, desc, type: int|real|bool|color|string|choice|font,
//            min, max, step, options }
//   store: "properties" → Properties.qml values
//          "niri"       → niri config (NiriSettings)
//          "hyprland"   → Hyprland config (HyprSettings)
//          other        → that group of settings.json (calendar, battery, …; default = spec.def)
//   type "button": an action, `spec.run()` on click (`spec.text` on the button)
Item {
    id: root

    required property var spec
    required property string store
    property bool sub: false             // option of the toggle above it
    property bool parentOn: true         // that toggle is on
    // in search results: highlight the query, show where it lives (click → go there)
    property string query: ""
    property string crumb: ""
    property bool selected: false
    signal openRequested()

    // jumped to from search: a glow that fades in and out
    function flash() { flashAnim.restart() }

    // a compositor setting: its settings service (NiriSettings / HyprSettings)
    readonly property var wm: store === "niri" ? NiriSettings : store === "hyprland" ? HyprSettings : null
    readonly property var current: wm ? wm.value(spec.key)
                                 : store === "properties" ? Properties[spec.key]
                                 : (Settings[store]?.[spec.key] ?? spec.def)
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

    Rectangle {
        id: flashRect
        anchors.fill: parent
        anchors.margins: 2
        radius: 10
        color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.22)
        border.width: 1.5
        border.color: Colors.color6
        opacity: 0
        SequentialAnimation {
            id: flashAnim
            NumberAnimation { target: flashRect; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
            PauseAnimation { duration: 350 }
            NumberAnimation { target: flashRect; property: "opacity"; to: 0.35; duration: 250 }
            NumberAnimation { target: flashRect; property: "opacity"; to: 1; duration: 250 }
            PauseAnimation { duration: 500 }
            NumberAnimation { target: flashRect; property: "opacity"; to: 0; duration: 900; easing.type: Easing.InOutQuad }
        }
    }

    // keyboard selection in search results
    Rectangle {
        anchors.fill: parent
        anchors.margins: 3
        radius: 10
        color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, root.selected ? 0.1 : 0)
        border.width: root.selected ? 1 : 0
        border.color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.45)
        Behavior on color { ColorAnimation { duration: 120 } }
    }
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

            // search results: "Page › Section ›", click to go there
            Text {
                visible: root.crumb !== ""
                text: root.crumb + "  󰅂"
                color: crumbMouse.containsMouse ? Colors.color6 : Qt.rgba(1, 1, 1, 0.4)
                font.pixelSize: 10
                font.family: Properties.fontFamily
                Behavior on color { ColorAnimation { duration: 120 } }
                MouseArea {
                    id: crumbMouse
                    anchors.fill: parent
                    anchors.margins: -3
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openRequested()
                }
            }
            RowLayout {
                spacing: 6
                Text {
                    text: root.query !== "" ? SI.highlight(root.spec.label, root.query, Colors.color6.toString()) : root.spec.label
                    textFormat: root.query !== "" ? Text.StyledText : Text.PlainText
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
                case "button": return button
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
        id: button
        ActionButton {
            icon: root.spec.icon ?? ""
            text: root.spec.text ?? root.spec.label
            onClicked: root.spec.run()
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
