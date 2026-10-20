import QtQuick
import QtQuick.Layouts
import qs.services

// Countdown to a date: "12 days 4 h" until it, "since" after it.
ColumnLayout {
    id: root
    property var opts: ({})
    property bool interactive: true
    property bool active: true

    spacing: 2
    // "YYYY-MM-DD" or "YYYY-MM-DD HH:MM" (local time)
    readonly property var target: {
        const m = /^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{1,2}):(\d{2}))?$/.exec((opts.when ?? "").trim())
        return m ? new Date(+m[1], +m[2] - 1, +m[3], +(m[4] ?? 0), +(m[5] ?? 0)) : null
    }
    readonly property real diff: target ? target.getTime() - Time.date.getTime() : 0
    readonly property real remain: Math.abs(diff)
    readonly property int days: Math.floor(remain / 86400000)
    readonly property int hours: Math.floor(remain % 86400000 / 3600000)
    readonly property int mins: Math.floor(remain % 3600000 / 60000)

    Text {
        Layout.alignment: Qt.AlignHCenter
        text: root.opts.title ?? ""
        visible: text !== ""
        color: Colors.fade(0.7)
        font.pixelSize: 14
        font.family: Properties.fontFamily
    }
    Text {
        Layout.alignment: Qt.AlignHCenter
        text: !root.target ? "Set a date" : root.days > 0 ? root.days + (root.days === 1 ? " day" : " days") : root.hours + " h " + root.mins + " min"
        color: Colors.ink
        font.pixelSize: 40
        font.bold: true
        font.family: Properties.fontFamily
    }
    Text {
        Layout.alignment: Qt.AlignHCenter
        visible: root.target !== null
        text: root.target ? (root.days > 0 ? root.hours + " h " + root.mins + " min " : "") + (root.diff >= 0 ? "to go" : "ago") + "  ·  " + Qt.formatDateTime(root.target, "d MMM yyyy") : ""
        color: Colors.fade(0.55)
        font.pixelSize: 12
        font.family: Properties.fontFamily
    }
}
