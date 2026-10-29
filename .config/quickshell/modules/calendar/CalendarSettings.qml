import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "../settings"

// Calendar app settings: reminders, view, and per account / calendar
// options (color, name, shown, reminders). The general options are the same
// keys as the settings app's Calendar page (Settings.calendar), so both stay
// in sync.
Modal {
    id: root

    cardWidth: 640

    function opt(key, def) { return Settings.calendar[key] ?? def }
    function setOpt(key, v) { Settings.set("calendar", key, v) }

    function hex(c) {
        const h = x => Math.round(x * 255).toString(16).padStart(2, "0")
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }

    ColumnLayout {
        width: parent.width
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                text: "󰒓"
                color: Colors.color6
                font.pixelSize: 20
                font.family: Properties.fontFamily
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: "Calendar settings"
                    color: Colors.ink
                    font.pixelSize: 17
                    font.bold: true
                    font.family: Properties.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    text: "Changes apply right away"
                    color: Colors.fade(0.5)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                }
            }
            IconButton {
                implicitWidth: 30; implicitHeight: 30
                icon: "󰅖"
                onClicked: root.close()
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(body.implicitHeight, root.height - 160)
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: body
                width: parent.width
                spacing: 8

                // ── Reminders ────────────────────────────────────────────────
                SectionTitle { text: "Reminders" }
                Card {
                    PlainRow {
                        Layout.fillWidth: true
                        label: "Reminders"
                        desc: "Notification before an event starts"
                        ToggleSwitch {
                            checked: root.opt("reminders", true)
                            onToggled: v => root.setOpt("reminders", v)
                        }
                    }
                    Divider {}
                    PlainRow {
                        Layout.fillWidth: true
                        enabled: root.opt("reminders", true)
                        opacity: enabled ? 1 : 0.4
                        label: "Default reminder"
                        desc: "Minutes before, for events without their own"
                        ChoiceControl {
                            options: ["off", "5", "10", "15", "30", "60"]
                            value: root.opt("defaultReminder", "10")
                            onEdited: v => root.setOpt("defaultReminder", v)
                        }
                    }
                    Divider {}
                    PlainRow {
                        Layout.fillWidth: true
                        enabled: root.opt("reminders", true)
                        opacity: enabled ? 1 : 0.4
                        label: "All-day events"
                        desc: "Remind at 09:00 on the day"
                        ToggleSwitch {
                            checked: root.opt("allDayReminder", false)
                            onToggled: v => root.setOpt("allDayReminder", v)
                        }
                    }
                    Divider {}
                    PlainRow {
                        Layout.fillWidth: true
                        enabled: root.opt("reminders", true)
                        opacity: enabled ? 1 : 0.4
                        label: "When it starts"
                        desc: "Another notification at the start time"
                        ToggleSwitch {
                            checked: root.opt("startReminder", false)
                            onToggled: v => root.setOpt("startReminder", v)
                        }
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
                                implicitWidth: 26; implicitHeight: 26
                                iconSize: 11
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

                // ── View ─────────────────────────────────────────────────────
                SectionTitle { text: "View" }
                Card {
                    PlainRow {
                        Layout.fillWidth: true
                        label: "Open in"
                        desc: "View when the app starts"
                        ChoiceControl {
                            options: ["day", "week", "month", "agenda"]
                            value: root.opt("defaultView", "month")
                            onEdited: v => root.setOpt("defaultView", v)
                        }
                    }
                    Divider {}
                    PlainRow {
                        Layout.fillWidth: true
                        label: "Day starts at"
                        desc: "Where the day and week views scroll to"
                        ChoiceControl {
                            options: ["6", "7", "8", "9", "10"]
                            value: root.opt("dayStart", "7")
                            onEdited: v => root.setOpt("dayStart", v)
                        }
                    }
                    Divider {}
                    PlainRow {
                        Layout.fillWidth: true
                        label: "Zoom"
                        desc: "Hour height in the day and week views, %  (also Ctrl + wheel)"
                        ChoiceControl {
                            options: CalendarStore.zoomSteps.map(String)
                            value: String(CalendarStore.zoom)
                            onEdited: v => root.setOpt("zoom", v)
                        }
                    }
                    Divider {}
                    PlainRow {
                        Layout.fillWidth: true
                        label: "Week numbers"
                        ToggleSwitch {
                            checked: root.opt("weekNumbers", true)
                            onToggled: v => root.setOpt("weekNumbers", v)
                        }
                    }
                    Divider {}
                    PlainRow {
                        Layout.fillWidth: true
                        label: "Sync every"
                        desc: "Minutes, also in the background for the dashboard and reminders"
                        ChoiceControl {
                            options: ["5", "15", "30", "60"]
                            value: root.opt("syncMinutes", "15")
                            onEdited: v => root.setOpt("syncMinutes", v)
                        }
                    }
                    Divider {}
                    PlainRow {
                        Layout.fillWidth: true
                        label: "Save moves after"
                        desc: "Seconds after the last drag in the day / week view; moves made meanwhile are saved together"
                        ChoiceControl {
                            options: ["0", "5", "10", "30", "60"]
                            value: root.opt("moveDelay", "10")
                            onEdited: v => root.setOpt("moveDelay", v)
                        }
                    }
                }

                // ── Accounts & calendars ─────────────────────────────────────
                SectionTitle { text: "Calendars" }
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    visible: CalendarStore.accounts.length === 0
                    text: "No accounts yet — add one with ＋ in the sidebar."
                    color: Colors.fade(0.45)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                }

                Repeater {
                    model: CalendarStore.accounts
                    Card {
                        id: accCard
                        required property var modelData
                        ConfirmArm { id: accArm }
                        readonly property bool armed: accArm.armed !== ""

                        // account header: name + kind + remove
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 52
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 12
                                spacing: 10
                                Text {
                                    text: accCard.modelData.type === "ics" ? "󰑫" : accCard.modelData.type === "local" ? "󰋜"
                                        : /icloud/i.test(accCard.modelData.url) ? "󰀵" : "󰒍"
                                    color: Colors.color6
                                    font.pixelSize: 16
                                    font.family: Properties.fontFamily
                                }
                                TextControl {
                                    Layout.fillWidth: true
                                    implicitWidth: 0
                                    value: accCard.modelData.name
                                    onEdited: v => { if (v.trim()) CalendarStore.renameAccount(accCard.modelData.id, v.trim()) }
                                }
                                Text {
                                    text: accCard.modelData.type === "ics" ? "Subscription" : accCard.modelData.type === "local" ? "Local"
                                        : /icloud/i.test(accCard.modelData.url) ? "iCloud" : "CalDAV"
                                    color: Colors.fade(0.4)
                                    font.pixelSize: 11
                                    font.family: Properties.fontFamily
                                }
                                ActionButton {
                                    icon: "󰆴"
                                    text: accCard.armed ? "Really remove" : "Remove"
                                    textColor: Colors.red
                                    primary: accCard.armed
                                    onClicked: if (accArm.confirm("remove")) CalendarStore.removeAccount(accCard.modelData.id)
                                }
                            }
                        }

                        Repeater {
                            model: accCard.modelData.calendars
                            ColumnLayout {
                                id: calRow
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 0
                                Divider {}
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: 56
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
                                            visible: calRow.modelData.readOnly || accCard.modelData.type === "ics"
                                            text: "󰌾"
                                            color: Colors.fade(0.3)
                                            font.pixelSize: 12
                                            font.family: Properties.fontFamily
                                        }
                                        // reminders from this calendar
                                        IconButton {
                                            implicitWidth: 30; implicitHeight: 30
                                            iconSize: 13
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
                }

                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.topMargin: 2
                    visible: CalendarStore.accounts.length > 0
                    text: "Color square: palette, opacity and hex  ·  󰂚 reminders from that calendar  ·  switch: show / hide"
                    color: Colors.fade(0.35)
                    font.pixelSize: 10
                    font.family: Properties.fontFamily
                    wrapMode: Text.WordWrap
                }
            }
        }
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
}
