import QtQuick
import QtQuick.Controls

// Thin slider in the panel style. Bind `value` to the live value and write
// it back in `onMoved` (only fires on user interaction, so no feedback loop):
//   CCSlider { value: node.audio.volume; onMoved: node.audio.volume = value }
Slider {
    id: root
    from: 0
    to: 1
    implicitHeight: 20

    background: Rectangle {
        x: root.leftPadding
        y: root.topPadding + root.availableHeight / 2 - height / 2
        width: root.availableWidth
        height: 4
        radius: 2
        color: "#33ffffff"

        Rectangle {
            width: root.visualPosition * parent.width
            height: parent.height
            radius: 2
            color: root.enabled ? "#ddffffff" : "#55ffffff"
        }
    }

    handle: Rectangle {
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: root.topPadding + root.availableHeight / 2 - height / 2
        width: 14
        height: 14
        radius: 7
        color: root.pressed ? "#ffffff" : "#eeffffff"
        border.color: "#55ffffff"
        border.width: 1
        scale: root.pressed ? 1.15 : root.hovered ? 1.08 : 1
        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
    }

    // Mouse wheel nudges by 5%
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            const step = event.angleDelta.y > 0 ? 0.05 : -0.05
            root.value = Math.max(root.from, Math.min(root.to, root.value + step))
            root.moved()
        }
    }
}
