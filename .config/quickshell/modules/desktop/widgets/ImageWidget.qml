import QtQuick
import Quickshell.Widgets
import Quickshell
import qs.services

// Picture frame: a picture file, rounded corners.
ClippingRectangle {
    id: root
    property var opts: ({})
    property bool interactive: true
    property bool active: true

    readonly property real w: opts.width ?? 280
    implicitWidth: w
    implicitHeight: img.status === Image.Ready && img.implicitWidth > 0 ? w * img.implicitHeight / img.implicitWidth : w * 0.66
    radius: opts.radius ?? 14
    color: Colors.fade(0.06)
    Image {
        id: img
        anchors.fill: parent
        source: (root.opts.path ?? "") !== "" ? "file://" + root.opts.path.replace(/^~(?=\/)/, Quickshell.env("HOME")) : ""
        sourceSize.width: root.w * 2
        fillMode: Image.PreserveAspectFit
        asynchronous: true
    }
    Text {
        anchors.centerIn: parent
        visible: img.status !== Image.Ready
        text: (root.opts.path ?? "") === "" ? "󰋩  Choose a picture" : "󰋩  Can't load the picture"
        color: Colors.fade(0.5)
        font.pixelSize: 13
        font.family: Properties.fontFamily
    }
}
