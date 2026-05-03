import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import "."

PanelWindow {
    id: root
    visible: false
    anchors {
        top: true
        left: true
    }

    implicitWidth: 480
    implicitHeight: 420
    color: "transparent"
    exclusiveZone: 0

    // ── Paths ─────────────────────────────────────────────────
    readonly property string wallpapersDir: Quickshell.env("HOME") + "/Pictures/Wallpapers"
    readonly property string outputPath:    Quickshell.env("HOME") + "/.config/hypr/wallpapers/pywallpaper.png"
    readonly property string scriptPath:    Quickshell.env("HOME") + "/.config/hypr/wallpapers/set_wallpaper.sh"
    // ─────────────────────────────────────────────────────────

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
            anim.enter()
            // re-scan every time the panel opens
            scanProc.running = true
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

    // ── Recursive find via `find` command ─────────────────────
    // Populates wallModel with { path, name } objects
    ListModel { id: wallModel }

    Process {
        id: scanProc
        running: true   // scan once on startup too
        command: [
            "bash", "-c",
            "find '" + root.wallpapersDir + "' -type f " +
            "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' \\) " +
            "| sort"
        ]
        property string buffer: ""

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
            wallModel.clear()
            scanProc.buffer = ""
        }

        onExited: function(code) {
            statusText.color = "#888888"
            statusText.text = wallModel.count + " found"
        }
    }

    // ── Copy + run script ─────────────────────────────────────
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

    // ── Main panel ────────────────────────────────────────────
    Rectangle {
        id: rect
        implicitHeight: parent.height - 20
        clip: true
        opacity: 1
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

        ColumnLayout {
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                margins: 10
            }
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

                Text {
                    id: statusText
                    text: "Scanning…"
                    color: "#888888"
                    font.pixelSize: 11
                    elide: Text.ElideLeft
                    Layout.maximumWidth: 240
                }
            }

            // Divider
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#33ffffff"
            }

            // Thumbnail grid
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                GridView {
                    id: grid
                    width: parent.width
                    cellWidth: (root.implicitWidth - 28) / 2
                    cellHeight: cellWidth * 0.6

                    model: wallModel

                    Text {
                        anchors.centerIn: parent
                        visible: wallModel.count === 0 && !scanProc.running
                        text: "No wallpapers found in\n" + root.wallpapersDir
                        color: "#666666"
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: 12
                    }

                    delegate: Item {
                        width: grid.cellWidth
                        height: grid.cellHeight

                        required property string path
                        required property string name

                        readonly property bool isSelected: applyProc.pickedPath === path

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 4
                            radius: 8
                            color: "#1a1a2e"
                            clip: true

                            Image {
                                id: thumb
                                anchors.fill: parent
                                source: "file://" + path
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                smooth: true

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

                            // Hover / selected overlay
                            Rectangle {
                                anchors.fill: parent
                                radius: 8
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

                            // Selection border
                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: "transparent"
                                border.width: isSelected ? 2 : (tileArea.containsMouse ? 1 : 0)
                                border.color: isSelected ? "#cba6f7" : "#89b4fa"
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
    }
}
