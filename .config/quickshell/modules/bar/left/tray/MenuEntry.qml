import Quickshell.Services.SystemTray
import QtQuick
import qs.services
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
        : (hovered ? Colors.fillHover : "transparent")

    property bool hovered: ma.containsMouse

    // Separator
    Rectangle {
        visible: entry.isSeparator === true
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Tokens.space.s4
        anchors.rightMargin: Tokens.space.s4
        height: 1
        color: Colors.fillPressed
    }

    RowLayout {
        id: col
        visible: entry.isSeparator !== true
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: Tokens.space.s12
        spacing: Tokens.space.s8

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
                ? (root.hovered ? Colors.ink : Colors.fade(0.85))
                : Colors.textDisabled
            font.pixelSize: Tokens.font.body
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            visible: entry.hasChildren === true
            text: "›"
            color: Colors.fade(0.4)
            font.pixelSize: Tokens.font.body
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
            if (entry && entry.hasChildren === true) {
                entry.opened()
                submenuLoader.active = !submenuLoader.active
                if (submenuLoader.item) {
                    submenuLoader.item.parentEntry = entry
                }
            } else if (entry) {
                entry.triggered()
                root.clicked()
            }
        }
    }

    Behavior on color {
        ColorAnimation { duration: Anim.instant }
    }

        Loader {
        id: submenuLoader
        active: false
        anchors.top: parent.top
        anchors.left: parent.right
        anchors.leftMargin: Tokens.space.s4
        z: 10
        source: active ? Qt.resolvedUrl("MenuChildren.qml") : ""
        onLoaded: {
            item.parentEntry = root.entry
            item.clicked.connect(root.clicked)
        }
    }
}

