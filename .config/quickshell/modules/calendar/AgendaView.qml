import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import "CalUtil.js" as U

// List of the next 60 days that have events, grouped by day.
Item {
    id: root

    property date cursor: new Date()
    signal eventClicked(var ev, Item item)
    signal dayOpened(date day)

    readonly property var groups: {
        const out = []
        const first = U.dayStart(cursor)
        for (let i = 0; i < 60; i++) {
            const d = U.addDays(first, i)
            const evs = CalendarStore.eventsOn(d).slice().sort((a, b) =>
                (U.fullDay(b, d) - U.fullDay(a, d)) || a.start - b.start)
            if (evs.length) out.push({ day: d, events: evs })
        }
        return out
    }

    Text {
        anchors.centerIn: parent
        visible: root.groups.length === 0
        text: CalendarStore.accounts.length === 0 ? "Add a calendar account to see your events"
                                                   : "Nothing planned in the next 60 days"
        color: Qt.rgba(1, 1, 1, 0.4)
        font.pixelSize: 13
        font.family: Properties.fontFamily
    }

    ListView {
        id: list
        anchors.fill: parent
        clip: true
        spacing: 10
        boundsBehavior: Flickable.StopAtBounds
        model: root.groups
        rightMargin: 14
        ScrollBar.vertical: CalScrollBar {}
        SmoothWheel { flick: list; step: 140 }

        delegate: RowLayout {
            id: group
            required property var modelData
            readonly property bool today: U.isToday(modelData.day)
            width: ListView.view.width - 14
            spacing: 14

            // date block
            Item {
                Layout.preferredWidth: 74
                Layout.alignment: Qt.AlignTop
                implicitHeight: dateCol.implicitHeight + 8
                Column {
                    id: dateCol
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 6
                    Text {
                        anchors.right: parent.right
                        text: group.modelData.day.getDate()
                        color: group.today ? Colors.color6 : U.weekday(group.modelData.day) >= 5 ? Qt.rgba(1, 1, 1, 0.6) : "white"
                        font.pixelSize: 26
                        font.bold: true
                        font.family: Properties.fontFamily
                    }
                    Text {
                        anchors.right: parent.right
                        text: group.today ? "Today" : U.dayShort[U.weekday(group.modelData.day)] + " · " + U.monthNames[group.modelData.day.getMonth()].slice(0, 3)
                        color: group.today ? Colors.color6 : Qt.rgba(1, 1, 1, 0.5)
                        font.pixelSize: 11
                        font.bold: true
                        font.family: Properties.fontFamily
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.dayOpened(group.modelData.day)
                }
            }

            // events card
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: rows.implicitHeight + 8
                radius: 14
                color: "#27000000"
                border.width: Properties.panelBorderWidth
                border.color: group.today ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.4) : Properties.cardBorder

                Column {
                    id: rows
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 }

                    Repeater {
                        model: group.modelData.events
                        Rectangle {
                            id: row
                            required property var modelData
                            required property int index
                            readonly property color calColor: CalendarStore.calendarMap[modelData.calendar]?.color ?? Colors.color6
                            readonly property bool past: !modelData.allDay && modelData.end < Date.now()
                            width: rows.width
                            height: 50
                            radius: 10
                            color: rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                            opacity: past ? 0.5 : 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 12

                                Text {
                                    Layout.preferredWidth: 118
                                    text: U.fmtRange(row.modelData, group.modelData.day)
                                    color: Qt.rgba(1, 1, 1, 0.7)
                                    font.pixelSize: 11
                                    font.family: Properties.fontFamily
                                    elide: Text.ElideRight
                                }
                                Rectangle {
                                    Layout.preferredWidth: 4
                                    Layout.preferredHeight: 30
                                    radius: 2
                                    color: row.calColor
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text {
                                        Layout.fillWidth: true
                                        text: row.modelData.title
                                        color: "white"
                                        font.pixelSize: 13
                                        font.bold: true
                                        font.family: Properties.fontFamily
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: [row.modelData.location, CalendarStore.calendarMap[row.modelData.calendar]?.name]
                                              .filter(x => x).join("  ·  ")
                                        color: Qt.rgba(1, 1, 1, 0.45)
                                        font.pixelSize: 11
                                        font.family: Properties.fontFamily
                                        elide: Text.ElideRight
                                    }
                                }
                                Text {
                                    visible: row.modelData.recurring
                                    text: "󰑖"
                                    color: Qt.rgba(1, 1, 1, 0.35)
                                    font.pixelSize: 13
                                    font.family: Properties.fontFamily
                                }
                            }
                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.eventClicked(row.modelData, row)
                            }
                        }
                    }
                }
            }
        }
    }
}
