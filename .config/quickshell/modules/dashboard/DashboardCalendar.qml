import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import qs.components
import qs.services

Item {
    id: root
    anchors.fill: parent

    // ── State ───────────────────────────────────────────────
    readonly property var todayDate: new Date()
    property int curYear:  todayDate.getFullYear()
    property int curMonth: todayDate.getMonth()
    property int selectedDay: -1

    readonly property var monthNames: [
        "January","February","March","April","May","June",
        "July","August","September","October","November","December"
    ]

    // the picked day, or today — DashboardEvents lists its events
    readonly property date selectedDate: selectedDay > 0 ? new Date(curYear, curMonth, selectedDay) : todayDate

    readonly property var calCells:       buildCells()
    readonly property int numWeeks:       calCells.length / 7
    readonly property int todayWeekIndex: getTodayWeekIndex(calCells)

    // ── Helpers ─────────────────────────────────────────────
    function buildCells() {
        let cells       = []
        let firstDow    = new Date(curYear, curMonth, 1).getDay()
        let startDow    = firstDow === 0 ? 6 : firstDow - 1
        let daysInMonth = new Date(curYear, curMonth + 1, 0).getDate()
        let prevDays    = new Date(curYear, curMonth, 0).getDate()
        for (let i = 0; i < startDow; i++)
            cells.push({ d: prevDays - startDow + 1 + i, type: "prev" })
        for (let d = 1; d <= daysInMonth; d++)
            cells.push({ d: d, type: "cur" })
        let nd = 1
        while (cells.length % 7 !== 0)
            cells.push({ d: nd++, type: "next" })
        return cells
    }

    function getTodayWeekIndex(cells) {
        if (curYear !== todayDate.getFullYear() || curMonth !== todayDate.getMonth()) return -1
        for (let i = 0; i < cells.length; i++)
            if (cells[i].type === "cur" && cells[i].d === todayDate.getDate())
                return Math.floor(i / 7)
        return -1
    }

    // ISO 8601 week number — standard UTC-based algorithm:
    // shift to the Thursday of the current week, then count weeks from Jan 1.
    function isoWeek(y, m, d) {
        // Work in UTC to avoid DST shifts
        let date = new Date(Date.UTC(y, m, d))
        // Day of week: Mon=1 … Sun=7
        let dow = date.getUTCDay() || 7
        // Move to the Thursday of this week (ISO weeks are identified by their Thursday)
        date.setUTCDate(date.getUTCDate() + 4 - dow)
        // Jan 1 of the year that Thursday falls in
        let yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
        return Math.ceil((((date - yearStart) / 86400000) + 1) / 7)
    }

    // Resolve a cell to a real Date, accounting for prev/next month overflow
    function cellDate(cell) {
        if (cell.type === "cur")  return new Date(curYear, curMonth,     cell.d)
        if (cell.type === "prev") return new Date(curYear, curMonth - 1, cell.d)
        return                           new Date(curYear, curMonth + 1, cell.d)
    }

    // close the dashboard and run a calendar app IPC call for that day
    function calendarCall(fn, d) {
        const iso = d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0")
        Quickshell.execDetached(["sh", "-c", 'qs ipc call dashboard close; qs ipc call calendar "$1" "$2"', "sh", fn, iso])
    }

    function prevMonth() {
        if (curMonth === 0) { curMonth = 11; curYear-- } else curMonth--
        selectedDay = -1
        slide(-1)
    }

    function nextMonth() {
        if (curMonth === 11) { curMonth = 0; curYear++ } else curMonth++
        selectedDay = -1
        slide(1)
    }

    function goToToday() {
        const dir = Math.sign((todayDate.getFullYear() - curYear) * 12 + todayDate.getMonth() - curMonth)
        curYear     = todayDate.getFullYear()
        curMonth    = todayDate.getMonth()
        selectedDay = -1
        if (dir !== 0) slide(dir)
    }

    // month change: the weeks slide in from that side
    function slide(dir) {
        monthSlide.stop()
        monthSlideX.from = dir * 30
        monthSlide.start()
    }
    ParallelAnimation {
        id: monthSlide
        NumberAnimation { id: monthSlideX; target: weeksShift; property: "x"; to: 0; duration: 260; easing.type: Easing.OutCubic }
        NumberAnimation { target: weeksCol; property: "opacity"; from: 0.15; to: 1; duration: 240; easing.type: Easing.OutCubic }
    }

    // ── Layout ───────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 6

        // ── Header: prev / month+year pill / next ────────────
        RowLayout {
            Layout.fillWidth: true

            // Prev button
            Item {
                id: prevBtn
                width: 28; height: 28
                HoverHandler { 
                    id: prevHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler   { id: prevTap; onTapped: root.prevMonth() }

                Behavior on scale {
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }
                scale: prevTap.pressed ? Properties.onPressedButtonScale : prevHover.hovered ? 1.10 : 1.0

                Rectangle {
                    id: prevBtnBg
                    anchors.fill: parent
                    radius: 6
                    color: "transparent"
                    border.color: Qt.rgba(1,1,1, prevHover.hovered ? 0.28 : 0.14)
                    border.width: 0.5

                    gradient: ButtonGradient {
                            hovered: prevHover.hovered
                        }
                }
                Text {
                    anchors.centerIn: parent
                    text: "‹"
                    font.pixelSize: 20
                    color: prevHover.hovered ? "white" : Qt.rgba(1,1,1,0.6)
                    Behavior on color { ColorAnimation { duration: 100 } }
                }
            }


            // Month + year pill with gradient and hover scale
            Item {
                id: monthPillItem
                height: 26
                // takes the room between the buttons; short month name when narrow
                Layout.fillWidth: true
                Layout.minimumWidth: 60
                Layout.maximumWidth: longName.implicitWidth + 28
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: longName.implicitWidth + 28

                property bool hovered: monthPillHover.hovered

                HoverHandler { 
                    id: monthPillHover 
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler   { id: monthTap; onTapped: root.goToToday() }

                Behavior on scale {
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }
                scale: monthTap.pressed ? Properties.onPressedButtonScale : monthPillItem.hovered ? 1.08 : 1.0

                // Gradient background
                Rectangle {
                    id: monthPillBg
                    anchors.fill: parent
                    radius: 7
                    color: "white"   // filled by the gradient layer below
                    border.color: Qt.rgba(1,1,1, monthPillItem.hovered ? 0.28 : 0.18)
                    border.width: 0.5
                    
                    gradient: ButtonGradient {
                            hovered: monthPillHover.hovered
                        }
                    
                }

                // full-length name, only measured
                Text {
                    id: longName
                    visible: false
                    text: root.monthNames[root.curMonth] + "   " + root.curYear
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                Text {
                    id: monthLabel
                    anchors.centerIn: parent
                    text: (monthPillItem.width < longName.implicitWidth + 28 ? root.monthNames[root.curMonth].slice(0, 3)
                                                                             : root.monthNames[root.curMonth]) + "   " + root.curYear
                    Behavior on text {
                        SequentialAnimation {
                            NumberAnimation { target: monthLabel; property: "opacity"; to: 0; duration: 90 }
                            PropertyAction {}
                            NumberAnimation { target: monthLabel; property: "opacity"; to: 1; duration: 140 }
                        }
                    }
                    color: "white"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
            }

            // Today: back to the current month and today's events
            Item {
                id: todayBtn
                readonly property bool away: root.curYear !== root.todayDate.getFullYear()
                                          || root.curMonth !== root.todayDate.getMonth() || root.selectedDay > 0
                height: 26
                implicitWidth: todayLabel.implicitWidth + 14
                opacity: away ? 1 : 0.45
                scale: todayTap.pressed ? Properties.onPressedButtonScale : todayHover.hovered ? 1.08 : 1.0
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 150 } }

                Rectangle {
                    anchors.fill: parent
                    radius: 7
                    border.color: Qt.rgba(1, 1, 1, todayHover.hovered || todayBtn.away ? 0.28 : 0.18)
                    border.width: 0.5
                    gradient: ButtonGradient { hovered: todayHover.hovered || todayBtn.away }
                }
                Text {
                    id: todayLabel
                    anchors.centerIn: parent
                    text: "Today"
                    color: "white"
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }
                HoverHandler { id: todayHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { id: todayTap; onTapped: root.goToToday() }
            }


            // Next button
            Item {
                id: nextBtn
                width: 28; height: 28
                HoverHandler { 
                    id: nextHover 
                    cursorShape: Qt.PointingHandCursor
                    }
                TapHandler   { id: nextTap; onTapped: root.nextMonth() }

                Behavior on scale {
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }
                scale: nextTap.pressed ? Properties.onPressedButtonScale : nextHover.hovered ? 1.10 : 1.0

                Rectangle {
                    id: nextBtnBg
                    anchors.fill: parent
                    radius: 6
                    color: "transparent"
                    border.color: Qt.rgba(1,1,1, nextHover.hovered ? 0.28 : 0.14)
                    border.width: 0.5
                    gradient: ButtonGradient {
                            hovered: nextHover.hovered
                        }
                }

                Text {
                    anchors.centerIn: parent
                    text: "›"
                    font.pixelSize: 20
                    color: nextHover.hovered ? "white" : Qt.rgba(1,1,1,0.6)
                    Behavior on color { ColorAnimation { duration: 100 } }
                }
            }
        }

        // ── Day-of-week header row ────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 0

            Item { width: 15 }

            Repeater {
                model: ["Mo","Tu","We","Th","Fr","Sa","Su"]
                Text {
                    required property string modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    text: modelData
                    color: index >= 5 ? Qt.rgba(1,1,1,0.2) : Qt.rgba(1,1,1,0.35)
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        // ── Week rows ─────────────────────────────────────────
        ColumnLayout {
            id: weeksCol
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 3
            transform: Translate { id: weeksShift }

            Repeater {
                model: root.numWeeks

                RowLayout {
                    id: weekRow
                    required property int index
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    // Week number — resolved from the actual date of the first cell
                    // so Jan/Dec cross-year edge cases are handled correctly.
                    Text {
                        width: 28
                        Layout.fillHeight: true
                        text: {
                            let c = root.calCells[weekRow.index * 7]
                            let dt = root.cellDate(c)
                            root.isoWeek(dt.getFullYear(), dt.getMonth(), dt.getDate())
                        }
                        color: Qt.rgba(1,1,1,0.2)
                        font.pixelSize: 9
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // 7 day cells
                    Repeater {
                        model: 7

                        Item {
                            id: dayCell
                            required property int index
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            property var  cell:       root.calCells[dayCell.index + weekRow.index * 7]
                            property bool isToday:    cell.type === "cur"
                                && root.curYear  === root.todayDate.getFullYear()
                                && root.curMonth === root.todayDate.getMonth()
                                && cell.d === root.todayDate.getDate()
                            property bool isOther:    cell.type !== "cur"
                            // today can also be selected — clicking it toggles the strong gradient on top
                            property bool isSelected: cell.type === "cur" && cell.d === root.selectedDay

                            HoverHandler { id: dayHover }

                            // Hover scale — snappy spring feel
                            Behavior on scale {
                                NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                            }
                            scale: dayTap.pressed ? Properties.onPressedButtonScale
                                 : (dayHover.hovered && !dayCell.isOther) ? 1.20 : 1.0

                            // ── Today — always-visible soft fill (same feel as hover) ──
                            Rectangle {
                                anchors.centerIn: parent
                                width:  Math.min(parent.width, parent.height) - 4
                                height: width
                                radius: 6
                                visible: dayCell.isToday && !dayCell.isSelected
                                color: Qt.rgba(1,1,1,0.13)
                                border.color: Qt.rgba(1,1,1,0.22)
                                border.width: 0.5
                            }

                            // ── Selected — strong gradient (applies to today too if clicked) ──
                            Rectangle {
                                id: selectedBg
                                anchors.centerIn: parent
                                width:  Math.min(parent.width, parent.height) - 4
                                height: width
                                radius: 6
                                visible: dayCell.isSelected
                                color: Qt.rgba(1, 1, 1, 0.1)
                            }

                            // ── Hover highlight (non-other, non-today, non-selected) ──
                            Rectangle {
                                anchors.centerIn: parent
                                width:  Math.min(parent.width, parent.height) - 4
                                height: width
                                radius: 6
                                visible: dayHover.hovered && !dayCell.isOther
                                         && !dayCell.isToday && !dayCell.isSelected
                                color: Qt.rgba(1,1,1,0.08)
                                Behavior on color { ColorAnimation { duration: 80 } }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: dayCell.cell.d
                                font.pixelSize: 12
                                font.weight: (dayCell.isToday || dayCell.isSelected) ? Font.Medium : Font.Normal
                                color: dayCell.isOther    ? Qt.rgba(1,1,1,0.15)
                                     : dayCell.isSelected ? "white"
                                     : dayCell.isToday    ? "white"
                                     : dayCell.index >= 5 ? Qt.rgba(1,1,1,0.45)     // weekend
                                     : Qt.rgba(1,1,1,0.75)
                            }

                            // calendar app events: a dot per calendar (max 3)
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.verticalCenter
                                anchors.topMargin: 8           // just under the number
                                spacing: 2
                                visible: !dayCell.isOther
                                Repeater {
                                    model: [...new Set(CalendarStore.eventsOn(root.cellDate(dayCell.cell)).map(e => e.calendar))].slice(0, 3)
                                    Rectangle {
                                        required property string modelData
                                        width: 3; height: 3; radius: 1.5
                                        color: CalendarStore.calendarMap[modelData]?.color ?? "white"
                                    }
                                }
                            }

                            // left: show the day's events · double: open it in the
                            // calendar · right: new event on that day
                            TapHandler {
                                id: dayTap
                                enabled: !dayCell.isOther
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onTapped: (point, button) => {
                                    if (button === Qt.RightButton) {
                                        root.selectedDay = dayCell.cell.d
                                        root.calendarCall("newEvent", root.cellDate(dayCell.cell))
                                    } else {
                                        root.selectedDay = (root.selectedDay === dayCell.cell.d) ? -1 : dayCell.cell.d
                                    }
                                }
                                onDoubleTapped: (point, button) => {
                                    if (button === Qt.LeftButton) root.calendarCall("openDate", root.cellDate(dayCell.cell))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
