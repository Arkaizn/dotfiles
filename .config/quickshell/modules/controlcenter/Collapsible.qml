import QtQuick
import QtQuick.Layouts

// Dropdown body for a ColumnLayout: height + opacity animate open/closed,
// so whatever card it sits in grows/shrinks smoothly with it.
Item {
    id: cl
    property bool open: false
    default property alias content: inner.data

    Layout.fillWidth: true
    Layout.preferredHeight: open ? inner.implicitHeight : 0
    visible: Layout.preferredHeight > 0.5
    opacity: open ? 1 : 0
    clip: true
    Behavior on Layout.preferredHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 160 } }

    ColumnLayout {
        id: inner
        width: cl.width
        spacing: 8
    }
}
