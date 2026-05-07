import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import qs.components

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

    function prevMonth() {
        if (curMonth === 0) { curMonth = 11; curYear-- } else curMonth--
        selectedDay = -1
    }

    function nextMonth() {
        if (curMonth === 11) { curMonth = 0; curYear++ } else curMonth++
        selectedDay = -1
    }

    function goToToday() {
        curYear     = todayDate.getFullYear()
        curMonth    = todayDate.getMonth()
        selectedDay = -1
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
                TapHandler   { onTapped: root.prevMonth() }

                Behavior on scale {
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }
                scale: prevHover.hovered ? 1.10 : 1.0

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

            Item { Layout.fillWidth: true }

            // Month + year pill with gradient and hover scale
            Item {
                id: monthPillItem
                height: 26
                // Measure the text so the pill is always snug
                implicitWidth: monthLabel.implicitWidth + 28

                property bool hovered: monthPillHover.hovered

                HoverHandler { 
                    id: monthPillHover 
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler   { onTapped: root.goToToday() }

                Behavior on scale {
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }
                scale: monthPillItem.hovered ? 1.08 : 1.0

                // Gradient background
                Rectangle {
                    id: monthPillBg
                    anchors.fill: parent
                    radius: 7
                    color: "transparent"   // filled by the gradient layer below
                    border.color: Qt.rgba(1,1,1, monthPillItem.hovered ? 0.28 : 0.18)
                    border.width: 0.5
                    
                    gradient: ButtonGradient {
                            hovered: monthPillHover.hovered
                        }
                    
                }

                Text {
                    id: monthLabel
                    anchors.centerIn: parent
                    text: root.monthNames[root.curMonth] + "   " + root.curYear
                    color: "white"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
            }

            Item { Layout.fillWidth: true }

            // Next button
            Item {
                id: nextBtn
                width: 28; height: 28
                HoverHandler { 
                    id: nextHover 
                    cursorShape: Qt.PointingHandCursor
                    }
                TapHandler   { onTapped: root.nextMonth() }

                Behavior on scale {
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }
                scale: nextHover.hovered ? 1.10 : 1.0

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

            Item { width: 28 }   // spacer matching week-number column

            Repeater {
                model: ["Mo","Tu","We","Th","Fr","Sa","Su"]
                Text {
                    Layout.fillWidth: true
                    text: modelData
                    color: Qt.rgba(1,1,1,0.35)
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        // ── Week rows ─────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 3

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
                            scale: (dayHover.hovered && !dayCell.isOther) ? 1.20 : 1.0

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
                                     : Qt.rgba(1,1,1,0.75)
                            }

                            TapHandler {
                                enabled: !dayCell.isOther
                                acceptedButtons: Qt.LeftButton
                                onTapped: {
                                    root.selectedDay = (root.selectedDay === dayCell.cell.d)
                                        ? -1
                                        : dayCell.cell.d
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
