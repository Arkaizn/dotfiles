import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import "../controlcenter"
import "CalUtil.js" as U

// Button showing a date; opens a small month to pick another.
Item {
    id: root

    property date day: new Date()
    signal picked(date day)

    implicitWidth: label.implicitWidth + 50
    implicitHeight: Properties.buttonHeight

    scale: mouse.pressed ? Properties.onPressedButtonScale : mouse.containsMouse ? 1 + (Properties.onEnteredButtonScale - 1) * 0.4 : 1
    Behavior on scale { NumberAnimation { duration: Properties.bDuration; easing.type: Easing.OutCubic } }

    ButtonBackground {
        hovered: mouse.containsMouse || pop.visible
    }
    RowLayout {
        anchors.centerIn: parent
        spacing: 8
        Text {
            text: "󰃭"
            color: Colors.fade(0.6)
            font.pixelSize: 13
            font.family: Properties.fontFamily
        }
        Text {
            id: label
            text: U.fmtShortDate(root.day) + " " + root.day.getFullYear()
            color: Colors.ink
            font.pixelSize: 12
            font.family: Properties.fontFamily
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: pop.visible ? pop.close() : pop.open()
    }

    Popup {
        id: pop
        // the app window's zoom (Ctrl +/−): popups are drawn above it, not inside
        scale: AppZoom.at(parent)
        transformOrigin: Popup.TopLeft
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
        contentItem: MiniMonth {
            selected: root.day
            showDots: false
            onPicked: d => { pop.close(); root.picked(d) }
        }
    }
}
