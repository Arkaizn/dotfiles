import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.components
import qs.services

// The password card: picture + greeting, password field with the submit
// button, Caps Lock hint, status line (checking / wrong password / …). The
// field shakes when `lock.failed` goes true. Children go between the greeting
// and the password field (the login screen puts its user / session pickers
// there).
//
//   AuthCard { stage: <LockStage>; lock: <shared state>; avatar: "/path/face" }
Rectangle {
    id: root

    required property LockStage stage
    required property var lock          // shared state (see LockStage)
    property bool showAvatar: true
    property string avatar: ""          // image path ("" = no picture)
    property string greeting: ""
    property string submitTip: "Unlock"
    readonly property alias field: passwordField
    default property alias extra: extraCol.data

    anchors.horizontalCenter: parent.horizontalCenter
    y: stage.height * 0.5 - height / 2 + 40 + (stage.auth ? 0 : 30)
    width: 380
    height: cardCol.implicitHeight + 48
    radius: Properties.panelRadius
    color: Properties.panelColor
    border.width: Properties.panelBorderWidth
    border.color: Properties.panelBorder
    opacity: stage.auth ? 1 : 0
    scale: stage.auth ? 1 : 0.94
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
    Behavior on y { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

    // swallow clicks so they don't hit the background MouseArea
    MouseArea { anchors.fill: parent }

    ColumnLayout {
        id: cardCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
        spacing: 12

        // avatar
        Item {
            // no picture file (or not readable): no empty circle
            visible: root.showAvatar && root.avatar !== "" && avatarImg.status !== Image.Error
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 96
            Layout.preferredHeight: 96
            Image {
                id: avatarImg
                anchors.fill: parent
                source: root.avatar === "" ? "" : "file://" + root.avatar
                cache: false
                sourceSize: Qt.size(192, 192)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: false
            }
            OpacityMask {
                anchors.fill: parent
                source: avatarImg
                maskSource: Rectangle { width: 96; height: 96; radius: 48 }
            }
            Rectangle {
                anchors.fill: parent
                radius: 48
                color: "transparent"
                border.width: 2
                border.color: Colors.fade(0.18)
            }
        }

        Text {
            visible: root.showAvatar && root.greeting !== ""
            Layout.alignment: Qt.AlignHCenter
            text: root.greeting
            color: Colors.ink
            font.pixelSize: 18
            font.bold: true
        }

        ColumnLayout {
            id: extraCol
            Layout.fillWidth: true
            spacing: 8
            visible: children.length > 0
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            SearchField {
                id: passwordField
                Layout.fillWidth: true
                icon: "󰌾"
                password: true
                placeholderText: root.lock.yubikey ? "Password or YubiKey" : "Password"
                enabled: !root.lock.checking
                error: root.lock.failed
                text: root.lock.password
                onTextChanged: if (text !== root.lock.password) root.lock.password = text
                onAccepted: root.lock.submit()
                Keys.onEscapePressed: root.lock.hideAuth()
                // keep the cursor at the end when text comes from another screen / the first key
                onActiveFocusChanged: if (activeFocus) cursorPosition = text.length
            }
            IconButton {
                implicitWidth: Properties.buttonHeight + 4
                implicitHeight: Properties.buttonHeight + 4
                icon: root.lock.checking ? "󰔟" : "󰁔"
                interactive: !root.lock.checking && root.lock.password.length > 0
                tooltip: root.submitTip
                onClicked: root.lock.submit()
            }
        }

        // Caps Lock warning
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: capsText.implicitWidth + 20
            implicitHeight: root.lock.capsLock ? 24 : 0
            radius: 12
            color: Qt.rgba(Colors.orange.r, Colors.orange.g, Colors.orange.b, 0.2)
            border.width: 1
            border.color: Qt.rgba(Colors.orange.r, Colors.orange.g, Colors.orange.b, 0.4)
            opacity: root.lock.capsLock ? 1 : 0
            visible: implicitHeight > 0.5
            clip: true
            Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Text {
                id: capsText
                anchors.centerIn: parent
                text: "󰘲  Caps Lock is on"
                color: Colors.orange
                font.pixelSize: 11
                font.family: Properties.fontFamily
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 16
            Layout.maximumWidth: cardCol.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.lock.status
            color: root.lock.failed ? Colors.red : Colors.fade(0.6)
            font.pixelSize: 12
        }
    }
}
