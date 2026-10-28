import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

Rectangle {
    id: root

    // ── Public API ────────────────────────────────────────────
    property var appStreams: []

    // Helper functions passed in (or redefined here matching parent signatures)
    function streamDisplayName(node) {
        const p = node.properties ?? {}
        return p["application.name"]
            ?? p["application.process.binary"]
            ?? node.description
            ?? node.name
            ?? "Unknown"
    }

    function streamIconSource(node) {
        const p = node.properties ?? {}
        const n = p["application.icon-name"] ?? p["application.process.binary"] ?? ""
        return n ? Quickshell.iconPath(n, true) : ""
    }

    // ── Internal state ────────────────────────────────────────
    property bool appsExpanded: false

    // ── Geometry ──────────────────────────────────────────────
    // implicitHeight = header + animated scroll area + padding
    // When appsExpanded changes, appsScrollView.height animates,
    // which changes appsCard.implicitHeight, which flows up to mainCol.
    implicitHeight: appsHeaderArea.height + 24 + appsScrollView.height

    Behavior on implicitHeight {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    radius: 10
    color: "#27000000"
    clip: true

    // ── Header (always visible) ───────────────────────────────
    Item {
        id: appsHeaderArea
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 12 }
        height: appsHeaderRow.implicitHeight + 8

        RowLayout {
            id: appsHeaderRow
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 8

            Text {
                text: "Apps"
                font { bold: true; pixelSize: 12 }
                color: "#88ffffff"
            }

            Rectangle {
                visible: root.appStreams.length > 0
                width: appCountLabel.implicitWidth + 10; height: 18; radius: 9
                color: "#40ffffff"
                Text {
                    id: appCountLabel
                    anchors.centerIn: parent
                    text: root.appStreams.length
                    color: "#ddffffff"
                    font { bold: true; pixelSize: 10 }
                }
            }

            Item { Layout.fillWidth: true }

            Text {
                text: root.appsExpanded ? "▲" : "▼"
                color: "#60ffffff"; font.pixelSize: 10
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.appsExpanded = !root.appsExpanded
        }
    }

    // ── Divider ───────────────────────────────────────────────
    Rectangle {
        visible: root.appsExpanded
        anchors {
            top: appsHeaderArea.bottom
            left: parent.left; right: parent.right
            leftMargin: 12; rightMargin: 12
        }
        height: 1; color: "#20ffffff"
    }

    // ── Collapsible scroll area ───────────────────────────────
    ScrollView {
        id: appsScrollView
        anchors {
            top: appsHeaderArea.bottom
            left: parent.left; right: parent.right
            leftMargin: 12; rightMargin: 12
            topMargin: root.appsExpanded ? 8 : 0
        }
        // Animating this height is what drives the whole panel to grow/shrink
        height: root.appsExpanded ? Math.min(appsCol.implicitHeight, 200) : 0
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AsNeeded

        Behavior on height {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        contentWidth: availableWidth

        ColumnLayout {
            id: appsCol
            width: appsScrollView.availableWidth
            spacing: 10

            Text {
                visible: root.appStreams.length === 0
                text: "No active streams"
                color: "#555555"; font.pixelSize: 12
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 6; Layout.bottomMargin: 6
            }

            Repeater {
                model: root.appStreams

                delegate: ColumnLayout {
                    id: appRow
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 4

                    Rectangle {
                        visible: appRow.index > 0
                        Layout.fillWidth: true; height: 1; color: "#20ffffff"
                    }

                    RowLayout {
                        Layout.fillWidth: true; spacing: 8

                        Image {
                            visible: source !== ""
                            width: 20; height: 20
                            source: root.streamIconSource(appRow.modelData)
                        }

                        Text {
                            text: root.streamDisplayName(appRow.modelData)
                            color: "#cdffffff"
                            font.pixelSize: 13; font.bold: true
                            Layout.fillWidth: true; elide: Text.ElideRight
                        }
                    }

                    // App volume slider — imperative pattern, no declarative value binding
                    Slider {
                        id: appVolumeSlider
                        Layout.fillWidth: true
                        from: 0.0; to: 1.0
                        value: 0

                        property var pwAudio: appRow.modelData.audio ?? null

                        Component.onCompleted: {
                            value = appRow.modelData.audio?.volume ?? 0
                        }

                        Connections {
                            target: appVolumeSlider.pwAudio
                            function onVolumeChanged() {
                                if (!appVolumeSlider.pressed)
                                    appVolumeSlider.value = appVolumeSlider.pwAudio.volume
                            }
                        }

                        onValueChanged: {
                            if (pressed && appVolumeSlider.pwAudio)
                                appVolumeSlider.pwAudio.volume = value
                        }

                        background: Rectangle {
                            x: appVolumeSlider.leftPadding
                            y: appVolumeSlider.topPadding + appVolumeSlider.availableHeight / 2 - height / 2
                            width: appVolumeSlider.availableWidth; height: 4; radius: 2
                            color: "#33ffffff"
                            Rectangle {
                                width: appVolumeSlider.visualPosition * parent.width
                                height: parent.height; radius: 2; color: "#ddffffff"
                            }
                        }
                        handle: Rectangle {
                            x: appVolumeSlider.leftPadding + appVolumeSlider.visualPosition * (appVolumeSlider.availableWidth - width)
                            y: appVolumeSlider.topPadding + appVolumeSlider.availableHeight / 2 - height / 2
                            width: 14; height: 14; radius: 7
                            color: appVolumeSlider.pressed ? "#ffffff" : "#ddffffff"
                            border.color: "#33ffffff"; border.width: 1
                        }
                    }
                }
            }
        }
    }
}
