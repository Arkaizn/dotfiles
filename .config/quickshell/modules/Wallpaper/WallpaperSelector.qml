import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.services
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import "."

PanelWindow {
    id: root
    visible: false
    anchors {
        top: true
        left: true
    }

    implicitWidth: 800
    implicitHeight: 620
    color: "transparent"
    exclusiveZone: 0

    BackgroundEffect.blurRegion: Region {
        item: rect
        bottomLeftRadius: 12
        bottomRightRadius: 12
    }

    property bool hasBeenHovered: false
    property bool hasScannedOnce: false

    // ── Paths ──────────────────────────────────────────────────
    readonly property string wallpapersDir: Quickshell.env("HOME") + "/Pictures/Wallpapers"
    readonly property string outputPath:    Quickshell.env("HOME") + "/Pictures/Wallpapers/pywallpaper.png"
    readonly property string scriptPath:    Quickshell.env("HOME") + "/Pictures/Wallpapers/set_wallpaper.sh"

    // Disk cache dir for generated thumbnails — persists across quickshell restarts
    readonly property string thumbCacheDir: Quickshell.cachePath("wallpaper_thumbs")
    // ──────────────────────────────────────────────────────────

    // Simple, fast string hash (djb2) — used to derive a stable cache filename per source path
    function hashPath(p) {
        let h = 5381
        for (let i = 0; i < p.length; i++) {
            h = ((h << 5) + h + p.charCodeAt(i)) | 0
        }
        return (h >>> 0).toString(16)
    }

    PopupAnimation {
        id: anim
        target: rect
        direction: "top"
        enterDuration: 150
        exitDuration: 150
        onExitFinished: root.visible = false
    }

    function toggle() {
        if (root.visible) {
            anim.exit()
        } else {
            root.visible = true
            enterTimer.start()
            // Only rescan the directory the first time, or if you want to
            // pick up new files, call `scanProc.running = true` explicitly
            // (e.g. bound to a refresh button). This keeps wallModel (and
            // therefore all cached thumbnail Image items) alive between opens.
            if (!hasScannedOnce) {
                scanProc.running = true
            }
        }
    }

    Timer {
        id: enterTimer
        interval: 50
        repeat: false
        onTriggered: anim.enter()
    }

    Timer {
        id: autoCloseTimer
        interval: 500
        repeat: false
        onTriggered: {
            anim.exit()
            hasBeenHovered = false
        }
    }

    // Inverse corner — right side only, panel is flush left
    InverseCorner {
        anchors.left: rect.right
        anchors.top: rect.top
        corner: "topLeft"
        color: rect.color
        radius: 12
    }

    // Ensure the thumbnail cache directory exists before anything tries to write to it
    Process {
        id: mkdirProc
        command: ["mkdir", "-p", root.thumbCacheDir]
        Component.onCompleted: running = true
    }

    // ── Wallpaper model + scanner ──────────────────────────────
    ListModel { id: wallModel }

    Process {
        id: scanProc
        running: false
        command: [
            "bash", "-c",
            "find '" + root.wallpapersDir + "' -type f " +
            "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' \\) " +
            "| sort"
        ]

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                if (line.trim() === "") return
                wallModel.append({
                    path: line,
                    name: line.split("/").pop()
                })
            }
        }

        onStarted: {
            statusText.color = "#888888"
            statusText.text = "Scanning…"
            wallModel.clear()
        }

        onExited: function(code) {
            root.hasScannedOnce = true
            statusText.color = "#888888"
            statusText.text = wallModel.count + " found"
        }
    }

    // ── Apply wallpaper ────────────────────────────────────────
    Process {
        id: applyProc
        property string pickedPath: ""
        running: false
        command: [
            "bash", "-c",
            "cp -- '" + applyProc.pickedPath + "' '" + root.outputPath + "' && bash '" + root.scriptPath + "'"
        ]
        onExited: function(code) {
            if (code === 0) {
                statusText.color = "#a6e3a1"
                statusText.text = "✔  " + applyProc.pickedPath.split("/").pop()
            } else {
                statusText.color = "#f38ba8"
                statusText.text = "✖  failed (code " + code + ")"
            }
        }
    }

    // ── Main panel ─────────────────────────────────────────────
    Rectangle {
        id: rect
        implicitHeight: parent.height - 20
        clip: true
        opacity: 0
        y: -height
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            leftMargin: 10
            rightMargin: 10
        }
        bottomLeftRadius: 12
        bottomRightRadius: 12
        color: '#45000000'

        // 3 columns
        readonly property real cellW: (rect.width - 28) / 3
        readonly property real cellH: cellW * 0.58

        // Content pinned to bottom — reveals as rect slides down, just like the dashboard
        ColumnLayout {
            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
                margins: 10
            }
            height: rect.implicitHeight - 20
            spacing: 8

            // Header
            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Wallpapers"
                    color: "white"
                    font.pixelSize: 14
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                // Manual refresh button — since we no longer auto-rescan on every open
                Text {
                    text: "⟳"
                    color: "#aaaaaa"
                    font.pixelSize: 14
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: scanProc.running = true
                    }
                }

                Text {
                    id: statusText
                    text: "Scanning…"
                    color: "#888888"
                    font.pixelSize: 11
                    elide: Text.ElideLeft
                    Layout.maximumWidth: 200
                }
            }

            // Divider
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#33ffffff"
            }

            // Thumbnail grid — 3 columns, scrollable
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                GridView {
                    id: grid
                    width: parent.width
                    cellWidth: rect.cellW
                    cellHeight: rect.cellH

                    model: wallModel

                    // Faster wheel scroll — 1.5x multiplier, tune to taste
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: function(event) {
                            grid.contentY = Math.max(0, Math.min(
                                grid.contentHeight - grid.height,
                                grid.contentY - event.angleDelta.y * 0.8
                            ))
                            event.accepted = true
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: wallModel.count === 0 && !scanProc.running
                        text: "No wallpapers found in\n" + root.wallpapersDir
                        color: "#666666"
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: 12
                    }

                    delegate: Item {
                        id: delegateRoot
                        width: grid.cellWidth
                        height: grid.cellHeight

                        required property string path
                        required property string name

                        readonly property bool isSelected: applyProc.pickedPath === path

                        // Where this wallpaper's cached thumbnail lives on disk.
                        // Keyed by a hash of the full path so renames/moves just
                        // regenerate rather than serving a stale image.
                        readonly property string cacheFile: root.thumbCacheDir + "/" + root.hashPath(path) + ".png"

                        property bool cacheChecked: false
                        property bool cacheExists: false

                        // Check once whether a cached thumb already exists on disk
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

                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: rect.cellW * 2
                                    height: rect.cellH * 2
                                    radius: 22
                                }
                            }

                            scale: tileArea.containsMouse ? 1.06 : 1.0
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                            Image {
                                id: thumb
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                smooth: true
                                sourceSize.width: rect.cellW * 2
                                sourceSize.height: rect.cellH * 2

                                // Once we know whether a cache file exists, load from
                                // cache if possible — otherwise load the real file
                                // (and we'll grab + save a cached copy once it's ready)
                                source: delegateRoot.cacheChecked
                                    ? "file://" + (delegateRoot.cacheExists ? delegateRoot.cacheFile : delegateRoot.path)
                                    : ""

                                onStatusChanged: {
                                    if (status === Image.Ready
                                        && delegateRoot.cacheChecked
                                        && !delegateRoot.cacheExists) {
                                        // Save a small cached copy so every future open
                                        // (even after a full quickshell restart) loads
                                        // this tiny file instead of the full-res original
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
                                    Text {
                                        anchors.centerIn: parent
                                        text: "…"
                                        color: "#444444"
                                        font.pixelSize: 16
                                    }
                                }
                            }

                            // Hover / selected name overlay
                            Rectangle {
                                anchors.fill: parent
                                radius: 10
                                color: tileArea.containsMouse || isSelected ? "#99000000" : "transparent"

                                Text {
                                    anchors {
                                        bottom: parent.bottom
                                        left: parent.left
                                        right: parent.right
                                        margins: 5
                                    }
                                    visible: tileArea.containsMouse || isSelected
                                    text: name
                                    color: "white"
                                    font.pixelSize: 10
                                    elide: Text.ElideMiddle
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: applyProc.running && isSelected
                                    text: "Applying…"
                                    color: "white"
                                    font.pixelSize: 11
                                }
                            }

                            // Selection border — only when selected, never on plain hover
                            Rectangle {
                                anchors.fill: parent
                                radius: 10
                                color: "transparent"
                                border.width: isSelected ? 2 : 0
                                border.color: "#cba6f7"
                                Behavior on border.width { NumberAnimation { duration: 80 } }
                            }

                            MouseArea {
                                id: tileArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (applyProc.running) return
                                    applyProc.pickedPath = path
                                    statusText.color = "#89dceb"
                                    statusText.text = "Applying…"
                                    applyProc.running = true
                                }
                            }
                        }
                    }
                }
            }
        }

        HoverHandler {
            id: rectHover
            onHoveredChanged: {
                if (hovered) {
                    hasBeenHovered = true
                    autoCloseTimer.stop()
                } else if (hasBeenHovered) {
                    autoCloseTimer.start()
                }
            }
        }
    }
}
