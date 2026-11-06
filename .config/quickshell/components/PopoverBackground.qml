import QtQuick
import QtQuick.Effects
import qs.services

// The surface of every popover (dropdown lists, menus, date / time pickers,
// suggestion lists):  Popup { background: PopoverBackground {} … }
// backdrop: an item of the window under the popover (e.g. the window's
// background) — then what's behind shows through blurred, like the frosted
// window itself. A popover is drawn inside the window, so the compositor's blur
// can't reach it; this does it here. Without a backdrop it's plain.
Rectangle {
    id: root
    property Item backdrop: null

    radius: Tokens.radius.xl
    color: backdrop ? Colors.alpha(Colors.surfacePopover, 0.72) : Colors.surfacePopover
    border.width: Properties.panelBorderWidth
    border.color: Properties.panelBorder

    // the part of the backdrop right under the popover, blurred, under the color
    Item {
        anchors.fill: parent
        z: -1
        visible: root.backdrop !== null && root.width > 0
        layer.enabled: visible
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
        }
        // an opaque base: the captured content is see-through itself (cards have alpha), and
        // what's really behind the popover must not show through sharp
        Rectangle { anchors.fill: parent; color: Colors.background }
        ShaderEffectSource {
            id: under
            anchors.fill: parent
            sourceItem: root.backdrop
            live: true
            hideSource: false
            // where the popover is over the backdrop: mapToItem doesn't notify, so it reads what
            // moves the popover (its item's position and scale — the open animation grows it from
            // 0.96, app zoom scales it —, its size, being shown) to be asked again; both corners, so
            // a scaled popover takes the area it really covers
            readonly property rect area: {
                root.parent?.x; root.parent?.y; root.parent?.scale; root.parent?.parent?.x; root.parent?.parent?.y
                root.width; root.height; root.visible
                if (!root.backdrop) return Qt.rect(0, 0, 0, 0)
                const a = root.mapToItem(root.backdrop, 0, 0), b = root.mapToItem(root.backdrop, root.width, root.height)
                return Qt.rect(a.x, a.y, b.x - a.x, b.y - a.y)
            }
            sourceRect: area
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: under
            blurEnabled: true
            blur: 1
            blurMax: 48
            saturation: 0.15
        }
    }
    // the rounded corners for the blur
    Rectangle {
        id: mask
        anchors.fill: parent
        radius: root.radius
        visible: false
        layer.enabled: true
    }
}
