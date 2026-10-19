import QtQuick
import qs.services

// A button on the bar: the glass background (ButtonBackground) that grows on
// hover and shrinks while pressed. Either a text / glyph (`text`) or own
// content (children go on top of the background and scale with it; they're
// decoration only — the button itself takes all clicks and hover).
//
//   BarButton {
//       text: Icons.get("arch") + " 3"
//       buttons: Qt.LeftButton | Qt.RightButton
//       onClicked: mouse => …
//   }
//
// Width: content + Properties.buttonWidth, height: Properties.buttonHeight.
Item {
    id: root

    property string text: ""
    property int iconSize: Properties.iconSize
    property color textColor: Properties.color
    property int buttons: Qt.LeftButton
    property int cursorShape: Qt.PointingHandCursor
    property bool wheelEnabled: false       // emit wheel() (otherwise the wheel passes through)
    // width of own content (children); with `text` the text's width is used
    property real contentWidth: background.implicitWidth

    readonly property bool hovered: mouse.containsMouse
    readonly property bool pressed: mouse.pressed
    default property alias content: face.data

    signal clicked(var mouse)
    signal wheel(var wheel)

    implicitWidth: contentWidth + Properties.buttonWidth
    implicitHeight: Properties.buttonHeight

    // background + content, scaled together
    Item {
        id: face
        anchors.fill: parent
        scale: mouse.pressed ? Properties.onPressedButtonScale
             : mouse.containsMouse ? Properties.onEnteredButtonScale
             : Properties.onExitedButtonScale
        Behavior on scale { NumberAnimation { duration: Properties.bDuration; easing.type: Easing.OutCubic } }

        ButtonBackground {
            id: background
            hovered: root.hovered
            iconText: root.text
            iconSize: root.iconSize
            textColor: root.textColor
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: root.buttons
        cursorShape: root.cursorShape
        onClicked: m => root.clicked(m)
        onWheel: w => { if (root.wheelEnabled) root.wheel(w); else w.accepted = false }
    }
}
