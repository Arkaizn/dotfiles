import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

Rectangle {
    id: root

    property var entry
    signal clicked()

    implicitWidth: Math.max(col.implicitWidth + 24, 160)
    implicitHeight: (entry.isSeparator === true) ? 9 : 32
    radius: 6
    color: (entry.isSeparator === true)
        ? "transparent"
        : (hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent")

    property bool hovered: ma.containsMouse

    // Separator
    Rectangle {
        visible: entry.isSeparator === true
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        height: 1
        color: Qt.rgba(1, 1, 1, 0.12)
    }

    RowLayout {
        id: col
        visible: entry.isSeparator !== true
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 12
        spacing: 8

        IconImage {
            visible: entry.icon !== undefined && entry.icon.toString() !== ""
            source: entry.icon ?? ""
            width: 14
            height: 14
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            text: entry.text ?? ""
            color: (entry.enabled !== false)
                ? (root.hovered ? "#ffffff" : Qt.rgba(1, 1, 1, 0.85))
                : Qt.rgba(1, 1, 1, 0.35)
            font.pixelSize: 13
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            visible: entry.hasChildren === true
            text: "›"
            color: Qt.rgba(1, 1, 1, 0.4)
            font.pixelSize: 13
            Layout.alignment: Qt.AlignVCenter
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        enabled: entry.isSeparator !== true && entry.enabled !== false
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            entry.triggered()
            root.clicked()
        }
    }

    Behavior on color {
        ColorAnimation { duration: 80 }
    }
}