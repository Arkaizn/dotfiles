import QtQuick
import qs.services

// The big clock of the lockscreen / login screen: centred while idle, moves
// up and shrinks when the password view opens. Text sits on the dimmed
// wallpaper, so it stays white in light themes too.
//
//   LockClock { stage: <LockStage>; seconds: true; date: true }
Column {
    id: root

    required property LockStage stage
    property bool seconds: true
    property bool date: true

    anchors.horizontalCenter: parent.horizontalCenter
    // small drop-in from above while showing
    y: (stage.auth ? stage.height * 0.13 : stage.height * 0.5 - height / 2 - 60) - (1 - stage.shown) * 30
    scale: stage.auth ? 0.6 : 1
    transformOrigin: Item.Top
    spacing: 0
    Behavior on y { enabled: root.stage.settled; NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
    Behavior on scale { enabled: root.stage.settled; NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 4
        Text {
            id: hours
            text: Time.format("HH")
            color: "white"
            font.pixelSize: 168
            font.bold: true
            font.family: Properties.fontFamily
        }
        Text {
            text: ":"
            color: Qt.rgba(1, 1, 1, 0.45)
            font.pixelSize: 168
            font.family: Properties.fontFamily
        }
        Text {
            text: Time.format("mm")
            color: Qt.rgba(1, 1, 1, 0.55)
            font.pixelSize: 168
            font.bold: true
            font.family: Properties.fontFamily
        }
        Text {
            visible: root.seconds
            anchors.baseline: hours.baseline
            text: Time.format("ss")
            color: Qt.rgba(1, 1, 1, 0.35)
            font.pixelSize: 40
            font.family: Properties.fontFamily
        }
    }
    Text {
        visible: root.date
        anchors.horizontalCenter: parent.horizontalCenter
        text: Time.format("dddd, d. MMMM")
        color: Qt.rgba(1, 1, 1, 0.8)
        font.pixelSize: 26
    }
}
