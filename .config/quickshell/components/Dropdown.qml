import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services

// Button that opens a list to pick from.
//   Dropdown { options: [{ label, value, hint?, color? }]; value: v; onEdited: x => v = x }
//   (color: a dot in front, e.g. the calendar's color)
// Keyboard: Tab focuses it; Space / Enter opens the list; ↑/↓ pick the
// neighbour without opening it. Like the other controls it doesn't change
// itself — the owner sets `value` from `edited`.
Pressable {
    id: root

    property var options: []
    property var value
    property int listWidth: 0          // the open list can be wider than the button (long hints)
    signal edited(var value)

    readonly property var current: options.find(o => o.value === value)
    readonly property int currentIndex: options.findIndex(o => o.value === value)

    accessibleName: current?.label ?? ""
    accessibleRole: Accessible.ComboBox
    focusRadius: Tokens.radius.md
    onClicked: list.visible ? list.close() : list.open()
    Keys.onUpPressed: if (currentIndex > 0) edited(options[currentIndex - 1].value)
    Keys.onDownPressed: if (currentIndex < options.length - 1) edited(options[currentIndex + 1].value)

    implicitWidth: 200
    implicitHeight: Properties.buttonHeight

    // grows at most 4px per side (it can be wide), like ActionButton
    scale: pressed ? Properties.onPressedButtonScale
         : hovered ? 1 + Math.min((Properties.onEnteredButtonScale - 1) * 0.4, 8 / Math.max(1, width)) : 1
    Behavior on scale { NumberAnimation { duration: Anim.button; easing.type: Anim.standard } }

    ButtonBackground {
        hovered: root.hovered || root.activeFocus || list.visible
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.space.s12
        anchors.rightMargin: Tokens.space.s10
        spacing: Tokens.space.s8
        Rectangle {
            visible: !!root.current?.color
            Layout.preferredWidth: 10
            Layout.preferredHeight: 10
            radius: 5
            color: root.current?.color ?? "transparent"
            Behavior on color { ColorAnimation { duration: Anim.normal } }
        }
        Text {
            Layout.fillWidth: true
            text: root.current?.label ?? "—"
            color: Colors.ink
            font.pixelSize: Tokens.font.small
            font.family: Properties.fontFamily
            elide: Text.ElideRight
        }
        Chevron { open: list.visible }
    }

    Popup {
        id: list
        // the app window's zoom (Ctrl +/−): popups are drawn above it, not inside
        scale: AppZoom.at(parent)
        transformOrigin: Popup.TopLeft
        y: root.height + 4
        // stays inside the window (moved up / left when there's no room below / right)
        margins: Tokens.space.s8
        width: Math.max(root.width, 160, root.listWidth)
        height: Math.min(view.contentHeight + 12, 260)
        padding: Tokens.space.s6
        closePolicy: Popup.CloseOnPressOutsideParent | Popup.CloseOnEscape   // the button itself toggles it
        onOpened: view.positionViewAtIndex(Math.max(0, root.options.indexOf(root.current)), ListView.Center)

        background: PopoverBackground {}

        ListView {
            id: view
            anchors.fill: parent
            clip: true
            model: root.options
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                id: entry
                required property var modelData
                readonly property bool selected: modelData.value === root.value
                width: ListView.view.width
                height: 28
                radius: Tokens.radius.md
                color: hover.hovered ? Colors.fade(0.08) : selected ? Colors.fade(0.05) : "transparent"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.space.s10
                    anchors.rightMargin: Tokens.space.s10
                    spacing: Tokens.space.s8
                    Rectangle {
                        visible: !!entry.modelData.color
                        Layout.preferredWidth: 10
                        Layout.preferredHeight: 10
                        radius: 5
                        color: entry.modelData.color ?? "transparent"
                    }
                    // label and hint never overlap: both are cut ("…") when it's tight
                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 40
                        text: entry.modelData.label
                        color: entry.selected ? Colors.accent : Colors.ink
                        font.pixelSize: Tokens.font.small
                        font.bold: entry.selected
                        font.family: Properties.fontFamily
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: text !== ""
                        Layout.maximumWidth: entry.width * 0.55
                        elide: Text.ElideMiddle
                        text: entry.modelData.hint ?? ""
                        color: Colors.textMuted
                        font.pixelSize: Tokens.font.micro
                        font.family: Properties.fontFamily
                    }
                }
                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        list.close()
                        if (!entry.selected) root.edited(entry.modelData.value)
                    }
                }
            }
        }
    }
}
