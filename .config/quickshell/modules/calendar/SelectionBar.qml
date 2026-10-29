import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "../settings"

// Floating bar while several events are selected (Ctrl / Shift + click in
// the views): move them to another calendar, copy them, shift them by a day,
// delete them. Deleting asks once more; with repeating events among them it
// asks "only these occurrences or the whole series".
//   shiftDays(n) / deleteAll(onlyThis) / moveTo(calId) / duplicate() — done by the window
Rectangle {
    id: root

    signal shiftDays(int n)
    signal deleteAll(bool onlyThis)
    signal moveTo(string calId)
    signal duplicate()

    readonly property int count: CalendarStore.selectedCount
    readonly property bool anyRecurring: CalendarStore.selectedEvents.some(e => e.recurring)
    readonly property bool anyReadOnly: CalendarStore.selectedEvents.some(e => CalendarStore.calendarMap[e.calendar]?.readOnly ?? true)
    property bool confirming: false
    onCountChanged: if (count === 0) confirming = false

    readonly property bool shown: count > 0
    visible: opacity > 0
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.94
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }

    implicitWidth: row.implicitWidth + 24
    implicitHeight: Properties.buttonHeight + 20
    radius: height / 2
    color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.97)
    border.width: Properties.panelBorderWidth
    border.color: Colors.color6

    // the bar takes clicks / hover / the wheel (nothing underneath reacts)
    MouseArea { anchors.fill: parent; hoverEnabled: true; onWheel: w => w.accepted = true }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Text {
            Layout.leftMargin: 6
            text: root.count + " selected"
            color: Colors.ink
            font.pixelSize: 12
            font.bold: true
            font.family: Properties.fontFamily
        }
        Rectangle { implicitWidth: 1; implicitHeight: 18; color: Colors.fade(0.12); Layout.leftMargin: 4; Layout.rightMargin: 4 }

        // normal actions
        RowLayout {
            visible: !root.confirming
            spacing: 6
            IconButton { icon: "󰅁"; tooltip: "One day earlier"; interactive: !root.anyReadOnly; onClicked: root.shiftDays(-1) }
            IconButton { icon: "󰅂"; tooltip: "One day later"; interactive: !root.anyReadOnly; onClicked: root.shiftDays(1) }
            DropdownControl {
                implicitWidth: 170
                visible: CalendarStore.writableCalendars.length > 1
                options: [{ label: "Move to…", value: "" }].concat(CalendarStore.writableCalendars.map(c => ({ label: c.name, value: c.id, color: c.color, hint: c.accountName })))
                value: ""
                onEdited: v => { if (v) root.moveTo(v) }
            }
            ActionButton { icon: "󰆏"; text: "Duplicate"; onClicked: root.duplicate() }
            ActionButton { icon: "󰆴"; text: "Delete"; textColor: Colors.red; interactive: !root.anyReadOnly; onClicked: root.confirming = true }
        }
        // delete: once more
        RowLayout {
            visible: root.confirming
            spacing: 6
            Text {
                text: "Delete " + root.count + (root.count === 1 ? " event?" : " events?")
                color: Colors.red
                font.pixelSize: 12
                font.family: Properties.fontFamily
            }
            ActionButton { text: "Cancel"; onClicked: root.confirming = false }
            ActionButton {
                visible: root.anyRecurring
                text: "Only these"
                onClicked: { root.confirming = false; root.deleteAll(true) }
            }
            ActionButton {
                icon: "󰆴"
                text: root.anyRecurring ? "With their series" : "Delete"
                textColor: Colors.red
                onClicked: { root.confirming = false; root.deleteAll(false) }
            }
        }
        IconButton { icon: "󰅖"; tooltip: "Clear the selection  (Esc)"; onClicked: CalendarStore.clearSelection() }
    }
}
