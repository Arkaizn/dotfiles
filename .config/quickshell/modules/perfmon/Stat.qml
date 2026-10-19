import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services

Rectangle {
    id: st
    property string label
    property string value
    property color labelColor: Colors.fade(0.42)
    Layout.fillWidth: true
    implicitHeight: 50
    radius: Properties.radius
    color: Colors.shade(0.12)
    border.width: Properties.panelBorderWidth
    border.color: Properties.cardBorder
    Column {
        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 8 }
        spacing: 2
        Text { text: st.label; color: st.labelColor; font.pixelSize: 10; font.bold: true; font.letterSpacing: 1; font.family: Properties.fontFamily }
        Text { width: parent.width; text: st.value; color: Colors.ink; font.pixelSize: 15; font.bold: true; font.family: Properties.fontFamily; elide: Text.ElideRight }
    }
}
