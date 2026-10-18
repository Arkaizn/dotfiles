import QtQuick
import qs.services

// Middle of the bar: "center" stays centred, centerLeft / centerRight grow
// outwards from its sides (modules: BarLayout).
Item {
    id: middle
    property string screenName
    anchors.fill: parent

    BarSection {
        id: center
        screenName: middle.screenName
        zone: "center"
        anchors.centerIn: parent
    }
    BarSection {
        screenName: middle.screenName
        zone: "centerLeft"
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: center.left
        anchors.rightMargin: center.implicitWidth > 0 ? Properties.spacing : 0
    }
    BarSection {
        screenName: middle.screenName
        zone: "centerRight"
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: center.right
        anchors.leftMargin: center.implicitWidth > 0 ? Properties.spacing : 0
    }
}
