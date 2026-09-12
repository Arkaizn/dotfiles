import QtQuick
import qs.services

Item {
    id: root

    property var target: parent
    property string direction: "top"   // "top" = enters from below, sliding up
                                        // "bottom" = enters from above, sliding down
    property int enterDuration: Anim.popupIn
    property int exitDuration:  Anim.popupOut
    property int distance: 0           // 0 = auto, uses target's own height/width

    signal exitFinished()

    function _offset() {
        var d = root.distance > 0
            ? root.distance
            : ((direction === "top" || direction === "bottom") ? target.height : target.width)
        switch (direction) {
            case "top":    return { x: 0, y:  d }
            case "bottom": return { x: 0, y: -d }
            case "left":   return { x:  d, y: 0 }
            case "right":  return { x: -d, y: 0 }
            default:       return { x: 0, y:  d }
        }
    }

    function enter() {
        exitGroup.stop()
        target.clip = true
        var off = root._offset()
        target.x = off.x
        target.y = off.y
        console.log("enter() offset:", off.x, off.y, "target size:", target.width, target.height, "target.y after set:", target.y)
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
        NumberAnimation { target: root.target; property: "x"; to: 0; duration: root.enterDuration; easing.type: Easing.OutCubic }
        NumberAnimation { target: root.target; property: "y"; to: 0; duration: root.enterDuration; easing.type: Easing.OutCubic }
    }

    ParallelAnimation {
        id: exitGroup
        NumberAnimation { target: root.target; property: "x"; to: root._offset().x; duration: root.exitDuration; easing.type: Easing.InCubic }
        NumberAnimation { target: root.target; property: "y"; to: root._offset().y; duration: root.exitDuration; easing.type: Easing.InCubic }
        onFinished: root.exitFinished()
    }
}