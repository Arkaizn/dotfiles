import QtQuick
import QtQuick.Layouts

// The content of one tab of a page (Layouts, Cleanup & packages): a Loader
// that slides in from the side you switched to.
//   from: 1 = from the right (a tab further right), -1 = from the left, 0 = no slide
Loader {
    id: root
    property int from: 0

    Layout.fillWidth: true
    visible: active
    transform: Translate { id: shift }

    onLoaded: if (from !== 0) slide.restart()
    ParallelAnimation {
        id: slide
        NumberAnimation { target: shift; property: "x"; from: root.from * 56; to: 0; duration: 360; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
    }
}
