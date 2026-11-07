import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// One place in the sidebar: glyph, name, for drives a free-space bar. Looks
// like Mail's folder rows: the current one carries the sliding highlight
// (`glow`, owned by Places), hover shows a lighter version of it.
//   PlaceEntry { icon; label; current; glow: pick; used: 0.4; onClicked: …; onContext: (x, y) => …
//                dropPath: where files dropped on it go ("" = none); onDropped: drop => …
//                actionIcon / actionTip: a small button at the end (eject); onAction
//                dragKind / dragId: it can be dragged up / down (Places decides where it lands:
//                  dragMoved(sceneY) while moving, dragDone(sceneY) on release)
//                indent: under a group · dot: a group's colour · fold: "" | "open" | "closed" (a group header)
//                iconSource: a picture instead of the glyph (the icon theme) · tint: the glyph's colour }
Pressable {
    id: e

    property string icon: ""
    property string label: ""
    property bool current: false
    property bool muted: false            // a bookmark whose folder is gone, a place that can't open yet
    property real used: -1                // 0…1: how full the drive is (a bar under the name), -1 none
    property Item glow: null
    signal context(real x, real y)        // right-click, where in the row
    property string dropPath: ""
    signal dropped(var drop)
    property string dragKind: ""
    property string dragId: ""
    property bool indent: false
    property color dot: "transparent"
    property string fold: ""
    property string iconSource: ""
    property color tint: "transparent"    // the glyph in this colour (a bookmark in a group: the group's)
    property bool dropRing: false         // something dragged here would go in (a group header)
    signal dragMoved(real sceneY)
    signal dragDone(real sceneY)
    property string actionIcon: ""
    property string actionTip: ""
    signal action()

    onCurrentChanged: if (current && glow) glow.target = e
    Component.onCompleted: if (current && glow) glow.target = e

    Layout.fillWidth: true
    implicitHeight: Tokens.size.control + (used >= 0 ? Tokens.space.s6 : 0)
    focusRadius: Tokens.radius.lg
    accessibleRole: Accessible.ListItem
    accessibleName: label
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onRightClicked: context(where.point.position.x, where.point.position.y)
    HoverHandler { id: where }

    // dragging: lifted, following the pointer; Places shows where it would land
    property real shift: 0
    transform: Translate { y: e.shift }
    z: lift.active ? 5 : 0
    opacity: lift.active ? 0.85 : 1
    DragHandler {
        id: lift
        enabled: e.dragKind !== ""
        target: null
        xAxis.enabled: false
        onTranslationChanged: if (active) { e.shift = translation.y; e.dragMoved(centroid.scenePosition.y) }
        onActiveChanged: if (!active) { const y = centroid.scenePosition.y; e.shift = 0; e.dragDone(y) }
    }

    DropArea {
        id: dropHere
        anchors.fill: parent
        enabled: e.dropPath !== ""
        onEntered: drag => drag.accepted = drag.hasUrls
        onDropped: drop => e.dropped(drop)
    }
    // a drag over it: the accent ring says "it goes in here"
    Rectangle {
        z: -1
        anchors.fill: parent
        radius: Tokens.radius.lg
        color: Colors.alpha(Colors.accent, 0.14)
        border.width: Tokens.border.selected
        border.color: Colors.accent
        opacity: dropHere.containsDrag || e.dropRing ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Anim.fast } }
    }

    // hover: a lighter version of the highlight
    Rectangle {
        z: -2
        anchors.fill: parent
        radius: Tokens.radius.lg
        border.width: Tokens.border.control
        border.color: Colors.fade(0.14)
        gradient: ButtonGradient { hovered: false }
        opacity: e.hovered && !e.current ? 0.6 : 0
        Behavior on opacity { NumberAnimation { duration: Anim.fast } }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.space.s8 + (e.indent ? Tokens.space.s16 : 0)
        anchors.rightMargin: Tokens.space.s8
        spacing: Tokens.space.s8
        // a group: its colour
        Rectangle {
            visible: e.dot.a > 0
            implicitWidth: Tokens.space.s10
            implicitHeight: Tokens.space.s10
            radius: width / 2
            color: e.dot
        }
        Image {
            visible: e.iconSource !== "" && e.dot.a === 0
            Layout.preferredWidth: Tokens.font.label + Tokens.space.s2
            Layout.preferredHeight: Tokens.font.label + Tokens.space.s2
            sourceSize: Qt.size((Tokens.font.label + Tokens.space.s2) * 2, (Tokens.font.label + Tokens.space.s2) * 2)
            source: e.iconSource
        }
        Text {
            visible: e.iconSource === "" && e.dot.a === 0
            text: e.icon
            color: e.current ? Colors.accent : e.tint.a > 0 ? Colors.alpha(e.tint, e.muted ? 0.4 : 0.9) : Colors.fade(e.muted ? 0.3 : 0.55)
            font.pixelSize: Tokens.font.label
            font.family: Properties.fontFamily
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s4
            Text {
                Layout.fillWidth: true
                text: e.label
                color: e.current ? Colors.ink : Colors.fade(e.muted ? 0.4 : 0.78)
                font.pixelSize: Tokens.font.small
                font.bold: e.current
                font.family: Properties.fontFamily
                elide: Text.ElideRight
            }
            // how full the drive is: amber from 90 %
            Rectangle {
                visible: e.used >= 0
                Layout.fillWidth: true
                implicitHeight: Tokens.space.s4
                radius: Tokens.radius.xs
                color: Colors.fade(0.1)
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, e.used))
                    height: parent.height
                    radius: Tokens.radius.xs
                    color: e.used >= 0.9 ? Colors.warning : Colors.alpha(Colors.accent, 0.7)
                }
            }
        }
        Text {
            visible: e.fold !== ""
            text: "\u{F0142}"
            rotation: e.fold === "open" ? 90 : 0
            Behavior on rotation { NumberAnimation { duration: Anim.normal; easing.type: Anim.standard } }
            color: Colors.fade(0.45)
            font.pixelSize: Tokens.font.small
            font.family: Properties.fontFamily
        }
        IconButton {
            visible: e.actionIcon !== ""
            implicitWidth: Tokens.size.controlSmall - Tokens.space.s4
            implicitHeight: Tokens.size.controlSmall - Tokens.space.s4
            iconSize: Tokens.icon.sm
            icon: e.actionIcon
            tooltip: e.actionTip
            onClicked: e.action()
        }
    }
}
