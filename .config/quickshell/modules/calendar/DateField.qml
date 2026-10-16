import QtQuick
import QtQuick.Controls
import qs.components
import qs.services
import "CalUtil.js" as U

// Date you can type or pick: "20.10.2026", "20.10.", "2026-10-20", "today",
// "tomorrow", "+3", "fri"… — or the calendar button for a small month.
// Unreadable input goes back to the last date.
Item {
    id: root

    property date day: new Date()
    signal picked(date day)

    implicitWidth: 168
    implicitHeight: Properties.buttonHeight

    function fmt(d) { return U.pad(d.getDate()) + "." + U.pad(d.getMonth() + 1) + "." + d.getFullYear() }

    function parse(s) {
        s = s.trim().toLowerCase().replace(/^(mon|tue|wed|thu|fri|sat|sun)[a-z]*\s+(?=\d)/, "")
        const today = U.dayStart(new Date())
        if (s === "" ) return null
        if (s === "today" || s === "heute") return today
        if (s === "tomorrow" || s === "morgen") return U.addDays(today, 1)
        let m = /^\+(\d+)$/.exec(s)
        if (m) return U.addDays(today, +m[1])
        const names = ["mo", "tu", "we", "th", "fr", "sa", "su"]
        const wi = names.findIndex(n => s.startsWith(n) && /^[a-z]+$/.test(s))
        if (wi >= 0) return U.addDays(today, ((wi - U.weekday(today)) + 7) % 7 || 7)
        m = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(s)
        if (m) return valid(+m[1], +m[2], +m[3])
        m = /^(\d{1,2})[./](\d{1,2})[./]?(\d{2,4})?$/.exec(s)
        if (m) {
            let y = m[3] ? +m[3] : root.day.getFullYear()
            if (m[3] && m[3].length === 2) y += 2000
            return valid(y, +m[2], +m[1])
        }
        return null
    }
    function valid(y, mo, d) {
        const x = new Date(y, mo - 1, d)
        return x.getMonth() === mo - 1 && x.getDate() === d ? x : null
    }

    function commit() {
        const d = parse(field.text)
        if (d && !U.sameDay(d, root.day)) root.picked(d)
        field.text = Qt.binding(() => field.activeFocus ? root.fmt(root.day) : U.dayShort[U.weekday(root.day)] + "  " + root.fmt(root.day))
    }

    SearchField {
        id: field
        anchors.fill: parent
        icon: ""
        clearable: false
        leftPadding: 12
        rightPadding: 36
        // weekday shown while not typing
        text: activeFocus ? root.fmt(root.day) : U.dayShort[U.weekday(root.day)] + "  " + root.fmt(root.day)
        onActiveFocusChanged: if (activeFocus) selectAll()
        onAccepted: { root.commit(); focus = false }
        onEditingFinished: root.commit()
    }

    IconButton {
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: 26; implicitHeight: 26
        iconSize: 12
        icon: "󰃭"
        active: pop.visible
        onClicked: pop.visible ? pop.close() : pop.open()
    }

    Popup {
        id: pop
        y: root.height + 6
        x: Math.min(0, root.width - width)
        width: 250
        padding: 12
        closePolicy: Popup.CloseOnPressOutsideParent | Popup.CloseOnEscape
        background: Rectangle {
            radius: Properties.popupRadius
            color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.98)
            border.width: Properties.panelBorderWidth
            border.color: Properties.panelBorder
        }
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 } NumberAnimation { property: "scale"; from: 0.95; to: 1; duration: 160; easing.type: Easing.OutCubic } }
        exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 100 } }
        contentItem: MiniMonth {
            selected: root.day
            showDots: false
            onPicked: d => { pop.close(); root.picked(d) }
        }
    }
}
