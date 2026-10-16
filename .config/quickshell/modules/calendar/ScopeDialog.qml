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
    readonly property bool dayChanged: ev !== null && !U.sameDay(new Date(newStart), new Date(ev.start))

    function ask(e, s, en) {
        ev = e
        newStart = s
        newEnd = en
        open()
    }

    function pick(scope) {
        CalendarStore.moveEvent(ev, newStart, newEnd, scope)
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
                    text: "Move a repeating event"
                    color: "white"
                    font.pixelSize: 16
                    font.bold: true
                    font.family: Properties.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    text: root.ev ? root.ev.title + "  →  " + U.fmtShortDate(new Date(root.newStart)) + ", "
                                    + U.fmtTime(root.newStart) + " – " + U.fmtTime(root.newEnd) : ""
                    color: Qt.rgba(1, 1, 1, 0.55)
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
            color: Qt.rgba(1, 1, 1, 0.5)
            font.pixelSize: 11
            font.family: Properties.fontFamily
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            ActionButton { text: "Cancel"; onClicked: root.close() }
            Item { Layout.fillWidth: true }
            ActionButton { text: "Only this event"; primary: root.dayChanged; onClicked: root.pick("this") }
            ActionButton {
                text: "All events"
                primary: !root.dayChanged
                interactive: !root.dayChanged
                onClicked: root.pick("all")
            }
        }
    }
}
