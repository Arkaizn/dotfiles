import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Syntax page: one file the shell writes, as it would be written now.
NetCard {
    id: pv
    required property string file
    required property string body
    property string error: ""
    Layout.fillWidth: true
    title: file.replace(Quickshell.env("HOME"), "~")
    icon: "󰈙"
    header: [
        Text {
            text: pv.error !== "" ? "rejected" : "valid"
            color: pv.error !== "" ? "#f38ba8" : Colors.color6
            font.pixelSize: 11
            font.bold: true
            font.family: Properties.fontFamily
        }
    ]
    Text {
        Layout.fillWidth: true
        Layout.margins: 14
        visible: pv.error !== ""
        text: "󰀦  Rejected, the old file stays:\n" + pv.error
        color: "#f38ba8"
        font.pixelSize: 11
        font.family: Properties.fontFamily
        wrapMode: Text.Wrap
    }
    Text {
        Layout.fillWidth: true
        Layout.margins: 14
        text: pv.body
        color: Qt.rgba(1, 1, 1, 0.75)
        font.pixelSize: 11
        font.family: Properties.fontFamily
        wrapMode: Text.WrapAnywhere
        textFormat: Text.PlainText
    }
}
