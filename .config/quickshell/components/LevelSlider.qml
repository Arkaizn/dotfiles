import QtQuick
import qs.services
import QtQuick.Controls

// Thin slider in the panel style. Bind `value` to the live value and write
// it back in `onMoved` (only fires on user interaction, so no feedback loop):
//   LevelSlider { value: node.audio.volume; accessibleName: "Volume"; onMoved: node.audio.volume = value }
// Keyboard: Tab focuses it (focus ring), arrow keys move it (Qt's Slider).
Slider {
    id: root
    property string accessibleName: ""
    Accessible.name: accessibleName
    focusPolicy: Qt.TabFocus
    from: 0
    to: 1
    implicitHeight: 20

    background: Rectangle {
        x: root.leftPadding
        y: root.topPadding + root.availableHeight / 2 - height / 2
        width: root.availableWidth
        height: 4
        radius: Tokens.radius.xs
        color: Colors.fade(0.2)

        Rectangle {
            width: root.visualPosition * parent.width
            height: parent.height
            radius: Tokens.radius.xs
            color: root.enabled ? Colors.fade(0.87) : Colors.fade(0.33)
        }
    }

    handle: Rectangle {
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: root.topPadding + root.availableHeight / 2 - height / 2
        width: 14
        height: 14
        radius: width / 2
        color: root.pressed ? Colors.ink : Colors.fade(0.93)
        border.color: Colors.fade(0.33)
        border.width: 1
        scale: root.pressed ? 1.15 : root.hovered ? 1.08 : 1
        Behavior on scale { NumberAnimation { duration: Anim.fast; easing.type: Anim.standard } }
        FocusRing { controlRadius: parent.radius; shown: root.visualFocus }
    }

    // false: the wheel scrolls the page instead of changing the value
    property bool scrollable: true

    // Mouse wheel nudges by 5%
    WheelHandler {
        enabled: root.scrollable
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            const step = event.angleDelta.y > 0 ? 0.05 : -0.05
            root.value = Math.max(root.from, Math.min(root.to, root.value + step))
            root.moved()
        }
    }
}
