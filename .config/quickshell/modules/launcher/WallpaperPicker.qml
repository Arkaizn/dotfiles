import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services

// Wallpaper picker: folder sections with thumbnail grids.
//
// Sibling of AppSearch.qml / ClipboardHistory.qml — same contract so
// Launcher.qml can drive it identically (query, maxHeight, active,
// closeRequested, moveDown/moveUp/activateCurrent). The toolbar buttons
// (expand, open folder, rescan, stop) live in Launcher's mode bar and call
// the functions below.
ColumnLayout {
    id: root

    property string query: ""
    property int maxHeight: 520
    // Launcher binds this to `mode === "wallpapers"`; first activation scans
    property bool active: false

    signal closeRequested()

    spacing: Tokens.space.s6

    // ── State exposed to the toolbar (the work is in services/Wallpapers) ──
    readonly property bool applying: Wallpapers.applying
    property string statusText: ""
    property color statusColor: Colors.textMuted

    readonly property bool hasScannedOnce: Wallpapers.scanned
    readonly property var allWallpapers: Wallpapers.items   // flat list of {path, name, relDir}
    readonly property string wallpapersDir: Wallpapers.dir

    // thumbnails per row (the Flow below has 8 px gaps, plus a little slack)
    readonly property int columns: 4
    readonly property real cellW: (width - 16 - (columns - 1) * 8 - 4) / columns     // 16 = side insets below
    readonly property real cellH: cellW * 0.58
    // thumbnails are decoded once at the wide card's cell size
    readonly property real thumbW: 230
    readonly property real thumbH: thumbW * 0.58

    // Rescan only on first open; use the rescan button to pick up new files
    // later, so thumbnails stay cached/alive between opens.
    onActiveChanged: if (active && !Wallpapers.scanned) rescan()

    Connections {
        target: Wallpapers
        function onStatusShown() {
            const st = Wallpapers.status
            root.statusText = st.text
            root.statusColor = st.tone === "ok" ? Colors.success : st.tone === "warn" ? Colors.warning
                             : st.tone === "error" ? Colors.danger : st.tone === "info" ? Colors.info : Colors.textMuted
            if (st.tone === "ok" || st.tone === "warn" || st.tone === "error") statusClearTimer.restart()
            else statusClearTimer.stop()
        }
        function onItemsChanged() { root.rebuildFolderModel() }
    }

    function rescan() { Wallpapers.scan() }
    function openFolder() { Wallpapers.openFolder() }
    function apply(path) {
        if (Wallpapers.applying) return
        Wallpapers.apply(path)
        // close right away; the command keeps running in the background
        root.closeRequested()
    }
    function stop() { Wallpapers.stop() }

    // Path relative to wallpapersDir; "" for root-level files
    function relDirOf(fullPath) {
        let base = root.wallpapersDir
        let rel = fullPath.indexOf(base) === 0 ? fullPath.substring(base.length) : fullPath
        if (rel.charAt(0) === "/") rel = rel.substring(1)
        let idx = rel.lastIndexOf("/")
        return idx >= 0 ? rel.substring(0, idx) : ""
    }

    // Rebuild folder sections from the scanned items, keeping expanded state where possible
    function rebuildFolderModel() {
        const seen = {}
        for (const w of Wallpapers.items) seen[w.relDir] = true
        let dirs = Object.keys(seen)
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

    // ── Keyboard contract ──
    // Up/Down scroll the grid, Enter applies the first search match.
    function scrollBy(dy) {
        let flick = scrollArea.contentItem
        flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + dy))
    }
    function moveDown() { scrollBy(root.cellH) }
    function moveUp() { scrollBy(-root.cellH) }
    function activateCurrent() {
        let needle = root.query.toLowerCase()
        if (needle === "") return
        let match = root.allWallpapers.find(w => w.name.toLowerCase().indexOf(needle) !== -1)
        if (match) root.apply(match.path)
    }

    Timer { id: statusClearTimer; interval: 2500; repeat: false; onTriggered: root.statusText = "" }


    ListModel { id: folderModel }
    Component.onCompleted: if (Wallpapers.scanned) rebuildFolderModel()






    Text {
        font.family: Properties.fontFamily
        visible: root.statusText.length > 0
        Layout.fillWidth: true
        text: root.statusText
        color: root.statusColor
        font.pixelSize: Tokens.font.caption
        elide: Text.ElideRight
    }

    // Folder sections: collapsible header + thumbnail grid, like browsing a directory tree
    ScrollView {
        id: scrollArea
        Layout.fillWidth: true
        Layout.fillHeight: true
        // fill whatever height Launcher gives us instead of growing to the
        // full content height (which would draw past the panel and never scroll)
        Layout.preferredHeight: 0
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function(event) {
                root.scrollBy(-event.angleDelta.y)
                event.accepted = true
            }
        }

        // inset 8 px from the scroll area's (clipping) edges: thumbnails grow
        // a little on hover and would be cut off at the sides otherwise
        ColumnLayout {
            x: 8
            width: scrollArea.availableWidth - 16
            spacing: Tokens.space.s10

            EmptyState {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.space.s20
                visible: root.hasScannedOnce && root.allWallpapers.length === 0
                compact: true
                icon: "󰸉"
                text: "No wallpapers found in\n" + root.wallpapersDir
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
                    readonly property bool effectivelyExpanded: root.query !== "" || expanded
                    readonly property var items: root.itemsForFolder(relDir, root.query)

                    // 0 = closed, 1 = open; animated, so opening / closing a folder
                    // (one, or all via the mode bar button) slides the thumbnails
                    property real openness: effectivelyExpanded ? 1 : 0
                    Behavior on openness { NumberAnimation { duration: Anim.medium; easing.type: Anim.standard } }

                    Layout.fillWidth: true
                    spacing: Tokens.space.s6
                    visible: items.length > 0 || root.query === ""

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: headerRow.implicitHeight

                        // Whole header row toggles the section; sits behind the button so
                        // the button's own click still lands on it directly (no double-toggle).
                        MouseArea {
                            anchors.fill: parent
                            enabled: root.query === ""
                            cursorShape: Qt.PointingHandCursor
                            onClicked: folderModel.setProperty(folderSection.index, "expanded", !folderSection.expanded)
                        }

                        RowLayout {
                            id: headerRow
                            anchors.fill: parent
                            spacing: Tokens.space.s8

                            Text {
                                font.family: Properties.fontFamily
                                text: folderSection.label + "  (" + folderSection.items.length + ")"
                                color: Properties.color
                                font.pixelSize: Tokens.font.body
                            }
                            Item { Layout.fillWidth: true }
                            IconButton {
                                Layout.rightMargin: Tokens.space.s12
                                icon: "󰅀"
                                rotation: -90 * (1 - folderSection.openness)    // turns with the folder
                                interactive: root.query === ""
                                onClicked: folderModel.setProperty(folderSection.index, "expanded", !folderSection.expanded)
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Colors.fade(0.18) }

                    // the thumbnails, clipped to the animated height
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: thumbs.implicitHeight * folderSection.openness
                        visible: folderSection.openness > 0.001
                        // clip only while opening / closing (hover-grown tiles at rest aren't cut)
                        clip: folderSection.openness < 0.999

                        Flow {
                            id: thumbs
                            width: parent.width
                            spacing: Tokens.space.s8
                            // slides down a little and fades in while opening
                            y: -14 * (1 - folderSection.openness)
                            opacity: folderSection.openness

                            Repeater {
                                model: folderSection.items

                                delegate: WallpaperTile {
                                    required property var modelData
                                    path: modelData.path
                                    name: modelData.name
                                    cellW: root.cellW
                                    cellH: root.cellH
                                    thumbW: root.thumbW
                                    thumbH: root.thumbH
                                    isSelected: Wallpapers.pickedPath === path
                                    applying: Wallpapers.applying && isSelected
                                    onClicked: root.apply(path)
                                }
                            }
                        }
                    }
                }
            }
            Item { implicitHeight: 4 }    // room for the last row's hover
        }
    }
}
