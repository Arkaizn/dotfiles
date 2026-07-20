import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Wayland
import qs.components
import qs.services
import QtQuick.Effects

PanelWindow {
    id: root
    visible: false

    // NOTE: only "bottom" is anchored (no left/right), which is what centers
    // this horizontally in Quickshell — same trick the dashboard uses.
    anchors {
        bottom: true
    }
    implicitWidth: 640
    implicitHeight: content.implicitHeight + 32
    color: '#00000000'
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusiveZone: 0

    IpcHandler {
        target: "appLauncher"
        function toggle(): void {
            root.toggle()
        }
    }

    BackgroundEffect.blurRegion: Region {
        item: rect
        topLeftRadius: 12
        topRightRadius: 12
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
            searchField.text = ""
            enterTimer.start()
        }
    }

    Timer {
        id: enterTimer
        interval: 50
        repeat: false
        onTriggered: {
            anim.enter()
            searchField.forceActiveFocus()
        }
    }

    // Whether the user has actually typed something
    readonly property bool isSearching: searchField.text.trim().length > 0

    // Full alphabetical app list
    property var allApps: [...DesktopEntries.applications.values]
        .filter(e => e.name)
        .sort((a, b) => a.name.localeCompare(b.name))

    // TODO: back this with real usage-frequency data (frecency) once that's
    // tracked somewhere. For now it's just a placeholder slice of apps so the
    // "recommended" row has something to show before you start typing.
    property var recommendedApps: allApps.slice(0, 8)

    // Escapes regex special characters so the query can be used safely inside a RegExp
    function escapeRegex(s) {
        return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    }

    // Ranks how well an app matches the query. Higher is better; -1 means "no match".
    // Name matches are weighted far above comment/keyword matches, so e.g. searching
    // "steam" surfaces the Steam app itself before games that merely have "Steam" in
    // their auto-generated Keywords= line.
    function scoreEntry(e, q) {
        const name = (e.name || "").toLowerCase()
        const comment = (e.comment || "").toLowerCase()
        const keywords = (e.keywords || []).join(" ").toLowerCase()
        const wordBoundary = new RegExp("\\b" + root.escapeRegex(q))

        if (name === q) return 100
        if (name.startsWith(q)) return 90
        if (wordBoundary.test(name)) return 80
        if (name.includes(q)) return 70
        if (comment.startsWith(q)) return 50
        if (wordBoundary.test(comment)) return 40
        if (comment.includes(q)) return 30
        if (keywords.includes(q)) return 20
        return -1
    }

    // Filtered + relevance-sorted list of apps, recomputed whenever the query changes
    property var filteredApps: {
        const q = searchField.text.trim().toLowerCase()
        if (q === "") return []

        return allApps
            .map(e => ({ entry: e, score: root.scoreEntry(e, q) }))
            .filter(r => r.score > 0)
            .sort((a, b) => b.score - a.score || a.entry.name.localeCompare(b.entry.name))
            .map(r => r.entry)
    }

    function launch(entry) {
        if (!entry) return
        entry.execute()
        root.visible = false
        searchField.text = ""
    }

    Rectangle {
        id: rect
        anchors.fill: parent
        color: "transparent"
        radius: 12

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16
            anchors.bottomMargin: 26
            spacing: 8

            // ── Recommended apps strip — shown until the user starts typing ──
            Flow {
                id: recommendedFlow
                Layout.fillWidth: true
                Layout.bottomMargin: 4
                visible: !root.isSearching
                spacing: 8

                Repeater {
                    model: root.recommendedApps

                    Item {
                        id: recCell
                        required property var modelData
                        width: 96
                        height: 72

                        HoverHandler {
                            id: recHover
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            onTapped: root.launch(recCell.modelData)
                        }

                        // Hover scale — same snappy spring feel as the calendar day cells
                        Behavior on scale {
                            NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                        }
                        scale: recHover.hovered ? 1.20 : 1.0

                        // ── Hover highlight — soft fill only, no border/gradient ──
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 4
                            radius: 6
                            visible: recHover.hovered
                            color: Qt.rgba(1, 1, 1, 0.08)
                            Behavior on color { ColorAnimation { duration: 80 } }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 4

                            Item { Layout.fillHeight: true }

                            IconImage {
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: 32
                                implicitHeight: 32
                                source: Quickshell.iconPath(recCell.modelData.icon, "AppImage")
                            }

                            Text {
                                Layout.fillWidth: true
                                text: recCell.modelData.name
                                color: Qt.rgba(1, 1, 1, 0.75)
                                font.pixelSize: 12
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            // ── Full search results — shown only once there's a query ──
            ListView {
                id: resultsList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(360, filteredApps.length * 44)
                Layout.bottomMargin: 4
                visible: root.isSearching
                clip: true
                model: filteredApps
                currentIndex: 0
                highlightMoveDuration: 80

                delegate: Item {
                    id: resultCell
                    required property var modelData
                    required property int index
                    property var entry: modelData
                    width: resultsList.width
                    height: 44

                    HoverHandler {
                        id: resultHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: root.launch(resultCell.modelData)
                    }

                    readonly property bool isCurrent: resultsList.currentIndex === resultCell.index

                    // ── Keyboard-selected row — persistent soft fill + border ──
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: 6
                        visible: resultCell.isCurrent
                        color: Qt.rgba(1, 1, 1, 0.13)
                        border.color: Qt.rgba(1, 1, 1, 0.22)
                        border.width: 0.5
                    }

                    // ── Pointer hover — soft fill only, hidden on the already-selected row ──
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: 6
                        visible: resultHover.hovered && !resultCell.isCurrent
                        color: Qt.rgba(1, 1, 1, 0.08)
                        Behavior on color { ColorAnimation { duration: 80 } }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8
                        
                        IconImage {
                            implicitWidth: 20
                            implicitHeight: 20
                            source: Quickshell.iconPath(resultCell.modelData.icon, "AppImage")
                        }

                        Text {
                            text: resultCell.modelData.name
                            color: resultCell.isCurrent ? "white" : Qt.rgba(1, 1, 1, 0.75)
                            font.pixelSize: 15
                            font.weight: resultCell.isCurrent ? Font.Medium : Font.Normal
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            Behavior on color { ColorAnimation { duration: 80 } }
                        }
                    }
                }

                // Friendly empty state
                Text {
                    anchors.centerIn: parent
                    visible: root.isSearching && filteredApps.length === 0
                    text: "No matching apps"
                    color: Qt.rgba(1, 1, 1, 0.35)
                    font.pixelSize: 13
                }
            }

            TextField {
                id: searchField
                Layout.fillWidth: true
                Layout.preferredHeight: Properties.buttonHeight
                placeholderText: "Search"
                placeholderTextColor: Qt.rgba(1, 1, 1, 0.35)
                color: Properties.color
                font.pixelSize: 13
                verticalAlignment: TextInput.AlignVCenter

                background: Rectangle {
                    radius: Properties.radius
                    color: Qt.rgba(0, 0, 0, 0.18)
                    border.width: 1.5
                    border.color: Qt.rgba(1, 1, 1, searchField.activeFocus ? 0.28 : 0.18)
                    gradient: ButtonGradient { hovered: searchField.activeFocus }
                }

                Text {
                    id: clearIcon
                    text: "✕"
                    color: Qt.rgba(1, 1, 1, 0.5)
                    font.pixelSize: 11
                    visible: searchField.text.length > 0
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: searchField.text = ""
                    }
                }

                Keys.onDownPressed: if (root.isSearching) resultsList.incrementCurrentIndex()
                Keys.onUpPressed: if (root.isSearching) resultsList.decrementCurrentIndex()
                Keys.onReturnPressed: if (root.isSearching) root.launch(resultsList.currentItem?.entry)

                // Esc always closes. Delete only closes when the field is already
                // empty, so it doesn't fight with deleting characters while typing.
                Keys.onEscapePressed: anim.exit()
                Keys.onDeletePressed: (event) => {
                    if (searchField.text.length === 0) {
                        anim.exit()
                    } else {
                        event.accepted = false
                    }
                }
            }
        }
    }
}
