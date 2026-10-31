import QtQuick
import QtQuick.Layouts
import qs.services

// − n +  (whole numbers; the wheel works on the number too)
//   Stepper { from: 1; to: 99; value: n; onEdited: v => n = v }
// The − / + are IconButtons (Tab, Space), ↑/↓ on either change it too.
RowLayout {
    id: st
    property int value: 1
    property int from: 1
    property int to: 99
    signal edited(int value)
    spacing: Tokens.space.s4
    IconButton {
        implicitWidth: 26; implicitHeight: 26
        iconSize: 11
        icon: "󰍴"
        tooltip: "Less"
        Keys.onUpPressed: if (st.value < st.to) st.edited(st.value + 1)
        Keys.onDownPressed: if (st.value > st.from) st.edited(st.value - 1)
        interactive: st.value > st.from
        onClicked: st.edited(st.value - 1)
    }
    Text {
        Layout.preferredWidth: 30
        horizontalAlignment: Text.AlignHCenter
        text: st.value
        color: Colors.ink
        font.pixelSize: Tokens.font.body
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
        tooltip: "More"
        Keys.onUpPressed: if (st.value < st.to) st.edited(st.value + 1)
        Keys.onDownPressed: if (st.value > st.from) st.edited(st.value - 1)
        interactive: st.value < st.to
        onClicked: st.edited(st.value + 1)
    }
}
