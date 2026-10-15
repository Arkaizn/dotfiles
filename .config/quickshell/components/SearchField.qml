import QtQuick
import QtQuick.Controls
import qs.services

// Text field in the dark inner-card style of the dashboard: darker fill,
// soft card border that brightens on focus, an icon on the left and an
// animated clear button on the right.
//
//   SearchField {
//       placeholderText: "Search apps"
//       icon: "󰍉"                // "" for no icon
//       password: false          // dots instead of text
//   }
TextField {
    id: root

    property string icon: "󰍉"
    property bool password: false
    property bool clearable: !password
    property bool error: false          // red border + shake (e.g. wrong password)

    implicitHeight: Properties.buttonHeight + 4
    leftPadding: icon !== "" ? 38 : 14
    rightPadding: clearBtn.visible ? 34 : 14
    verticalAlignment: TextInput.AlignVCenter
    color: Properties.color
    font.pixelSize: 13
    font.family: Properties.fontFamily
    selectionColor: Qt.rgba(1, 1, 1, 0.28)
    selectedTextColor: "white"
    placeholderTextColor: Qt.rgba(1, 1, 1, 0.35)
    echoMode: password ? TextInput.Password : TextInput.Normal
    passwordCharacter: "●"
    // spread the dots out a bit (only once something is typed, so the placeholder stays normal)
    font.letterSpacing: password && echoMode === TextInput.Password && text.length > 0 ? 6 : 0

    // shake when `error` goes true
    property real shakeX: 0
    transform: Translate { x: root.shakeX }
    onErrorChanged: if (error) shake.restart()
    SequentialAnimation {
        id: shake
        NumberAnimation { target: root; property: "shakeX"; to: -10; duration: 50 }
        NumberAnimation { target: root; property: "shakeX"; to: 10; duration: 70 }
        NumberAnimation { target: root; property: "shakeX"; to: -6; duration: 60 }
        NumberAnimation { target: root; property: "shakeX"; to: 4; duration: 50 }
        NumberAnimation { target: root; property: "shakeX"; to: 0; duration: 40 }
    }

    background: Rectangle {
        radius: Properties.radius + 2
        // focus only nudges things: fill a touch lighter, border a touch brighter
        color: root.activeFocus ? "#3a000000" : "#45000000"
        border.width: Properties.panelBorderWidth
        border.color: root.error ? "#f38ba8"
                    : root.activeFocus ? Qt.rgba(1, 1, 1, 0.16)
                    : hover.hovered ? Qt.rgba(1, 1, 1, 0.13)
                    : Properties.cardBorder
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }

        // thin highlight that grows from the centre when focused
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 1
            anchors.horizontalCenter: parent.horizontalCenter
            height: 1.5
            radius: 1
            width: root.activeFocus ? parent.width - parent.radius * 2 : 0
            color: root.error ? "#f38ba8" : Qt.rgba(1, 1, 1, 0.14)
            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        }
    }

    HoverHandler { id: hover; cursorShape: Qt.IBeamCursor }

    // leading icon
    Text {
        visible: root.icon !== ""
        anchors { left: parent.left; leftMargin: 13; verticalCenter: parent.verticalCenter }
        text: root.icon
        color: Qt.rgba(1, 1, 1, root.activeFocus ? 0.7 : 0.45)
        font.pixelSize: 15
        font.family: Properties.fontFamily
        scale: root.activeFocus ? 1.05 : 1
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
    }

    // clear button, pops in once there's text
    Text {
        id: clearBtn
        visible: root.clearable && opacity > 0
        opacity: root.clearable && root.text.length > 0 ? 1 : 0
        scale: root.text.length > 0 ? 1 : 0.6
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        text: "󰅖"
        color: clearMouse.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.5)
        font.pixelSize: 14
        font.family: Properties.fontFamily
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

        MouseArea {
            id: clearMouse
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.text = ""; root.forceActiveFocus() }
        }
    }
}
