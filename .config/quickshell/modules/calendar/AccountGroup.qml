import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services

// Sidebar block of one account: header (switch the whole account off / on,
// look for new calendars, remove with a second click) and its calendars —
// click to show/hide, click the color square to recolor.
ColumnLayout {
    id: root

    required property var account
    ConfirmArm { id: arm }
    readonly property bool armed: arm.armed !== ""
    readonly property bool on: account.enabled !== false
    readonly property bool canList: account.type === "caldav" || account.type === "graph"
    property bool listing: false

    readonly property var errorFor: CalendarStore.errors.filter(e => e.calendar.startsWith(account.id + "|"))

    spacing: Tokens.space.s2


    Item {
        Layout.fillWidth: true
        implicitHeight: 26
        HoverHandler { id: headHover }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.space.s4
            spacing: Tokens.space.s6
            Text {
                text: root.account.type === "ics" ? "󰑫" : root.account.type === "local" ? "󰋜"
                    : root.account.type === "graph" ? "󰴢"
                    : /icloud/i.test(root.account.url) ? "󰀵" : "󰒍"
                color: Colors.fade(root.on ? 0.45 : 0.25)
                font.pixelSize: Tokens.font.small
                font.family: Properties.fontFamily
            }
            Text {
                Layout.fillWidth: true
                text: root.armed ? "Click again to remove" : root.account.name
                color: root.armed ? Colors.red : Colors.fade(root.on ? 0.7 : 0.35)
                font.pixelSize: Tokens.font.caption
                font.bold: true
                font.family: Properties.fontFamily
                elide: Text.ElideRight
            }
            Text {
                visible: root.errorFor.length > 0
                text: "󰀦"
                color: Colors.red
                font.pixelSize: Tokens.font.small
                font.family: Properties.fontFamily
                HoverHandler { id: errHover }
                HoverTip { shown: errHover.hovered; text: root.errorFor.map(e => e.message).join("\n") }
            }
            // calendars made on another device show up by themselves (hourly); this checks now
            IconButton {
                visible: root.canList && root.on && (headHover.hovered || root.listing) && !root.armed
                implicitWidth: 22; implicitHeight: 22
                iconSize: 11
                icon: "󰑓"
                tooltip: "Look for new calendars"
                busy: root.listing
                onClicked: {
                    root.listing = true
                    CalendarStore.refreshCalendars(root.account.id, () => root.listing = false)
                }
            }
            IconButton {
                visible: (headHover.hovered || !root.on) && !root.armed
                implicitWidth: 22; implicitHeight: 22
                iconSize: 11
                icon: "󰐥"
                tooltip: root.on ? "Switch this account off (stops syncing, keeps the login)" : "Switch this account on"
                textColor: root.on ? Properties.color : Colors.fade(0.35)
                onClicked: CalendarStore.setAccount(root.account.id, { enabled: !root.on })
            }
            IconButton {
                visible: headHover.hovered || root.armed
                implicitWidth: 22; implicitHeight: 22
                iconSize: 11
                icon: "󰆴"
                tooltip: "Remove account"
                textColor: root.armed ? Colors.red : Properties.color
                onClicked: if (arm.confirm("remove")) CalendarStore.removeAccount(root.account.id)
            }
        }
    }

    Text {
        visible: !root.on
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.space.s24
        Layout.bottomMargin: Tokens.space.s2
        text: "Off — not syncing · " + root.account.calendars.length + (root.account.calendars.length === 1 ? " calendar" : " calendars")
        color: Colors.fade(0.3)
        font.pixelSize: Tokens.font.micro
        font.family: Properties.fontFamily
        elide: Text.ElideRight
    }

    Repeater {
        model: root.on ? root.account.calendars : []
        Rectangle {
            id: row
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: 30
            radius: Tokens.radius.md
            color: rowMouse.containsMouse ? Colors.fade(0.06) : "transparent"

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: CalendarStore.setCalendar(row.modelData.id, { enabled: !row.modelData.enabled })
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.space.s8
                anchors.rightMargin: Tokens.space.s8
                spacing: Tokens.space.s10

                // color square = visibility checkbox; click it to recolor
                Rectangle {
                    id: swatch
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: 16
                    radius: 5
                    color: row.modelData.enabled ? row.modelData.color : "transparent"
                    border.width: 2
                    border.color: row.modelData.color
                    Text {
                        anchors.centerIn: parent
                        visible: row.modelData.enabled
                        text: "󰄬"
                        color: Colors.neutral(0.1)
                        font.pixelSize: Tokens.font.micro
                        font.bold: true
                        font.family: Properties.fontFamily
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) colorMenu.open()
                            else CalendarStore.setCalendar(row.modelData.id, { enabled: !row.modelData.enabled })
                        }
                        onPressAndHold: colorMenu.open()
                    }

                    Popup {
                        id: colorMenu
                        // the app window's zoom (Ctrl +/−): popups are drawn above it, not inside
                        scale: AppZoom.at(parent)
                        transformOrigin: Popup.TopLeft
                        y: swatch.height + 6
                        padding: Tokens.space.s10
                        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
                        background: PopoverBackground {}
                        contentItem: Grid {
                            columns: 6
                            spacing: Tokens.space.s6
                            Repeater {
                                model: CalendarStore.palette.concat([Colors.color1, Colors.color3, Colors.color6, Colors.color8])
                                Rectangle {
                                    required property var modelData
                                    width: 20; height: 20; radius: 6
                                    color: modelData
                                    border.width: 1.5
                                    border.color: Colors.line(chip.containsMouse ? 0.6 : 0.15)
                                    MouseArea {
                                        id: chip
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            colorMenu.close()
                                            CalendarStore.setCalendar(row.modelData.id, { color: String(parent.color) })
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: row.modelData.name
                    color: row.modelData.enabled ? Colors.ink : Colors.fade(0.4)
                    font.pixelSize: Tokens.font.small
                    font.family: Properties.fontFamily
                    elide: Text.ElideRight
                }
                Text {
                    visible: row.modelData.readOnly || root.account.type === "ics"
                    text: "󰌾"
                    color: Colors.fade(0.3)
                    font.pixelSize: Tokens.font.caption
                    font.family: Properties.fontFamily
                }
                // recolor
                Text {
                    visible: rowMouse.containsMouse
                    text: "󰏘"
                    color: Colors.fade(0.5)
                    font.pixelSize: Tokens.font.small
                    font.family: Properties.fontFamily
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: colorMenu.open()
                    }
                }
            }
        }
    }
}
