import QtQuick
import qs.services
import QtQuick.Layouts

// Part of a card that slides open / closed: height, opacity and a small
// downward slide animate together, so the card around it grows smoothly.
Item {
    id: root
    property bool open: false
    property int spacing: 0
    default property alias content: inner.data

    Layout.fillWidth: true
    Layout.preferredHeight: open ? inner.implicitHeight : 0
    visible: Layout.preferredHeight > 0.5
    // clip only while sliding: once open, buttons growing on hover at its
    // edges must not be cut off
    clip: Math.abs(Layout.preferredHeight - inner.implicitHeight) > 0.5
    Behavior on Layout.preferredHeight { NumberAnimation { duration: Anim.medium; easing.type: Anim.standard } }

    ColumnLayout {
        id: inner
        width: root.width
        spacing: root.spacing
        opacity: root.open ? 1 : 0
        y: root.open ? 0 : -8
        Behavior on opacity { NumberAnimation { duration: Anim.normal } }
        Behavior on y { NumberAnimation { duration: Anim.medium; easing.type: Anim.standard } }
    }
}
