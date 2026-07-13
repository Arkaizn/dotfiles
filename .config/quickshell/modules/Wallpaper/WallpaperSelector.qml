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
    anchors { top: true; left: true }
    implicitWidth: 800
    implicitHeight: 820
    color: "transparent"
    exclusiveZone: 0

    // Layer-shell panels get no keyboard input by default; OnDemand lets the
    // search field grab focus on click without the panel being always-focused.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    BackgroundEffect.blurRegion: Region { item: rect; bottomLeftRadius: 12; bottomRightRadius: 12 }

    property bool hasBeenHovered: false
    property bool hasScannedOnce: false

    property string searchText: ""
    property var allWallpapers: []   // flat list of {path, name, relDir}
    property var folderSet: ({})     // set (object) of relDirs seen during scan

    readonly property string wallpapersDir: Quickshell.env("HOME") + "/Pictures/Wallpapers"
    readonly property string outputPath:    Quickshell.env("HOME") + "/.local/share/backgrounds/pywallpaper.png"
    readonly property string scriptPath:    Quickshell.env("HOME") + "/.config/quickshell/scripts/set_wallpaper.sh"
    readonly property string thumbCacheDir: Quickshell.cachePath("wallpaper_thumbs") // persists across restarts

    // Path relative to wallpapersDir; "" for root-level files
    function relDirOf(fullPath) {
        let base = root.wallpapersDir
        let rel = fullPath.indexOf(base) === 0 ? fullPath.substring(base.length) : fullPath
        if (rel.charAt(0) === "/") rel = rel.substring(1)
        let idx = rel.lastIndexOf("/")
        return idx >= 0 ? rel.substring(0, idx) : ""
    }

    // Rebuild folder sections from folderSet, keeping expanded state where possible
    function rebuildFolderModel() {
        let dirs = Object.keys(root.folderSet)
        let hasRoot = dirs.indexOf("") !== -1
        let subDirs = dirs.filter(d => d !== "").sort()

        let prevExpanded = {}
        for (let i = 0; i < folderModel.count; i++) {
            let e = folderModel.get(i)
            prevExpanded[e.relDir] = e.expanded
        }

        folderModel.clear()
        if (hasRoot)
            folderModel.append({ relDir: "", label: "(root)", expanded: prevExpanded[""] ?? true })
        for (const d of subDirs)
            folderModel.append({ relDir: d, label: d, expanded: prevExpanded[d] ?? true })
    }

    // Expand all if any collapsed, else collapse all
    function toggleExpandAll() {
        let anyCollapsed = false
        for (let i = 0; i < folderModel.count; i++)
            if (!folderModel.get(i).expanded) { anyCollapsed = true; break }
        for (let i = 0; i < folderModel.count; i++)
            folderModel.setProperty(i, "expanded", anyCollapsed)
    }

    // Items in one folder matching the current search text (reactive to both)
    function itemsForFolder(relDir, needleRaw) {
        let needle = needleRaw.toLowerCase()
        return root.allWallpapers.filter(w =>
            w.relDir === relDir && (needle === "" || w.name.toLowerCase().indexOf(needle) !== -1))
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
            return
        }
        root.visible = true
        enterTimer.start()
        // Rescan only on first open; use the refresh button to pick up new files later,
        // so thumbnails stay cached/alive between opens.
        if (!hasScannedOnce) scanProc.running = true
    }

    Timer { id: enterTimer; interval: 50; repeat: false; onTriggered: anim.enter() }
    Timer {
        id: autoCloseTimer
        interval: 500
        repeat: false
        onTriggered: { anim.exit(); hasBeenHovered = false }
    }
    Timer { id: statusClearTimer; interval: 2500; repeat: false; onTriggered: statusText.text = "" }

    InverseCorner {
        anchors.left: rect.right
        anchors.top: rect.top
        corner: "topLeft"
        color: rect.color
        radius: 12
    }

    Process { id: mkdirProc; command: ["mkdir", "-p", root.thumbCacheDir]; Component.onCompleted: running = true }

    ListModel { id: folderModel }

    Process {
        id: scanProc
        running: false
        // Recursive find picks up files in Wallpapers/ and any subfolders
        command: [
            "bash", "-c",
            "find '" + root.wallpapersDir + "' -type f " +
            "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' \\) | sort"
        ]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                if (line.trim() === "") return
                let relDir = root.relDirOf(line)
                root.folderSet[relDir] = true
                root.allWallpapers.push({ path: line, name: line.split("/").pop(), relDir: relDir })
            }
        }
        onStarted: {
            statusText.color = "#888888"
            statusText.text = "Scanning…"
            root.allWallpapers = []
            root.folderSet = {}
        }
        onExited: function(code) {
            root.hasScannedOnce = true
            root.allWallpapers = root.allWallpapers // reassign to trigger reactive bindings
            root.rebuildFolderModel()
            statusText.text = ""
        }
    }

    Process {
        id: applyProc
        property string pickedPath: ""
        running: false
        command: ["bash", "-c", "cp -- '" + applyProc.pickedPath + "' '" + root.outputPath + "' && bash '" + root.scriptPath + "'"]
        onExited: function(code) {
            if (code === 0) {
                statusText.color = "#a6e3a1"
                statusText.text = "✔  " + applyProc.pickedPath.split("/").pop()
            } else {
                statusText.color = "#f38ba8"
                statusText.text = "✖  failed (code " + code + ")"
            }
            statusClearTimer.restart()
        }
    }

    Process { id: openFolderProc; running: false; command: ["xdg-open", root.wallpapersDir] }

    Rectangle {
        id: rect
        implicitHeight: parent.height - 20
        clip: true
        opacity: 0
        y: -height
        anchors { top: parent.top; left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10 }
        bottomLeftRadius: 12
        bottomRightRadius: 12
        color: '#45000000'

        readonly property real cellW: (rect.width - 40) / 3
        readonly property real cellH: cellW * 0.58

        ColumnLayout {
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 10 }
            height: rect.implicitHeight - 20
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    Layout.preferredHeight: Properties.buttonHeight
                    placeholderText: "Search wallpapers…"
                    placeholderTextColor: Qt.rgba(1, 1, 1, 0.35)
                    color: Properties.color
                    font.pixelSize: 13
                    selectionColor: Qt.rgba(1, 1, 1, 0.28)
                    leftPadding: 12
                    rightPadding: clearIcon.visible ? 30 : 12
                    verticalAlignment: TextInput.AlignVCenter
                    onTextChanged: root.searchText = text

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
                }

                WallpaperButton { icon: "⛶"; tooltip: "Expand / collapse all folders"; onClicked: root.toggleExpandAll() }
                WallpaperButton { icon: "📁"; tooltip: "Open wallpapers folder"; onClicked: openFolderProc.running = true }
                WallpaperButton { icon: "⟳"; tooltip: "Rescan wallpapers"; onClicked: scanProc.running = true }
            }

            Text {
                id: statusText
                visible: text.length > 0
                Layout.fillWidth: true
                color: "#888888"
                font.pixelSize: 11
                elide: Text.ElideRight
            }

            // Folder sections: collapsible header + thumbnail grid, like browsing a directory tree
            ScrollView {
                id: scrollArea
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                readonly property real scrollSpeedMultiplier: 1

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: function(event) {
                        let flick = scrollArea.contentItem
                        flick.contentY = Math.max(0, Math.min(
                            flick.contentHeight - flick.height,
                            flick.contentY - event.angleDelta.y * scrollArea.scrollSpeedMultiplier))
                        event.accepted = true
                    }
                }

                ColumnLayout {
                    width: rect.width - 20
                    spacing: 10

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 20
                        visible: root.hasScannedOnce && root.allWallpapers.length === 0
                        text: "No wallpapers found in\n" + root.wallpapersDir
                        color: "#666666"
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: 12
                    }

                    Repeater {
                        model: folderModel

                        delegate: ColumnLayout {
                            id: folderSection
                            required property int index
                            required property string relDir
                            required property string label
                            required property bool expanded

                            // Search always shows matches regardless of collapsed state
                            readonly property bool effectivelyExpanded: root.searchText !== "" || expanded
                            readonly property var items: root.itemsForFolder(relDir, root.searchText)

                            Layout.fillWidth: true
                            spacing: 6
                            visible: items.length > 0 || root.searchText === ""

                            Item {
                                id: headerArea
                                Layout.fillWidth: true
                                implicitHeight: headerRow.implicitHeight

                                // Whole header row toggles the section; sits behind the button so
                                // the button's own click still lands on it directly (no double-toggle).
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: root.searchText === ""
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: folderModel.setProperty(folderSection.index, "expanded", !folderSection.expanded)
                                }

                                RowLayout {
                                    id: headerRow
                                    anchors.fill: parent
                                    spacing: 8

                                    Text {
                                        text: folderSection.label + "  (" + folderSection.items.length + ")"
                                        color: Properties.color
                                        font.pixelSize: 13
                                    }
                                    Item { Layout.fillWidth: true }
                                    WallpaperButton {
                                        // Only this button shows the hover/scale animation; nudged
                                        // slightly in from the edge rather than flush right.
                                        Layout.rightMargin: 20
                                        icon: folderSection.effectivelyExpanded ? "▼" : "▶"
                                        interactive: root.searchText === ""
                                        onClicked: folderModel.setProperty(folderSection.index, "expanded", !folderSection.expanded)
                                    }
                                }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1, 1, 1, 0.18) }

                            Flow {
                                Layout.fillWidth: true
                                visible: folderSection.effectivelyExpanded
                                spacing: 8

                                Repeater {
                                    model: folderSection.items

                                    delegate: WallpaperTile {
                                        required property var modelData
                                        path: modelData.path
                                        name: modelData.name
                                        cellW: rect.cellW
                                        cellH: rect.cellH
                                        thumbCacheDir: root.thumbCacheDir
                                        isSelected: applyProc.pickedPath === path
                                        applying: applyProc.running && isSelected
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

        HoverHandler {
            id: rectHover
            onHoveredChanged: {
                if (hovered) { hasBeenHovered = true; autoCloseTimer.stop() }
                else if (hasBeenHovered) autoCloseTimer.start()
            }
        }
    }
}
