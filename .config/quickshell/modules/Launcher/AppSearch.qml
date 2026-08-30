import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// App search + "recommended apps" grid.
//
// Sibling of ClipboardHistory.qml — both expose the same contract so
// Launcher.qml can drive whichever one is active identically:
//   property string query        - search text fed in from outside
//   property int maxHeight       - cap on the results list height
//   signal closeRequested()      - "an item was activated, close the panel"
//   function moveDown()/moveUp() - keyboard nav
//   function activateCurrent()   - Enter key
ColumnLayout {
    id: root

    property string query: ""
    property int maxHeight: 360
    readonly property bool isSearching: query.trim().length > 0

    signal closeRequested()

    spacing: 8

    // Full alphabetical app list
    property var allApps: [...DesktopEntries.applications.values]
        .filter(e => e.name)
        .sort((a, b) => a.name.localeCompare(b.name))

    // Re-sync the results model whenever the underlying app list itself
    // changes (e.g. desktop entries load in after startup)
    onAllAppsChanged: updateFilteredModel()
    onQueryChanged: updateFilteredModel()

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

    // Stable identity for a desktop entry, used to match old vs new items when
    // syncing the ListModel below. Falls back to name if there's no id.
    function entryKey(e) {
        return e.id !== undefined && e.id !== null ? e.id : e.name
    }

    // ── ListModel backing the results list ──
    // A real ListModel, updated incrementally via insert/remove/move rather
    // than reassigned wholesale as a fresh JS array. That's what lets
    // ListView's add/remove/displaced transitions actually fire — a plain JS
    // array swap looks like a full model reset to QML, which skips those
    // transitions and just repopulates instantly.
    ListModel {
        id: filteredModel
    }

    // Recomputes the filtered/ranked app list from the current search text,
    // then syncs `filteredModel` to match it incrementally.
    function updateFilteredModel() {
        const q = root.query.trim().toLowerCase()

        const newItems = q === "" ? [] : root.allApps
            .map(e => ({ entry: e, score: root.scoreEntry(e, q) }))
            .filter(r => r.score > 0)
            .sort((a, b) => b.score - a.score || a.entry.name.localeCompare(b.entry.name))
            .map(r => r.entry)

        root.syncListModel(filteredModel, newItems)
        resultsList.currentIndex = newItems.length > 0 ? 0 : -1
    }

    // Mutates `model` (a ListModel) in place so its contents/order end up
    // matching `newArr`, using remove/insert/move instead of clear+refill.
    function syncListModel(model, newArr) {
        const newKeys = newArr.map(root.entryKey)

        // 1) Drop rows that are no longer present (walk backwards so
        //    removing doesn't shift the indices we still need to check)
        for (let i = model.count - 1; i >= 0; i--) {
            const k = root.entryKey(model.get(i).entry)
            if (newKeys.indexOf(k) === -1) {
                model.remove(i)
            }
        }

        // 2) Walk the target order, inserting anything missing and moving
        //    anything that's out of place
        for (let i = 0; i < newArr.length; i++) {
            const k = newKeys[i]
            let curIndex = -1
            for (let j = 0; j < model.count; j++) {
                if (root.entryKey(model.get(j).entry) === k) {
                    curIndex = j
                    break
                }
            }

            if (curIndex === -1) {
                model.insert(i, { entry: newArr[i] })
            } else if (curIndex !== i) {
                model.move(curIndex, i, 1)
            }
        }
    }

    function launch(entry) {
        if (!entry) return
        entry.execute()
        root.closeRequested()
    }

    // Finds an already-open window (Toplevel) belonging to this desktop
    // entry, if any — backs the hover "Switch to app" button below.
    //
    // Wayland windows only expose a raw `appId` string (e.g. "firefox" or
    // "org.mozilla.firefox"), not a desktop-file id, so there's no direct
    // link between a Toplevel and a DesktopEntry to compare. Instead we run
    // it the other way: ask Quickshell's own heuristicLookup() to guess
    // which desktop entry *each open window* belongs to, and see if that
    // guess is the entry we're rendering. It's best-effort (same as
    // Quickshell's taskbar-style examples use) and can occasionally miss or
    // misfire on apps with unusual appIds, but there's no more reliable
    // general signal available over the foreign-toplevel protocol.
    function findToplevel(entry) {
        if (!entry) return null
        const toplevels = [...ToplevelManager.toplevels.values]
        for (const t of toplevels) {
            if (!t.appId) continue
            const matched = DesktopEntries.heuristicLookup(t.appId)
            if (matched && matched.id === entry.id) return t
        }
        return null
    }

    function moveDown() { if (root.isSearching) resultsList.incrementCurrentIndex() }
    function moveUp() { if (root.isSearching) resultsList.decrementCurrentIndex() }
    function activateCurrent() { if (root.isSearching) root.launch(resultsList.currentItem?.entry) }

    // ── Recommended apps strip — shown until the user starts typing ──
    Flow {
        id: recommendedFlow
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        opacity: root.isSearching ? 0 : 1
        visible: opacity > 0
        spacing: 8

        Behavior on opacity {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

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
        // min 1 row while searching so the "No matching apps" empty state
        // actually has room to render, instead of being clipped to 0 height
        Layout.preferredHeight: Math.min(root.maxHeight, Math.max(filteredModel.count, root.isSearching ? 1 : 0) * 44)
        Layout.bottomMargin: 4
        opacity: root.isSearching ? 1 : 0
        visible: opacity > 0
        clip: true
        model: filteredModel
        highlightMoveDuration: 80

        Behavior on opacity {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        // Layout.preferredHeight is allowed to animate here — it only
        // resizes `card` (a plain Item), not the Wayland surface.
        Behavior on Layout.preferredHeight {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }

        // ── New rows fade + slide in when they enter the filtered model ──
        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120; easing.type: Easing.OutCubic }
            NumberAnimation { property: "y"; from: 40; duration: 120; easing.type: Easing.OutCubic }
        }

        // ── Rows that drop out of the filtered results fade away ──
        remove: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: 100; easing.type: Easing.InCubic }
        }

        // ── Rows that shift position when the list re-sorts slide smoothly ──
        displaced: Transition {
            NumberAnimation { properties: "y"; duration: 120; easing.type: Easing.OutCubic }
        }

        delegate: Item {
            id: resultCell
            required property var entry
            required property int index
            width: resultsList.width
            height: 44

            // Re-evaluated whenever ToplevelManager's window list changes,
            // since findToplevel() reads ToplevelManager.toplevels.
            readonly property var toplevel: root.findToplevel(resultCell.entry)
            readonly property int switchZoneWidth: 100

            HoverHandler {
                id: resultHover
                cursorShape: Qt.PointingHandCursor
            }

            // Single TapHandler for the whole row, branching on *where*
            // within the row the tap landed, rather than stacking a second
            // TapHandler under the switch button — nested pointer handlers
            // both trying to claim the same click get unreliable fast.
            TapHandler {
                onTapped: (point) => {
                    if (resultCell.toplevel && point.position.x >= resultCell.width - resultCell.switchZoneWidth) {
                        resultCell.toplevel.activate()
                        root.closeRequested()
                    } else {
                        root.launch(resultCell.entry)
                    }
                }
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
                    source: Quickshell.iconPath(resultCell.entry.icon, "AppImage")
                }

                Text {
                    text: resultCell.entry.name
                    color: resultCell.isCurrent ? "white" : Qt.rgba(1, 1, 1, 0.75)
                    font.pixelSize: 15
                    font.weight: resultCell.isCurrent ? Font.Medium : Font.Normal
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    Behavior on color { ColorAnimation { duration: 80 } }
                }
            }

            // ── "Switch to app" — only exists as a hoverable zone; the
            // pill itself only renders while hovered, and only if the app
            // actually has an open window. HoverHandler is passive (it never
            // grabs/consumes the click), so it can sit right on top of the
            // row's TapHandler above with zero interference — the tap
            // decision is made purely by x-position, not by which handler
            // "wins".
            Item {
                id: switchZone
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: resultCell.switchZoneWidth

                Rectangle {
                    id: switchPill
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    visible: resultCell.toplevel !== null
                    height: 26
                    radius: 6
                    color: Qt.rgba(1, 1, 1, 0.16)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.28)
                    width: switchLabel.implicitWidth + 16

                    Behavior on opacity {
                        NumberAnimation { duration: 80 }
                    }

                    Text {
                        id: switchLabel
                        anchors.centerIn: parent
                        text: "Switch to app"
                        font.pixelSize: 11
                        color: "white"
                    }
                }
            }
        }

        // Friendly empty state
        Text {
            anchors.centerIn: parent
            visible: root.isSearching && filteredModel.count === 0
            text: "No matching apps"
            color: Qt.rgba(1, 1, 1, 0.35)
            font.pixelSize: 13
        }
    }
}
