import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services

// Sidebar block of one account: header (remove with a second click) and its
// calendars — click to show/hide, click the color square to recolor.
ColumnLayout {
    id: root

    required property var account
    property bool armed: false

    readonly property var errorFor: CalendarStore.errors.filter(e => e.calendar.startsWith(account.id + "|"))

    spacing: 2

    Timer { id: disarm; interval: 3000; onTriggered: root.armed = false }

    Item {
        Layout.fillWidth: true
        implicitHeight: 26
        HoverHandler { id: headHover }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 4
            spacing: 6
            Text {
                text: root.account.type === "ics" ? "󰑫" : root.account.type === "local" ? "󰋜"
                    : root.account.type === "graph" ? "󰴢"
                    : /icloud/i.test(root.account.url) ? "󰀵" : "󰒍"
                color: Colors.fade(0.45)
                font.pixelSize: 12
                font.family: Properties.fontFamily
            }
            Text {
                Layout.fillWidth: true
                text: root.armed ? "Click again to remove" : root.account.name
                color: root.armed ? Colors.red : Colors.fade(0.7)
                font.pixelSize: 11
                font.bold: true
                font.family: Properties.fontFamily
                elide: Text.ElideRight
            }
            Text {
                visible: root.errorFor.length > 0
                text: "󰀦"
                color: Colors.red
                font.pixelSize: 12
                font.family: Properties.fontFamily
                HoverHandler { id: errHover }
                ToolTip.visible: errHover.hovered
                ToolTip.text: root.errorFor.map(e => e.message).join("\n")
            }
            IconButton {
                visible: headHover.hovered || root.armed
                implicitWidth: 22; implicitHeight: 22
                iconSize: 11
                icon: "󰆴"
                tooltip: "Remove account"
                textColor: root.armed ? Colors.red : Properties.color
                onClicked: {
                    if (root.armed) CalendarStore.removeAccount(root.account.id)
                    else { root.armed = true; disarm.restart() }
                }
            }
        }
    }

    Repeater {
        model: root.account.calendars
        Rectangle {
            id: row
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: 30
            radius: Properties.radius
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
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 10

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
                        color: "#1a1a1a"
                        font.pixelSize: 10
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
                        y: swatch.height + 6
                        padding: 10
                        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
                        background: Rectangle {
                            radius: Properties.popupRadius
                            color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.98)
                            border.width: Properties.panelBorderWidth
                            border.color: Properties.panelBorder
                        }
                        contentItem: Grid {
                            columns: 6
                            spacing: 6
                            Repeater {
                                model: CalendarStore.palette.concat([Colors.color1, Colors.color3, Colors.color6, Colors.color8])
                                Rectangle {
                                    required property var modelData
                                    width: 20; height: 20; radius: 6
                                    color: modelData
                                    border.width: 1.5
                                    border.color: Colors.fade(chip.containsMouse ? 0.6 : 0.15)
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
                    font.pixelSize: 12
                    font.family: Properties.fontFamily
                    elide: Text.ElideRight
                }
                Text {
                    visible: row.modelData.readOnly || root.account.type === "ics"
                    text: "󰌾"
                    color: Colors.fade(0.3)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                }
                // recolor
                Text {
                    visible: rowMouse.containsMouse
                    text: "󰏘"
                    color: Colors.fade(0.5)
                    font.pixelSize: 12
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
