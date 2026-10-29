import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "../settings"
import "CalUtil.js" as U

// A repeating event was dragged: move only this occurrence or the whole
// series? (A series can't change its day here, only its time.)
Modal {
    id: root

    cardWidth: 460

    property var ev: null
    property double newStart: 0
    property double newEnd: 0
    // several selected events moved together: [{ ev, start, end }] besides ev
    // (the answer counts for every repeating one among them)
    property var others: []
    readonly property bool dayChanged: ev !== null && !U.sameDay(new Date(newStart), new Date(ev.start))

    function ask(e, s, en, more) {
        ev = e
        newStart = s
        newEnd = en
        others = more ?? []
        open()
    }

    function pick(scope) {
        CalendarStore.moveEvent(ev, newStart, newEnd, scope)
        for (const o of others) CalendarStore.moveEvent(o.ev, o.start, o.end, o.ev.recurring ? scope : "all")
        others = []
        close()
    }

    ColumnLayout {
        width: parent.width
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                text: "󰑖"
                color: Colors.color6
                font.pixelSize: 20
                font.family: Properties.fontFamily
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: root.others.length ? "Move " + (root.others.length + 1) + " events, some repeating" : "Move a repeating event"
                    color: Colors.ink
                    font.pixelSize: 16
                    font.bold: true
                    font.family: Properties.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    text: root.ev ? root.ev.title + "  →  " + U.fmtShortDate(new Date(root.newStart)) + ", "
                                    + U.fmtTime(root.newStart) + " – " + U.fmtTime(root.newEnd) : ""
                    color: Colors.fade(0.55)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                    elide: Text.ElideRight
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.dayChanged
            text: "A whole series can only change its time here, not its day — moving to another day works for this event only."
            color: Colors.fade(0.5)
            font.pixelSize: 11
            font.family: Properties.fontFamily
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            ActionButton { text: "Cancel"; onClicked: root.close() }
            Item { Layout.fillWidth: true }
            ActionButton { text: root.others.length ? "Only these" : "Only this event"; primary: root.dayChanged; onClicked: root.pick("this") }
            ActionButton {
                text: root.others.length ? "Whole series" : "All events"
                primary: !root.dayChanged
                interactive: !root.dayChanged
                onClicked: root.pick("all")
            }
        }
    }
}
