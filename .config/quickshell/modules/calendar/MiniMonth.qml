import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "CalUtil.js" as U

// Small month grid: navigate months, click a day, dots for days with events.
ColumnLayout {
    id: root

    property date selected: new Date()
    property date shownMonth: U.monthStart(selected)
    property bool showDots: true
    signal picked(date day)

    onSelectedChanged: if (!U.sameDay(U.monthStart(selected), shownMonth)) shownMonth = U.monthStart(selected)

    // month changes slide the days in from that side
    property date lastMonth: shownMonth
    onShownMonthChanged: {
        const dir = shownMonth > lastMonth ? 1 : shownMonth < lastMonth ? -1 : 0
        lastMonth = shownMonth
        if (dir === 0) return
        monthSlide.stop()
        monthSlideX.from = dir * 24
        monthSlide.start()
    }
    ParallelAnimation {
        id: monthSlide
        NumberAnimation { id: monthSlideX; target: daysShift; property: "x"; to: 0; duration: Anim.medium; easing.type: Anim.standard }
        NumberAnimation { target: grid; property: "opacity"; from: 0.2; to: 1; duration: Anim.medium; easing.type: Anim.standard }
    }

    spacing: Tokens.space.s6

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.space.s4
        Text {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.space.s4
            text: U.monthNames[root.shownMonth.getMonth()] + " " + root.shownMonth.getFullYear()
            color: Colors.ink
            font.pixelSize: Tokens.font.body
            font.bold: true
            font.family: Properties.fontFamily
        }
        IconButton {
            implicitWidth: 26; implicitHeight: 26
            iconSize: 12
            icon: "󰅁"
            onClicked: root.shownMonth = U.addMonths(root.shownMonth, -1)
        }
        IconButton {
            implicitWidth: 26; implicitHeight: 26
            iconSize: 12
            icon: "󰅂"
            onClicked: root.shownMonth = U.addMonths(root.shownMonth, 1)
        }
    }

    Grid {
        id: grid
        Layout.fillWidth: true
        columns: 7
        transform: Translate { id: daysShift }
        readonly property real cell: width / 7

        Repeater {
            model: U.dayShort
            Text {
                required property string modelData
                required property int index
                width: grid.cell
                height: 20
                horizontalAlignment: Text.AlignHCenter
                text: modelData.slice(0, 2)
                color: index >= 5 ? Colors.fade(0.25) : Colors.fade(0.4)
                font.pixelSize: Tokens.font.micro
                font.bold: true
                font.family: Properties.fontFamily
            }
        }

        Repeater {
            model: 42
            Item {
                id: cell
                required property int index
                readonly property date day: U.addDays(U.weekStart(root.shownMonth), index)
                readonly property bool inMonth: day.getMonth() === root.shownMonth.getMonth()
                readonly property bool isSel: U.sameDay(day, root.selected)
                readonly property bool today: U.isToday(day)
                readonly property var evs: root.showDots ? CalendarStore.eventsOn(day) : []
                width: grid.cell
                height: Math.min(grid.cell, 30)

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height) - 2
                    height: width
                    radius: width / 2
                    color: cell.isSel ? Colors.alpha(Colors.color6, 0.85)
                         : hover.hovered ? Colors.fade(0.08) : "transparent"
                    border.width: cell.today && !cell.isSel ? 1.5 : 0
                    border.color: Colors.color6
                }
                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: cell.evs.length > 0 ? -2 : 0
                    text: cell.day.getDate()
                    color: cell.isSel ? U.onColor(Colors.color6)
                         : cell.inMonth ? (cell.index % 7 >= 5 ? Colors.fade(0.55) : Colors.ink) : Colors.fade(0.3)
                    font.pixelSize: Tokens.font.caption
                    font.bold: cell.today || cell.isSel
                    font.family: Properties.fontFamily
                }
                // up to 3 dots in the calendars' colors
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Tokens.space.s4
                    spacing: Tokens.space.s2
                    Repeater {
                        model: [...new Set(cell.evs.map(e => e.calendar))].slice(0, 3)
                        Rectangle {
                            required property string modelData
                            width: 4; height: 4; radius: Tokens.radius.xs
                            color: cell.isSel ? U.onColor(Colors.color6) : (CalendarStore.calendarMap[modelData]?.color ?? Colors.ink)
                        }
                    }
                }
                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.picked(cell.day) }
            }
        }
    }
}
