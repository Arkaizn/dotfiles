import QtQuick
import QtQuick.Layouts
import qs.services

// A dim explanation line under a section or control, wrapping.
//   Hint { text: "Only for new events" }
Text {
    Layout.fillWidth: true
    Layout.leftMargin: Tokens.space.s6
    color: Colors.textMuted
    font.pixelSize: Tokens.font.caption
    font.family: Properties.fontFamily
    wrapMode: Text.Wrap
}
