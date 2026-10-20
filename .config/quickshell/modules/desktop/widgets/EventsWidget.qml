import QtQuick
import QtQuick.Layouts
import qs.services
import qs.services.lib

// The next events of your calendars (CalendarStore), with their calendar's color.
ColumnLayout {
    id: root
    property var opts: ({})
    property bool interactive: true
    property bool active: true

    spacing: 8
    implicitWidth: 280

    readonly property var upcoming: {
        const now = Time.date.getTime(), until = now + (opts.days ?? 14) * 86400000
        return CalendarStore.visibleEvents.filter(e => e.end > now && e.start < until)
            .sort((a, b) => a.start - b.start).slice(0, opts.count ?? 5)
    }
    function when(e) {
        const d = new Date(e.start), today = Format.day(Time.date)
        const tomorrow = Format.day(new Date(Time.date.getFullYear(), Time.date.getMonth(), Time.date.getDate() + 1))
        const day = Format.day(d) === today ? "Today" : Format.day(d) === tomorrow ? "Tomorrow" : Qt.formatDate(d, "ddd d MMM")
        return day + (e.allDay ? "" : "  " + Format.hm(e.start))
    }

    Text {
        text: "Upcoming"
        color: Colors.ink
        font.pixelSize: 15
        font.bold: true
        font.family: Properties.fontFamily
    }
    Text {
        visible: root.upcoming.length === 0
        text: "Nothing in the next " + (root.opts.days ?? 14) + " days"
        color: Colors.fade(0.5)
        font.pixelSize: 12
        font.family: Properties.fontFamily
    }
    Repeater {
        model: root.upcoming
        RowLayout {
            id: ev
            required property var modelData
            Layout.fillWidth: true
            spacing: 10
            Rectangle {
                Layout.fillHeight: true
                implicitWidth: 3; radius: 2
                color: CalendarStore.calendarMap[ev.modelData.calendar]?.color ?? Colors.color6
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text { Layout.fillWidth: true; text: ev.modelData.title; color: Colors.ink; font.pixelSize: 13; elide: Text.ElideRight; font.family: Properties.fontFamily }
                Text { text: root.when(ev.modelData); color: Colors.fade(0.55); font.pixelSize: 11; font.family: Properties.fontFamily }
            }
        }
    }
}
