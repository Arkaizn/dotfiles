import QtQuick

// Wheel scrolling for a Flickable like the month view: a fixed step per
// notch, eased, and notches add up while it's still moving.
//   Flickable { id: f; SmoothWheel { flick: f; step: 52 } }
WheelHandler {
    id: root

    property Flickable flick
    property real step: 120          // px per wheel notch

    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

    function scrollBy(dy) {
        const base = anim.running ? anim.to : flick.contentY
        const min = flick.originY
        const max = flick.originY + Math.max(0, flick.contentHeight - flick.height)
        anim.stop()
        anim.to = Math.max(min, Math.min(max, base + dy))
        anim.start()
    }

    onWheel: event => {
        scrollBy(event.angleDelta.y !== 0 ? -event.angleDelta.y / 120 * step : -event.pixelDelta.y)
    }

    property NumberAnimation anim: NumberAnimation {
        target: root.flick
        property: "contentY"
        duration: 320
        easing.type: Easing.OutCubic
    }
}
