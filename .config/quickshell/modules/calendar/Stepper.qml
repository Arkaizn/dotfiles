import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// − n +  (whole numbers; the wheel works on the number too)
RowLayout {
    id: st
    property int value: 1
    property int from: 1
    property int to: 99
    signal edited(int value)
    spacing: 4
    IconButton {
        implicitWidth: 26; implicitHeight: 26
        iconSize: 11
        icon: "󰍴"
        interactive: st.value > st.from
        onClicked: st.edited(st.value - 1)
    }
    Text {
        Layout.preferredWidth: 30
        horizontalAlignment: Text.AlignHCenter
        text: st.value
        color: Colors.ink
        font.pixelSize: 13
        font.bold: true
        font.family: Properties.fontFamily
        WheelHandler {
            onWheel: e => st.edited(Math.max(st.from, Math.min(st.to, st.value + (e.angleDelta.y > 0 ? 1 : -1))))
        }
    }
    IconButton {
        implicitWidth: 26; implicitHeight: 26
        iconSize: 11
        icon: "󰐕"
        interactive: st.value < st.to
        onClicked: st.edited(st.value + 1)
    }
}
