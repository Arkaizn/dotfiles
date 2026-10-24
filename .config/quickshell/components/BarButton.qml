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
// Width: content + Properties.buttonWidth, height: PanelGeometry.barButtonHeight
// (Properties.buttonHeight, growing with the bar's thickness). On a left /
// right bar a button wider than the bar is turned by 90° (read top to bottom):
// its own size swaps, the face inside keeps its natural size.
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

    readonly property real naturalWidth: contentWidth + Properties.buttonWidth
    readonly property bool turned: PanelGeometry.barVertical && naturalWidth > PanelGeometry.barButtonHeight + 6
    implicitWidth: turned ? PanelGeometry.barButtonHeight : naturalWidth
    implicitHeight: turned ? naturalWidth : PanelGeometry.barButtonHeight

    // background + content, scaled together (and turned on a vertical bar)
    Item {
        id: face
        width: root.naturalWidth
        height: PanelGeometry.barButtonHeight
        anchors.centerIn: parent
        rotation: root.turned ? 90 : 0
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
        // a quick second click arrives as a double click (and no `clicked`):
        // it's a click too, e.g. closing a popup that's still opening
        onDoubleClicked: m => root.clicked(m)
        onWheel: w => { if (root.wheelEnabled) root.wheel(w); else w.accepted = false }
    }
}
