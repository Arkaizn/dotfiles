import QtQuick
import Quickshell.Io
import Qt5Compat.GraphicalEffects
import "."

// A single wallpaper thumbnail tile: disk-cached preview image, hover
// zoom/overlay with filename, selection border, and an "Applying…" state.
//
// Usage:
//   WallpaperTile {
//       path: modelData.path
//       name: modelData.name
//       cellW: rect.cellW
//       cellH: rect.cellH
//       thumbCacheDir: root.thumbCacheDir
//       isSelected: applyProc.pickedPath === path
//       applying: applyProc.running && isSelected
//       onClicked: { ... }
//   }
Item {
    id: delegateRoot

    required property string path
    required property string name
    property real cellW: 100
    property real cellH: 58
    property string thumbCacheDir: ""
    property bool isSelected: false
    property bool applying: false
    signal clicked()

    width: cellW
    height: cellH

    // djb2 hash -> stable cache filename per source path
    function hashPath(p) {
        let h = 5381
        for (let i = 0; i < p.length; i++) h = ((h << 5) + h + p.charCodeAt(i)) | 0
        return (h >>> 0).toString(16)
    }

    // Cache keyed by hash of full path, so renames/moves regenerate rather than serve stale images
    readonly property string cacheFile: delegateRoot.thumbCacheDir + "/" + delegateRoot.hashPath(delegateRoot.path) + ".png"
    property bool cacheChecked: false
    property bool cacheExists: false

    Process {
        id: cacheCheck
        command: ["test", "-f", delegateRoot.cacheFile]
        onExited: function(code) {
            delegateRoot.cacheExists = (code === 0)
            delegateRoot.cacheChecked = true
        }
        Component.onCompleted: running = true
    }

    Rectangle {
        id: tile
        anchors.centerIn: parent
        width: parent.width - 8
        height: parent.height - 8
        radius: 10
        clip: true
        color: "#1a1a2e"
        scale: tileArea.containsMouse ? 1.06 : 1.0
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle { width: delegateRoot.cellW * 2; height: delegateRoot.cellH * 2; radius: 22 }
        }

        Image {
            id: thumb
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            sourceSize.width: delegateRoot.cellW * 2
            sourceSize.height: delegateRoot.cellH * 2
            // Load from cache once known to exist, else load the real file
            // and save a cached copy for future opens (even after restart)
            source: delegateRoot.cacheChecked
                ? "file://" + (delegateRoot.cacheExists ? delegateRoot.cacheFile : delegateRoot.path)
                : ""
            onStatusChanged: {
                if (status === Image.Ready && delegateRoot.cacheChecked && !delegateRoot.cacheExists) {
                    grabToImage(function(result) {
                        if (result) {
                            result.saveToFile(delegateRoot.cacheFile)
                            delegateRoot.cacheExists = true
                        }
                    })
                }
            }

            Rectangle {
                anchors.fill: parent
                color: "#1a1a2e"
                visible: thumb.status !== Image.Ready
                Text { anchors.centerIn: parent; text: "…"; color: "#444444"; font.pixelSize: 16 }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: 10
            color: tileArea.containsMouse || delegateRoot.isSelected ? "#99000000" : "transparent"

            Text {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 5 }
                visible: tileArea.containsMouse || delegateRoot.isSelected
                text: delegateRoot.name
                color: "white"
                font.pixelSize: 10
                elide: Text.ElideMiddle
            }
            Text {
                anchors.centerIn: parent
                visible: delegateRoot.applying
                text: "Applying…"
                color: "white"
                font.pixelSize: 11
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: 10
            color: "transparent"
            border.width: delegateRoot.isSelected ? 2 : 0
            border.color: "#cba6f7"
            Behavior on border.width { NumberAnimation { duration: 80 } }
        }

        MouseArea {
            id: tileArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: delegateRoot.clicked()
        }
    }
}
