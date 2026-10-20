import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib

// Month calendar: today marked, dots on days with events (CalendarStore),
// arrows to page through months (back to this month on the title).
ColumnLayout {
    id: root
    property var opts: ({})
    property bool interactive: true
    property bool active: true

    spacing: 8
    property int offset: 0                       // months from now
    readonly property date month: { const d = Time.date; return new Date(d.getFullYear(), d.getMonth() + offset, 1) }
    readonly property int firstDay: opts.sunday ? 0 : 1
    readonly property string today: Format.day(Time.date)
    // 42 days from the start of the first week
    readonly property var days: {
        const start = new Date(month)
        start.setDate(1 - ((month.getDay() - firstDay + 7) % 7))
        const out = []
        for (let i = 0; i < 42; i++) {
            const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i)
            out.push({ n: d.getDate(), key: Format.day(d), inMonth: d.getMonth() === month.getMonth() })
        }
        return out
    }
    readonly property var names: {
        const all = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
        return all.slice(firstDay).concat(all.slice(0, firstDay))
    }

    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: Qt.formatDate(root.month, "MMMM yyyy")
            color: Colors.ink
            font.pixelSize: 15
            font.bold: true
            font.family: Properties.fontFamily
            MouseArea {
                anchors.fill: parent
                enabled: root.interactive && root.offset !== 0
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.offset = 0
            }
        }
        IconButton {
            visible: root.interactive
            implicitWidth: 24; implicitHeight: 24; iconSize: 12
            icon: "󰅁"
            onClicked: root.offset--
        }
        IconButton {
            visible: root.interactive
            implicitWidth: 24; implicitHeight: 24; iconSize: 12
            icon: "󰅂"
            onClicked: root.offset++
        }
    }

    GridLayout {
        columns: 7
        rowSpacing: 2
        columnSpacing: 2
        Repeater {
            model: root.names
            Text {
                required property string modelData
                Layout.preferredWidth: 30
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                color: Colors.fade(0.45)
                font.pixelSize: 11
                font.family: Properties.fontFamily
            }
        }
        Repeater {
            model: root.days
            Item {
                id: cell
                required property var modelData
                readonly property bool isToday: modelData.key === root.today
                readonly property int events: root.opts.events !== false ? (CalendarStore.byDay[modelData.key] ?? []).length : 0
                Layout.preferredWidth: 30
                Layout.preferredHeight: 28
                Rectangle {
                    anchors.centerIn: parent
                    width: 26; height: 26; radius: 13
                    color: cell.isToday ? Colors.color6 : "transparent"
                }
                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -1
                    text: cell.modelData.n
                    color: cell.isToday ? Colors.background : cell.modelData.inMonth ? Colors.ink : Colors.fade(0.28)
                    font.pixelSize: 12
                    font.bold: cell.isToday
                    font.family: Properties.fontFamily
                }
                Rectangle {
                    visible: cell.events > 0
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 1 }
                    width: 4; height: 4; radius: 2
                    color: cell.isToday ? Colors.ink : Colors.color6
                    opacity: cell.modelData.inMonth ? 1 : 0.4
                }
            }
        }
    }
}
