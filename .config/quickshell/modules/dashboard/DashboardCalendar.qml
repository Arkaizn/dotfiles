import QtQuick
import QtQuick.Layouts
import Quickshell.Io

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

    function isoWeek(y, m, d) {
        let date    = new Date(y, m, d)
        let jan4    = new Date(y, 0, 4)
        let w1start = new Date(jan4)
        w1start.setDate(jan4.getDate() - ((jan4.getDay() + 6) % 7))
        let diff = date - w1start
        return diff < 0 ? 52 : Math.floor(diff / 604800000) + 1
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

        // Header: prev / month+year / next
        RowLayout {
            Layout.fillWidth: true

            Item {
                id: prevBtn
                width: 28; height: 28
                HoverHandler { id: prevHover }
                TapHandler   { onTapped: root.prevMonth() }
                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: prevHover.hovered ? Qt.rgba(1,1,1,0.12) : "transparent"
                    Behavior on color { ColorAnimation { duration: 100 } }
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

            Text {
                text: root.monthNames[root.curMonth] + "   " + root.curYear
                color: "white"
                font.pixelSize: 13
                font.weight: Font.Medium
                Layout.alignment: Qt.AlignVCenter
                TapHandler { onTapped: root.goToToday() }
            }

            Item { Layout.fillWidth: true }

            Item {
                id: nextBtn
                width: 28; height: 28
                HoverHandler { id: nextHover }
                TapHandler   { onTapped: root.nextMonth() }
                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: nextHover.hovered ? Qt.rgba(1,1,1,0.12) : "transparent"
                    Behavior on color { ColorAnimation { duration: 100 } }
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

        // Day-of-week header row — MUST match grid columns exactly
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 0

            // Week-number column spacer — same width as week num cells below
            Item { width: 28 }

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

        // Week rows
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

                    // Week number
                    Text {
                        width: 28
                        Layout.fillHeight: true
                        text: root.isoWeek(
                            root.curYear, root.curMonth,
                            root.calCells[weekRow.index * 7].d
                        )
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
                            property bool isSelected: !isToday && cell.type === "cur" && cell.d === root.selectedDay

                            HoverHandler { id: dayHover }

                            // Today highlight ring
                            Rectangle {
                                anchors.centerIn: parent
                                width:  Math.min(parent.width, parent.height) - 4
                                height: width
                                radius: 6
                                visible: dayCell.isToday
                                color: Qt.rgba(1,1,1,0.18)
                            }

                            // Selected ring
                            Rectangle {
                                anchors.centerIn: parent
                                width:  Math.min(parent.width, parent.height) - 4
                                height: width
                                radius: 6
                                visible: dayCell.isSelected
                                color: "transparent"
                                border.color: Qt.rgba(1,1,1,0.4)
                                border.width: 1
                            }

                            // Hover highlight
                            Rectangle {
                                anchors.centerIn: parent
                                width:  Math.min(parent.width, parent.height) - 4
                                height: width
                                radius: 6
                                visible: dayHover.hovered && !dayCell.isOther && !dayCell.isToday && !dayCell.isSelected
                                color: Qt.rgba(1,1,1,0.08)
                                Behavior on color { ColorAnimation { duration: 80 } }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: dayCell.cell.d
                                font.pixelSize: 12
                                font.weight: dayCell.isToday ? Font.Medium : Font.Normal
                                color: dayCell.isToday    ? "white"
                                     : dayCell.isOther   ? Qt.rgba(1,1,1,0.15)
                                     : dayCell.isSelected ? Qt.rgba(1,1,1,0.9)
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