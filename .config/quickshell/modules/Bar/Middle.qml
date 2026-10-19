import QtQuick
import qs.services

// Middle of the bar: "center" stays centred, centerLeft / centerRight grow
// outwards from its sides (modules: BarLayout).
Item {
    id: middle
    property string screenName
    property bool editing: false
    property string dragId: ""
    anchors.fill: parent
    readonly property alias centerSection: center
    readonly property alias centerLeftSection: centerLeft
    readonly property alias centerRightSection: centerRight

    BarSection {
        id: center
        screenName: middle.screenName
        editing: middle.editing
        dragId: middle.dragId
        zone: "center"
        anchors.centerIn: parent
    }
    BarSection {
        id: centerLeft
        screenName: middle.screenName
        editing: middle.editing
        dragId: middle.dragId
        zone: "centerLeft"
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: center.left
        anchors.rightMargin: center.implicitWidth > 0 ? Properties.spacing : 0
    }
    BarSection {
        id: centerRight
        screenName: middle.screenName
        editing: middle.editing
        dragId: middle.dragId
        zone: "centerRight"
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: center.right
        anchors.leftMargin: center.implicitWidth > 0 ? Properties.spacing : 0
    }
}
