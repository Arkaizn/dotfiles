import QtQuick
import Quickshell.Widgets
import qs.services

// A single wallpaper thumbnail tile: disk-cached preview image, hover
// zoom/overlay with filename, selection border, and an "Applying…" state.
//
// Usage:
//   WallpaperTile {
//       path: modelData.path
//       name: modelData.name
//       cellW: rect.cellW
//       cellH: rect.cellH
//       isSelected: Wallpapers.pickedPath === path
//       applying: Wallpapers.applying && isSelected
//       onClicked: { ... }
//   }
Item {
    id: delegateRoot

    required property string path
    required property string name
    property real cellW: 100
    property real cellH: 58
    // decode size of the thumbnail: fixed, so the card's width animation
    // (which changes cellW every frame) doesn't reload the images
    property real thumbW: cellW
    property real thumbH: cellH
    property bool isSelected: false
    property bool applying: false
    signal clicked()

    width: cellW
    height: cellH

    // the cached thumbnail (services/Wallpapers lists the cache once per scan)
    readonly property string cacheFile: Wallpapers.thumbFor(delegateRoot.path)
    readonly property bool cacheExists: Wallpapers.hasThumb(delegateRoot.path)

    // rounded clip without an offscreen layer per tile (was an OpacityMask)
    ClippingRectangle {
        id: tile
        anchors.centerIn: parent
        width: parent.width - 8
        height: parent.height - 8
        radius: Tokens.radius.lg
        color: Colors.surfaceWell
        scale: tileArea.pressed ? Properties.onPressedButtonScale : tileArea.containsMouse ? 1.06 : 1.0
        Behavior on scale { NumberAnimation { duration: Anim.fast; easing.type: Anim.standard } }

        Image {
            id: thumb
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            sourceSize.width: delegateRoot.thumbW * 2
            sourceSize.height: delegateRoot.thumbH * 2
            // the cached copy once it exists, else the real file (then saved
            // below, for future opens even after a restart). Encoded per path
            // segment: a # or ? in a file name is part of the name, not the URL.
            source: "file://" + (delegateRoot.cacheExists ? delegateRoot.cacheFile : delegateRoot.path).split("/").map(encodeURIComponent).join("/")
            onStatusChanged: {
                if (status === Image.Ready && !delegateRoot.cacheExists && thumb.Window.window) {
                    grabToImage(function(result) {
                        if (result && result.saveToFile(delegateRoot.cacheFile)) Wallpapers.thumbSaved(delegateRoot.path)
                    })
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Colors.surfaceWell
                visible: thumb.status !== Image.Ready
                Text { font.family: Properties.fontFamily; anchors.centerIn: parent; text: "…"; color: Colors.textFaint; font.pixelSize: Tokens.font.subtitle }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: Tokens.radius.lg
            color: tileArea.containsMouse || delegateRoot.isSelected ? Colors.shade(0.6) : "transparent"

            Text {
                font.family: Properties.fontFamily
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 5 }
                visible: tileArea.containsMouse || delegateRoot.isSelected
                text: delegateRoot.name
                color: Colors.ink
                font.pixelSize: Tokens.font.micro
                elide: Text.ElideMiddle
            }
            Text {
                font.family: Properties.fontFamily
                anchors.centerIn: parent
                visible: delegateRoot.applying
                text: "Applying…"
                color: Colors.ink
                font.pixelSize: Tokens.font.caption
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: Tokens.radius.lg
            color: "transparent"
            border.width: delegateRoot.isSelected ? 2 : 0
            border.color: Colors.accent
            Behavior on border.width { NumberAnimation { duration: Anim.instant } }
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
