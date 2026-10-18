import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Notifications page: do not disturb (+ schedule), popup position / timing,
// per-app rules and test notifications (services/Notifs.qml).
ColumnLayout {
    id: page
    spacing: 16

    readonly property var cfg: Settings.notifications
    readonly property var rules: Array.isArray(cfg.rules) ? cfg.rules : []
    property string newApp: ""
    property string ruleError: ""

    function setRules(r) { Settings.set("notifications", "rules", r) }
    function addRule(app) {
        app = app.trim()
        if (app === "") { ruleError = "enter an app name"; return }
        if (rules.some(r => r.app.toLowerCase() === app.toLowerCase())) { ruleError = "there's already a rule for " + app; return }
        ruleError = ""
        setRules(rules.concat([{ app: app, action: "silent" }]))
        newApp = ""
    }

    // apps that sent something: this session + what's in the center
    readonly property var knownApps: {
        const a = Notifs.seenApps.slice()
        for (let i = 0; i < Notifs.groupModel.count; i++) {
            const n = Notifs.groupModel.get(i).appName
            if (!a.includes(n)) a.push(n)
        }
        return a.filter(n => !rules.some(r => r.app.toLowerCase() === n.toLowerCase())).sort()
    }

    // ── Do not disturb ──────────────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        title: "Do not disturb"
        icon: Notifs.dnd ? "󰂛" : "󰂚"
        NetRow {
            first: true
            label: "Do not disturb"
            desc: Notifs.dnd ? (Notifs.dndManual ? "on" : "on by the schedule") + (Notifs.missed > 0 ? " · " + Notifs.missed + " held back (in the notification center)" : "")
                             : "popups show normally. Also: right-click the bell on the bar"
            ToggleSwitch { checked: Notifs.dndManual; onToggled: v => Notifs.setDnd(v) }
        }
        NetRow {
            label: "On a schedule"
            desc: "every day, e.g. 22:00 → 07:00 (over midnight works)"
            ToggleSwitch { checked: page.cfg.scheduleOn ?? false; onToggled: v => Settings.set("notifications", "scheduleOn", v) }
        }
        NetRow {
            visible: page.cfg.scheduleOn ?? false
            sub: true
            label: "From  →  to"
            desc: Notifs.minutesOf(page.cfg.scheduleFrom ?? "22:00") < 0 || Notifs.minutesOf(page.cfg.scheduleTo ?? "07:00") < 0
                  ? "use HH:MM, e.g. 22:00" : (Notifs.dndScheduled ? "active right now" : "not active right now")
            RowLayout {
                spacing: 8
                TextControl {
                    implicitWidth: 90
                    value: page.cfg.scheduleFrom ?? "22:00"
                    onEdited: v => Settings.set("notifications", "scheduleFrom", v.trim())
                }
                Text { text: "→"; color: Qt.rgba(1, 1, 1, 0.5); font.family: Properties.fontFamily }
                TextControl {
                    implicitWidth: 90
                    value: page.cfg.scheduleTo ?? "07:00"
                    onEdited: v => Settings.set("notifications", "scheduleTo", v.trim())
                }
            }
        }
        NetRow {
            label: "Critical ones still pop up"
            desc: "e.g. low battery, failed backups"
            ToggleSwitch { checked: page.cfg.allowCritical ?? true; onToggled: v => Settings.set("notifications", "allowCritical", v) }
        }
    }

    // ── Popups ──────────────────────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        title: "Popups"
        NetRow {
            first: true
            label: "Position"
            DropdownControl {
                options: [{ label: "Top right", value: "top-right" }, { label: "Top centre", value: "top-center" },
                          { label: "Top left", value: "top-left" }, { label: "Bottom right", value: "bottom-right" },
                          { label: "Bottom left", value: "bottom-left" }]
                value: Notifs.position
                onEdited: v => Settings.set("notifications", "position", v)
            }
        }
        NetRow {
            label: "Show for (seconds)"
            desc: "when the app doesn't say; critical ones stay until closed"
            NumberControl { from: 1; to: 60; value: page.cfg.timeout ?? 5; onEdited: v => Settings.set("notifications", "timeout", Math.round(v)) }
        }
        NetRow {
            label: "At most on screen"
            NumberControl { from: 1; to: 10; value: page.cfg.maxPopups ?? 5; onEdited: v => Settings.set("notifications", "maxPopups", Math.round(v)) }
        }
    }

    // ── Rules ───────────────────────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        title: "Per-app rules"
        NetRow {
            first: true
            wide: true
            label: "Add a rule"
            desc: page.ruleError !== "" ? page.ruleError
                  : "app name as it appears on the notification; * matches anything (e.g. *discord*). Silent: notification center only. Hide: dropped."
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    SearchField {
                        Layout.fillWidth: true
                        icon: ""
                        clearable: false
                        placeholderText: "e.g. Spotify"
                        text: page.newApp
                        error: page.ruleError !== ""
                        onTextEdited: page.newApp = text
                        onAccepted: page.addRule(page.newApp)
                    }
                    ActionButton { icon: "󰐕"; text: "Add"; onClicked: page.addRule(page.newApp) }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: page.knownApps.length > 0
                    Repeater {
                        model: page.knownApps
                        Chip {
                            required property string modelData
                            text: "+ " + modelData
                            copyable: false
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.addRule(parent.modelData) }
                        }
                    }
                }
            }
        }
        Repeater {
            model: page.rules
            NetRow {
                required property var modelData
                required property int index
                label: modelData.app
                desc: modelData.action === "hide" ? "dropped, never shown" : modelData.action === "silent" ? "no popup, kept in the center" : "normal"
                RowLayout {
                    spacing: 6
                    Segmented {
                        small: true
                        options: [{ label: "Normal", value: "normal" }, { label: "Silent", value: "silent" }, { label: "Hide", value: "hide" }]
                        value: modelData.action ?? "normal"
                        onEdited: v => page.setRules(page.rules.map((r, i) => i === index ? { app: r.app, action: v } : r))
                    }
                    IconButton {
                        icon: "󰆴"
                        tooltip: "Remove the rule"
                        onClicked: page.setRules(page.rules.filter((r, i) => i !== index))
                    }
                }
            }
        }
    }

    // ── Test ────────────────────────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        title: "Test"
        NetRow {
            first: true
            label: "Send a test notification"
            desc: Notifs.dnd ? "do not disturb is on: normal ones go to the center only" : "goes through the rules above (app name \"Notification test\")"
            RowLayout {
                spacing: 6
                ActionButton {
                    text: "Normal"
                    onClicked: Jobs.run(["notify-send", "-a", "Notification test", "Hello", "A normal notification at " + Qt.formatTime(new Date(), "HH:mm:ss")], () => {})
                }
                ActionButton {
                    text: "Critical"
                    onClicked: Jobs.run(["notify-send", "-a", "Notification test", "-u", "critical", "Critical", "Stays until you close it"], () => {})
                }
                ActionButton {
                    text: "With buttons"
                    onClicked: Jobs.run(["notify-send", "-a", "Notification test", "-A", "yes=Yes", "-A", "no=No", "Question", "Pick one"],
                                        (code, out) => { if (out.trim()) Jobs.run(["notify-send", "-a", "Notification test", "You picked", out.trim()], () => {}) })
                }
            }
        }
    }
}
