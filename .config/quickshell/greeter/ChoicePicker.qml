pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// A row on the password card: icon + the current choice; a click opens the
// list below it, a click on an entry picks it (user, session).
// With `otherLabel` the list ends with that entry ("Other user…"): it turns the
// row into a text field, Enter sends what was typed (typed), Esc goes back.
//
//   ChoicePicker { icon: "󰍹"; model: [...]; current: obj; label: o => o.name; onPicked: o => … }
//   ChoicePicker { …; otherLabel: "Other user…"; onTyped: t => { if (ok(t)) editing = false } }
ColumnLayout {
    id: root

    property string icon: ""
    property var model: []
    property var current: null
    property var label: o => String(o)
    property var iconOf: null               // o => glyph: an icon per entry (the row shows the current one's)
    property bool open: false
    property string otherLabel: ""          // "" = only the list
    property string otherPlaceholder: ""
    property bool editing: false            // the text field instead of the row
    readonly property bool canOpen: model.length > 1 || otherLabel !== ""
    signal picked(var choice)
    signal typed(string text)
    signal cancelled()                      // Esc in the text field
    signal activity()                       // a key in the text field

    onEditingChanged: {
        if (!editing) return
        open = false
        typeField.text = ""
        typeField.forceActiveFocus()
    }
    onVisibleChanged: if (!visible) { open = false; editing = false }

    Layout.fillWidth: true
    spacing: Tokens.space.s4

    // typing a name (Enter: use it · Esc: back to the list)
    SearchField {
        id: typeField
        visible: root.editing
        Layout.fillWidth: true
        implicitHeight: Properties.buttonHeight
        icon: root.icon
        placeholderText: root.otherPlaceholder
        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
        onTextChanged: if (root.editing) root.activity()
        onAccepted: root.typed(text)
        Keys.onEscapePressed: { root.editing = false; root.cancelled() }
    }

    Rectangle {
        visible: !root.editing
        Layout.fillWidth: true
        implicitHeight: Properties.buttonHeight
        radius: Tokens.radius.lg
        color: head.containsMouse || root.open ? Colors.fade(0.10) : Colors.fade(0.05)
        border.width: Properties.panelBorderWidth
        border.color: root.open ? Colors.fade(0.16) : Properties.cardBorder
        Behavior on color { ColorAnimation { duration: Anim.fast } }

        RowLayout {
            anchors { fill: parent; leftMargin: 13; rightMargin: Tokens.space.s12 }
            spacing: Tokens.space.s10
            Text {
                text: root.iconOf && root.current ? root.iconOf(root.current) : root.icon
                color: Colors.fade(0.6)
                font.pixelSize: 15
                font.family: Properties.fontFamily
            }
            Text {
                Layout.fillWidth: true
                text: root.current ? root.label(root.current) : ""
                color: Colors.ink
                font.pixelSize: Tokens.font.body
                elide: Text.ElideRight
            }
            Text {
                visible: root.canOpen
                text: root.open ? "󰅃" : "󰅀"
                color: Colors.fade(0.5)
                font.pixelSize: Tokens.font.body
                font.family: Properties.fontFamily
            }
        }
        MouseArea {
            id: head
            anchors.fill: parent
            hoverEnabled: true
            enabled: root.canOpen
            cursorShape: Qt.PointingHandCursor
            onClicked: root.open = !root.open
        }
    }

    // the list
    Repeater {
        model: root.open ? root.model : []
        Rectangle {
            id: entry
            required property var modelData
            // by label: the same entry read twice from a var list isn't the same object
            readonly property bool chosen: root.current !== null && root.label(modelData) === root.label(root.current)
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.space.s12
            implicitHeight: Properties.buttonHeight - 4
            radius: Tokens.radius.md
            color: entryMouse.containsMouse ? Colors.fade(0.12) : chosen ? Colors.fade(0.07) : "transparent"
            Row {
                anchors { left: parent.left; leftMargin: Tokens.space.s12; verticalCenter: parent.verticalCenter }
                spacing: Tokens.space.s8
                Text {
                    width: 14
                    text: entry.chosen ? "󰄬" : ""
                    color: Colors.ink
                    font.pixelSize: Tokens.font.small
                    font.family: Properties.fontFamily
                }
                Text {
                    visible: root.iconOf !== null
                    width: 18
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: root.iconOf ? root.iconOf(entry.modelData) : ""
                    color: entry.chosen ? Colors.ink : Colors.fade(0.6)
                    font.pixelSize: Tokens.font.body
                    font.family: Properties.fontFamily
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.label(entry.modelData)
                    color: entry.chosen ? Colors.ink : Colors.fade(0.75)
                    font.pixelSize: Tokens.font.small
                }
            }
            MouseArea {
                id: entryMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // pick first: closing the list destroys this entry
                onClicked: { root.picked(entry.modelData); root.open = false }
            }
        }
    }

    // "Other user…": type a name instead
    Rectangle {
        visible: root.open && root.otherLabel !== ""
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.space.s12
        implicitHeight: Properties.buttonHeight - 4
        radius: Tokens.radius.md
        color: otherMouse.containsMouse ? Colors.fade(0.12) : "transparent"
        Row {
            anchors { left: parent.left; leftMargin: Tokens.space.s12; verticalCenter: parent.verticalCenter }
            spacing: Tokens.space.s8
            Text {
                width: 14
                text: "󰏫"
                color: Colors.fade(0.6)
                font.pixelSize: Tokens.font.small
                font.family: Properties.fontFamily
            }
            Text {
                text: root.otherLabel
                color: Colors.fade(0.75)
                font.pixelSize: Tokens.font.small
            }
        }
        MouseArea {
            id: otherMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.editing = true
        }
    }
}
