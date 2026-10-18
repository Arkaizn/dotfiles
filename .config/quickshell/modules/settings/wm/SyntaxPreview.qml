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
            color: pv.error !== "" ? Colors.red : Colors.color6
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
        color: Colors.red
        font.pixelSize: 11
        font.family: Properties.fontFamily
        wrapMode: Text.Wrap
    }
    Text {
        Layout.fillWidth: true
        Layout.margins: 14
        text: pv.body
        color: Colors.fade(0.75)
        font.pixelSize: 11
        font.family: Properties.fontFamily
        wrapMode: Text.WrapAnywhere
        textFormat: Text.PlainText
    }
}
