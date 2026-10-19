import QtQuick

// Brings a page's parts in one after another: each fades in and grows from
// 96 % (from its top edge). The settings window runs it on every page switch.
//   StaggerIn { id: enter }   enter.run([item, item, …])
QtObject {
    id: root
    property int step: 45               // ms between two parts
    property int maxParts: 8            // the rest come in with the 8th

    property Component anim: Component {
        SequentialAnimation {
            id: a
            property Item item
            property int delay
            PropertyAction { target: a.item; property: "opacity"; value: 0 }
            PauseAnimation { duration: a.delay }
            ParallelAnimation {
                NumberAnimation { target: a.item; property: "opacity"; to: 1; duration: 280; easing.type: Easing.OutCubic }
                NumberAnimation { target: a.item; property: "scale"; from: 0.96; to: 1; duration: 380; easing.type: Easing.OutCubic }
            }
            onFinished: destroy()
        }
    }

    function run(items) {
        let n = 0
        for (const it of items) {
            // hidden ones and ones that are faded on purpose keep their look
            if (!it || !it.visible || it.opacity !== 1 || it.height === 0) continue
            it.transformOrigin = Item.Top
            anim.createObject(root, { item: it, delay: Math.min(n, maxParts) * step }).start()
            n++
        }
    }
}
