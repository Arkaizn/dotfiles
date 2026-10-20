import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "network"

// Health page: what the shell needs, and whether it's there and working
// (services/Health.qml). Each check: status, details, a fix you can copy, and
// a re-run button. Runs when the page opens if it hasn't run yet.
ColumnLayout {
    id: page
    spacing: 16

    Component.onCompleted: if (Health.results.length === 0 && !Health.running) Health.run()

    readonly property var groups: {
        const g = []
        for (const r of Health.results) if (!g.includes(r.group)) g.push(r.group)
        return g
    }

    function statusColor(s) { return s === "ok" ? Colors.color6 : s === "warn" ? Colors.yellow : s === "error" ? Colors.red : Colors.fade(0.5) }
    function statusIcon(s) { return s === "ok" ? "󰄬" : s === "warn" ? "󰀦" : s === "error" ? "󰅙" : "󰔟" }

    // ── Summary ─────────────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: sumRow.implicitHeight + 28
        radius: 14
        readonly property color tint: Health.errors > 0 ? Qt.rgba(0.95, 0.55, 0.66, 1) : Health.warnings > 0 ? Qt.rgba(0.98, 0.89, 0.69, 1) : Colors.color6
        color: Qt.rgba(tint.r, tint.g, tint.b, 0.08)
        border.width: Properties.panelBorderWidth
        border.color: Qt.rgba(tint.r, tint.g, tint.b, 0.35)
        Behavior on color { ColorAnimation { duration: 250 } }

        RowLayout {
            id: sumRow
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 18; rightMargin: 14 }
            spacing: 14
            Text {
                text: Health.running ? "󰔟" : Health.errors > 0 ? "󰅙" : Health.warnings > 0 ? "󰀦" : "󰄬"
                color: page.statusColor(Health.running ? "running" : Health.errors > 0 ? "error" : Health.warnings > 0 ? "warn" : "ok")
                font.pixelSize: 30
                font.family: Properties.fontFamily
                RotationAnimation on rotation { running: Health.running; loops: Animation.Infinite; from: 0; to: 360; duration: 1200 }
                onTextChanged: if (!Health.running) rotation = 0
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: Health.running ? "Checking…"
                        : Health.results.length === 0 ? "Not checked yet"
                        : Health.errors > 0 ? Health.errors + (Health.errors === 1 ? " problem" : " problems") + (Health.warnings > 0 ? ", " + Health.warnings + " warnings" : "")
                        : Health.warnings > 0 ? "Works, " + Health.warnings + (Health.warnings === 1 ? " warning" : " warnings")
                        : "Everything looks good"
                    color: Colors.ink
                    font.pixelSize: 16
                    font.bold: true
                    font.family: Properties.fontFamily
                }
                Text {
                    text: Health.lastRun > 0 ? Health.results.filter(r => r.status === "ok").length + " of " + Health.results.length
                                                + " checks ok  ·  last run " + new Date(Health.lastRun).toLocaleTimeString(Qt.locale(), "HH:mm:ss") : ""
                    color: Colors.fade(0.5)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                }
            }
            ActionButton {
                icon: "󰑓"
                text: "Run all checks"
                primary: true
                interactive: !Health.running
                onClicked: Health.run()
            }
        }
    }

    NetCard {
        Layout.fillWidth: true
        NetRow {
            first: true
            label: "First-run setup"
            desc: "name, bar preset, notifications, keys: the welcome steps of a new install"
            ActionButton { icon: "󰐊"; text: "Run again"; onClicked: Panels.open("wizard") }
        }
        NetRow {
            label: "Check at startup"
            desc: "20 s after the shell starts; a notification only if something is an error"
            ToggleSwitch {
                checked: Settings.health.startupCheck ?? true
                onToggled: v => Settings.set("health", "startupCheck", v)
            }
        }
    }

    // ── Checks by group ─────────────────────────────────────────────────────
    Repeater {
        model: page.groups
        NetCard {
            id: gcard
            required property string modelData
            Layout.fillWidth: true
            title: modelData
            Repeater {
                model: Health.results.filter(r => r.group === gcard.modelData)
                NetRow {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property var r: modelData
                    first: index === 0
                    wide: r.fix !== ""
                    label: r.title
                    desc: r.detail
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            text: page.statusIcon(row.r.status)
                            color: page.statusColor(row.r.status)
                            font.pixelSize: 16
                            font.family: Properties.fontFamily
                        }
                        Text {
                            text: row.r.status === "running" ? "checking…" : row.r.status
                            color: page.statusColor(row.r.status)
                            font.pixelSize: 11
                            font.bold: true
                            font.family: Properties.fontFamily
                        }
                        // the fix, with a copy button
                        Text {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            visible: row.r.fix !== ""
                            text: "Fix:  " + row.r.fix
                            color: Colors.fade(0.75)
                            font.pixelSize: 11
                            font.family: Properties.fontFamily
                            wrapMode: Text.WrapAnywhere
                        }
                        IconButton {
                            id: copyBtn
                            visible: row.r.fix !== ""
                            property bool copied: false
                            icon: copied ? "󰄬" : "󰆏"
                            tooltip: "Copy the fix"
                            onClicked: { Quickshell.execDetached(["wl-copy", "--", row.r.fix]); copied = true; copiedTimer.restart() }
                            Timer { id: copiedTimer; interval: 1200; onTriggered: copyBtn.copied = false }
                        }
                        Item { visible: row.r.fix === ""; Layout.fillWidth: true }
                        IconButton {
                            icon: "󰑓"
                            tooltip: "Check again"
                            interactive: row.r.status !== "running"
                            onClicked: Health.runOne(row.r.id)
                        }
                    }
                }
            }
        }
    }
}
