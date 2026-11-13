import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.components
import qs.services

// The password card: picture + greeting, password field with the submit
// button, Caps Lock hint, status line (checking / wrong password / …). The
// field shakes when `lock.failed` goes true. Children go between the greeting
// and the password field (the login screen puts its user picker there), `footer`
// ones below the status line (its session picker).
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
    property alias footer: footerCol.data

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
    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Anim.standard } }
    Behavior on scale { NumberAnimation { duration: 350; easing.type: Anim.standard } }
    Behavior on y { NumberAnimation { duration: 350; easing.type: Anim.standard } }

    // swallow clicks so they don't hit the background MouseArea
    MouseArea { anchors.fill: parent }

    ColumnLayout {
        id: cardCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Tokens.space.s24 }
        spacing: Tokens.space.s12

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
            font.pixelSize: Tokens.font.title
            font.bold: true
        }

        ColumnLayout {
            id: extraCol
            Layout.fillWidth: true
            spacing: Tokens.space.s8
            visible: children.length > 0
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s8

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
                interactive: !root.lock.checking && (root.lock.password.length > 0 || root.lock.emptySubmit)
                tooltip: root.submitTip
                onClicked: root.lock.submit()
            }
        }

        // Caps Lock warning
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: capsText.implicitWidth + 20
            implicitHeight: root.lock.capsLock ? 24 : 0
            radius: Tokens.radius.xl
            color: Colors.alpha(Colors.orange, 0.2)
            border.width: 1
            border.color: Colors.alpha(Colors.orange, 0.4)
            opacity: root.lock.capsLock ? 1 : 0
            visible: implicitHeight > 0.5
            clip: true
            Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Anim.standard } }
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Text {
                id: capsText
                anchors.centerIn: parent
                text: "󰘲  Caps Lock is on"
                color: Colors.orange
                font.pixelSize: Tokens.font.caption
                font.family: Properties.fontFamily
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 16
            Layout.maximumWidth: cardCol.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            // the status, else what to do with the YubiKey (FIDO2: touch it)
            text: root.lock.status || root.lock.keyHint
            color: root.lock.failed && root.lock.status ? Colors.red : Colors.fade(0.6)
            font.pixelSize: Tokens.font.small
        }

        ColumnLayout {
            id: footerCol
            Layout.fillWidth: true
            spacing: Tokens.space.s8
            visible: children.length > 0
        }
    }
}
