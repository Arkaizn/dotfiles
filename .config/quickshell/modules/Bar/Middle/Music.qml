import QtQuick
import qs.services

// The media player module (MusicBody), turned by 90° on a left / right bar
// when it's wider than the bar. Shown by the body's own `shown` (reading its
// `visible` here would stay false once this is hidden).
Item {
    id: root
    readonly property bool turned: PanelGeometry.barVertical && body.implicitWidth > PanelGeometry.barButtonHeight + 6
    visible: body.shown
    implicitWidth: turned ? body.implicitHeight : body.implicitWidth
    implicitHeight: turned ? body.implicitWidth : body.implicitHeight

    MusicBody {
        id: body
        anchors.centerIn: parent
        width: implicitWidth
        height: implicitHeight
        rotation: root.turned ? 90 : 0
    }
}
