import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "../settings"

// The calendar settings' pages (CalendarStore.settingsPages lists them), shown one
// at a time: in the calendar's settings dialog (CalendarSettings, a PagedModal)
// and as sub-pages of Calendar in the settings app. Each page: `pageId` +
// visible: shows(pageId).
ColumnLayout {
    id: root

    // (first: the account pages' delegates use them)
    component Hint: Text {
        Layout.fillWidth: true
        Layout.leftMargin: 6
        color: Colors.fade(0.42)
        font.pixelSize: 11
        font.family: Properties.fontFamily
        wrapMode: Text.Wrap
    }

    component SectionTitle: Text {
        Layout.leftMargin: 6
        Layout.topMargin: 6
        color: Colors.fade(0.55)
        font.pixelSize: 12
        font.bold: true
        font.family: Properties.fontFamily
    }

    component Card: Rectangle {
        default property alias content: col.data
        Layout.fillWidth: true
        implicitHeight: col.implicitHeight
        radius: 14
        color: Colors.card
        border.width: Properties.panelBorderWidth
        border.color: Properties.cardBorder
        ColumnLayout {
            id: col
            width: parent.width
            spacing: 0
        }
    }

    component Divider: Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 16
        Layout.rightMargin: 16
        implicitHeight: 1
        color: Colors.fade(0.06)
    }

    property string page: ""
    property bool showAll: false            // every page laid out (the dialog's search)
    signal transfer(string mode)
    function shows(id) { return page === id || showAll }
    function kindOf(a) { return CalendarStore.kindOf(a) }
    function opt(key, def) { return Settings.calendar[key] ?? def }
    function setOpt(key, v) { Settings.set("calendar", key, v) }

    function hex(c) {
        const h = x => Math.round(x * 255).toString(16).padStart(2, "0")
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }

    spacing: 8

    // ── Reminders ──
    ColumnLayout {
        readonly property string pageId: "reminders"
        visible: root.shows(pageId)
        Layout.fillWidth: true
        spacing: 8
        Card {
            PlainRow {
                Layout.fillWidth: true
                label: "Reminders"
                desc: "Notification before an event starts"
                ToggleSwitch { checked: root.opt("reminders", true); onToggled: v => root.setOpt("reminders", v) }
            }
            Divider {}
            PlainRow {
                Layout.fillWidth: true
                enabled: root.opt("reminders", true)
                opacity: enabled ? 1 : 0.4
                label: "Default reminder"
                desc: "Minutes before, for events without their own"
                ChoiceControl { options: ["off", "5", "10", "15", "30", "60"]; value: root.opt("defaultReminder", "10"); onEdited: v => root.setOpt("defaultReminder", v) }
            }
            Divider {}
            PlainRow {
                Layout.fillWidth: true
                enabled: root.opt("reminders", true)
                opacity: enabled ? 1 : 0.4
                label: "All-day events"
                desc: "Remind at 09:00 on the day"
                ToggleSwitch { checked: root.opt("allDayReminder", false); onToggled: v => root.setOpt("allDayReminder", v) }
            }
            Divider {}
            PlainRow {
                Layout.fillWidth: true
                enabled: root.opt("reminders", true)
                opacity: enabled ? 1 : 0.4
                label: "When it starts"
                desc: "Another notification at the start time"
                ToggleSwitch { checked: root.opt("startReminder", false); onToggled: v => root.setOpt("startReminder", v) }
            }
            Divider {}
            PlainRow {
                Layout.fillWidth: true
                enabled: root.opt("reminders", true)
                opacity: enabled ? 1 : 0.4
                label: "Sound"
                desc: "Played with the notification (not with do not disturb)"
                RowLayout {
                    spacing: 4
                    IconButton {
                        implicitWidth: 26; implicitHeight: 26; iconSize: 11
                        icon: "󰐊"
                        tooltip: "Play it"
                        visible: root.opt("reminderSound", "message") !== "off"
                        onClicked: CalendarStore.playSound(root.opt("reminderSound", "message"))
                    }
                    ChoiceControl {
                        options: ["off", "message", "bell", "alarm", "complete"]
                        value: root.opt("reminderSound", "message")
                        onEdited: v => { root.setOpt("reminderSound", v); CalendarStore.playSound(v) }
                    }
                }
            }
        }
        Hint { text: "Reminders per calendar: the 󰂚 on an account's page." }
    }

    // ── View ──
    ColumnLayout {
        readonly property string pageId: "view"
        visible: root.shows(pageId)
        Layout.fillWidth: true
        spacing: 8
        Card {
            PlainRow {
                Layout.fillWidth: true
                label: "Open in"
                desc: "View when the app starts"
                ChoiceControl { options: ["day", "week", "month", "agenda"]; value: root.opt("defaultView", "month"); onEdited: v => root.setOpt("defaultView", v) }
            }
            Divider {}
            PlainRow {
                Layout.fillWidth: true
                label: "Week numbers"
                ToggleSwitch { checked: root.opt("weekNumbers", true); onToggled: v => root.setOpt("weekNumbers", v) }
            }
        }
        SectionTitle { text: "Day and week" }
        Card {
            PlainRow {
                Layout.fillWidth: true
                label: "Day starts at"
                desc: "Where the day and week views scroll to"
                ChoiceControl { options: ["6", "7", "8", "9", "10"]; value: root.opt("dayStart", "7"); onEdited: v => root.setOpt("dayStart", v) }
            }
            Divider {}
            PlainRow {
                Layout.fillWidth: true
                label: "Zoom"
                desc: "Hour height in the day and week views, %  (also Ctrl + wheel over the hours, Ctrl Alt +/−)"
                ChoiceControl { options: CalendarStore.zoomSteps.map(String); value: String(CalendarStore.zoom); onEdited: v => root.setOpt("zoom", v) }
            }
        }
    }

    // ── Sync ──
    ColumnLayout {
        readonly property string pageId: "sync"
        visible: root.shows(pageId)
        Layout.fillWidth: true
        spacing: 8
        Card {
            PlainRow {
                Layout.fillWidth: true
                label: "Sync every"
                desc: "Minutes, also in the background for the dashboard and reminders"
                ChoiceControl { options: ["5", "15", "30", "60"]; value: root.opt("syncMinutes", "15"); onEdited: v => root.setOpt("syncMinutes", v) }
            }
            Divider {}
            PlainRow {
                Layout.fillWidth: true
                label: "Save moves after"
                desc: "Seconds after the last drag in the day / week view; moves made meanwhile are saved together"
                ChoiceControl { options: ["0", "5", "10", "30", "60"]; value: root.opt("moveDelay", "10"); onEdited: v => root.setOpt("moveDelay", v) }
            }
        }
    }

    // ── Export / import ──
    ColumnLayout {
        readonly property string pageId: "transfer"
        visible: root.shows(pageId)
        Layout.fillWidth: true
        spacing: 8
        Card {
            PlainRow {
                Layout.fillWidth: true
                label: "Export"
                desc: "Some or all accounts in one file — with their passwords / sign-ins encrypted by a passphrase, or without them"
                ActionButton { icon: "󰈔"; text: "Export…"; interactive: CalendarStore.accounts.length > 0; onClicked: root.transfer("export") }
            }
            Divider {}
            PlainRow {
                Layout.fillWidth: true
                label: "Import"
                desc: "A file exported here (or from the settings app); an account that's already here is updated"
                ActionButton { icon: "󰇚"; text: "Import…"; onClicked: root.transfer("import") }
            }
        }
        Hint { text: "Events (.ics files): the import button in the calendar's sidebar. Settings → Accounts has the mail and calendar accounts together." }
    }

    // ── one page per account ──
    Repeater {
        model: CalendarStore.accounts
        ColumnLayout {
            id: accPage
            required property var modelData
            readonly property var a: modelData
            readonly property string pageId: "acc:" + a.id
            visible: root.shows(pageId)
            Layout.fillWidth: true
            spacing: 8
            ConfirmArm { id: accArm }

            Card {
                PlainRow {
                    Layout.fillWidth: true
                    label: "Name"
                    TextControl {
                        implicitWidth: 240
                        value: accPage.a.name
                        onEdited: v => { if (v.trim()) CalendarStore.renameAccount(accPage.a.id, v.trim()) }
                    }
                }
                Divider {}
                PlainRow {
                    Layout.fillWidth: true
                    label: "Kind"
                    desc: accPage.a.type === "ics" ? accPage.a.url : accPage.a.type === "local" ? "Kept on this computer" : (accPage.a.url ?? "")
                    Text { text: root.kindOf(accPage.a); color: Colors.fade(0.55); font.pixelSize: 12; font.family: Properties.fontFamily }
                }
            }

            SectionTitle { text: "Calendars" }
            Card {
                Repeater {
                    model: accPage.a.calendars
                    ColumnLayout {
                        id: calRow
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 0
                        Divider { visible: calRow.index > 0 }
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 52
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 12
                                spacing: 10
                                ColorControl {
                                    value: calRow.modelData.color
                                    onEdited: v => CalendarStore.setCalendar(calRow.modelData.id, { color: root.hex(v) })
                                }
                                TextControl {
                                    Layout.fillWidth: true
                                    implicitWidth: 0
                                    value: calRow.modelData.name
                                    onEdited: v => { if (v.trim()) CalendarStore.setCalendar(calRow.modelData.id, { name: v.trim() }) }
                                }
                                Text {
                                    visible: calRow.modelData.readOnly || accPage.a.type === "ics"
                                    text: "󰌾"
                                    color: Colors.fade(0.3)
                                    font.pixelSize: 12
                                    font.family: Properties.fontFamily
                                }
                                IconButton {
                                    implicitWidth: 30; implicitHeight: 30; iconSize: 13
                                    icon: calRow.modelData.notify === false ? "󰂛" : "󰂚"
                                    active: calRow.modelData.notify !== false
                                    textColor: calRow.modelData.notify === false ? Colors.fade(0.4) : Properties.color
                                    tooltip: calRow.modelData.notify === false ? "Reminders off for this calendar" : "Reminders on"
                                    onClicked: CalendarStore.setCalendar(calRow.modelData.id, { notify: calRow.modelData.notify === false })
                                }
                                ToggleSwitch {
                                    checked: calRow.modelData.enabled
                                    onToggled: v => CalendarStore.setCalendar(calRow.modelData.id, { enabled: v })
                                }
                            }
                        }
                    }
                }
            }
            Hint { text: "Color square: palette, opacity and hex  ·  󰂚 reminders from that calendar  ·  switch: show / hide" }

            SectionTitle { text: "Remove" }
            Card {
                PlainRow {
                    Layout.fillWidth: true
                    label: accArm.armed !== "" ? "Click again to remove" : "Remove this account"
                    desc: accPage.a.type === "local" ? "Its events are deleted from this computer" : "Its login leaves the keyring; the events stay on the server"
                    ActionButton {
                        icon: "󰆴"
                        text: accArm.armed !== "" ? "Really remove" : "Remove…"
                        textColor: Colors.red
                        primary: accArm.armed !== ""
                        onClicked: if (accArm.confirm("remove")) CalendarStore.removeAccount(accPage.a.id)
                    }
                }
            }
        }
    }
}
