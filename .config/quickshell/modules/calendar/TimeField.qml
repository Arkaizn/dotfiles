import QtQuick
import QtQuick.Controls
import qs.components
import qs.services
import "CalUtil.js" as U

// Time you can type or pick: "9", "930", "9:30", "9.30", "14h15", "2pm" —
// or the arrow for a list in 15 min steps. Value in minutes since midnight.
Item {
    id: root

    property int minutes: 540
    signal edited(int minutes)

    implicitWidth: 96
    implicitHeight: Properties.buttonHeight

    function fmt(m) { return U.pad(Math.floor(m / 60)) + ":" + U.pad(m % 60) }

    function parse(s) {
        s = s.trim().toLowerCase().replace(/\s+/g, "")
        const pm = /pm$/.test(s), am = /am$/.test(s)
        s = s.replace(/(am|pm)$/, "")
        let h, mi
        let m = /^(\d{1,2})[:.h](\d{1,2})$/.exec(s)
        if (m) { h = +m[1]; mi = +m[2] }
        else if ((m = /^(\d{1,2})$/.exec(s))) { h = +m[1]; mi = 0 }
        else if ((m = /^(\d{1,2})(\d{2})$/.exec(s))) { h = +m[1]; mi = +m[2] }
        else return -1
        if (pm && h < 12) h += 12
        if (am && h === 12) h = 0
        return h < 24 && mi < 60 ? h * 60 + mi : -1
    }

    function commit() {
        const v = parse(field.text)
        if (v >= 0 && v !== root.minutes) root.edited(v)
        field.text = Qt.binding(() => root.fmt(root.minutes))
    }

    SearchField {
        id: field
        anchors.fill: parent
        icon: ""
        clearable: false
        leftPadding: 12
        rightPadding: 30
        text: root.fmt(root.minutes)
        onActiveFocusChanged: if (activeFocus) selectAll()
        onAccepted: { root.commit(); focus = false }
        onEditingFinished: root.commit()
    }

    IconButton {
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: 22; implicitHeight: 22
        iconSize: 11
        icon: "󰅀"
        active: list.visible
        onClicked: list.visible ? list.close() : list.open()
    }

    Popup {
        id: list
        // the app window's zoom (Ctrl +/−): popups are drawn above it, not inside
        scale: AppZoom.at(parent)
        transformOrigin: Popup.TopLeft
        y: root.height + 4
        width: Math.max(root.width, 110)
        height: 240
        padding: 6
        closePolicy: Popup.CloseOnPressOutsideParent | Popup.CloseOnEscape
        onOpened: view.positionViewAtIndex(Math.round(root.minutes / 15), ListView.Center)
        background: Rectangle {
            radius: Properties.radius + 2
            color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.98)
            border.width: Properties.panelBorderWidth
            border.color: Properties.panelBorder
        }
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 } }
        exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 100 } }

        ListView {
            id: view
            anchors.fill: parent
            clip: true
            model: 96
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: CalScrollBar {}
            SmoothWheel { flick: view; step: 84 }
            delegate: Rectangle {
                id: entry
                required property int index
                readonly property int value: index * 15
                readonly property bool selected: value === root.minutes
                width: ListView.view.width - 10
                height: 28
                radius: Properties.radius
                color: hover.hovered ? Colors.fade(0.08) : selected ? Colors.fade(0.05) : "transparent"
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 10
                    text: root.fmt(entry.value)
                    color: entry.selected ? Colors.color6 : entry.value % 60 === 0 ? Colors.ink : Colors.fade(0.6)
                    font.pixelSize: 12
                    font.bold: entry.selected || entry.value % 60 === 0
                    font.family: Properties.fontFamily
                }
                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { list.close(); root.edited(entry.value) } }
            }
        }
    }
}
