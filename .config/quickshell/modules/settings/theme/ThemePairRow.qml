import QtQuick
import QtQuick.Layouts
import qs.services
import ".."
import "../network"

// One app part of the light / dark switch: on / off, and which theme to use
// in light and in dark mode (guessed from what's set now until you pick).
NetRow {
    id: row
    property string kind                     // gtk | icons | kvantum
    property string partKey: kind
    wide: true

    readonly property var options: (Theme.themes[kind] ?? []).map(n => ({ label: n, value: n }))

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        ToggleSwitch { checked: Theme.part(row.partKey); onToggled: v => Settings.set("theme", row.partKey, v) }
        Text { text: "󰖨"; color: Colors.fade(0.6); font.pixelSize: 14; font.family: Properties.fontFamily }
        DropdownControl {
            Layout.fillWidth: true
            enabled: Theme.part(row.partKey)
            options: row.options
            value: Theme.pair(row.kind, "light")
            onEdited: v => Settings.set("theme", row.kind + "Light", v)
        }
        Text { text: "󰖔"; color: Colors.fade(0.6); font.pixelSize: 14; font.family: Properties.fontFamily }
        DropdownControl {
            Layout.fillWidth: true
            enabled: Theme.part(row.partKey)
            options: row.options
            value: Theme.pair(row.kind, "dark")
            onEdited: v => Settings.set("theme", row.kind + "Dark", v)
        }
    }
}
