// PopupAnimation.qml
import QtQuick

Item {
    id: root

    property var target: parent
    property string direction: "top"
    property int enterDuration: Anim.popupIn
    property int exitDuration:  Anim.popupOut
    signal exitFinished()

    function enter() {
        exitGroup.stop()
        target.clip = true
        target.opacity = 1
        enterGroup.start()
    }

    function exit() {
        enterGroup.stop()
        target.clip = true
        exitGroup.start()
    }

    ParallelAnimation {
    id: enterGroup
        NumberAnimation {
            target: root.target
            property: "height"
            from: 0
            to: root.target.implicitHeight
            duration: root.enterDuration
            easing.type: Easing.OutBack
            easing.overshoot: 1.0  // tweak this — higher = more overshoot
        }
    }

    ParallelAnimation {
        id: exitGroup
        NumberAnimation {
            target: root.target
            property: "height"
            from: root.target.implicitHeight
            to: 0
            duration: root.exitDuration
            easing.type: Anim.easingOut
        }
        onFinished: root.exitFinished()
    }
}