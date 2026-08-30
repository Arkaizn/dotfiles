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

    // ── Why the surface size is a constant, not a binding ──
    // implicitHeight here drives the *real* Wayland layer-shell surface
    // (via WlrLayershell), not just a QtQuick item. Every time it changes,
    // Quickshell has to renegotiate a new surface size with the compositor.
    // That's fine once (e.g. on open), but animating it — or even just
    // letting it snap around every keystroke as the results list grows and
    // shrinks — causes visible desync: ghosting, stale content bleeding
    // through, UI elements briefly rendered at the wrong position relative
    // to the new bounds.
    //
    // The fix: make the surface a fixed size, big enough for the tallest
    // possible state (a full-length results list), and never touch it again
    // while the launcher is open. All the *visible* growing/shrinking
    // happens on `card` below instead — an ordinary Rectangle inside the
    // surface, animated with a plain `Behavior on height`. That's pure
    // GPU-side compositing, not a surface reconfigure, so it can animate as
    // smoothly as any other QtQuick property.
    readonly property int maxResultsHeight: 360
    readonly property int contentSpacing: 8
    readonly property int contentMargins: 16 + 26 // matches content's anchors.margins + bottomMargin below
    implicitHeight: maxResultsHeight + contentSpacing + Properties.buttonHeight + contentMargins

    color: '#00000000'
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusiveZone: 0

    // Restricts click/hover input to the visible card instead of the whole
    // (mostly-empty, transparent) fixed-size surface. If your Quickshell
    // version doesn't support `mask` on PanelWindow, just delete this block —
    // everything else works without it, you'd just get a slightly larger
    // invisible click-catching area above the card.
    mask: Region {
        item: card
    }

    IpcHandler {
        target: "appLauncher"
        function toggle(): void {
            root.toggle()
        }
    }

    BackgroundEffect.blurRegion: Region {
        item: card
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

    // Re-sync the results model whenever the underlying app list itself changes
    // (e.g. desktop entries load in after startup)
    onAllAppsChanged: updateFilteredModel()

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
        const q = searchField.text.trim().toLowerCase()

        const newItems = q === "" ? [] : allApps
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
        root.visible = false
        searchField.text = ""
    }

    // ── Stable wrapper for the open/close slide animation ──
    // Fixed size, fills the whole (fixed-size) surface — exactly like the
    // very first version of this file. PopupAnimation targets THIS, not the
    // dynamically-sized card below. Reason: PopupAnimation almost certainly
    // animates `y` (or `scale`) directly for its slide effect, and the
    // moment something animates `y` on an item, QML silently breaks that
    // item's `anchors.bottom` binding. `card` below is bottom-anchored with
    // a *variable* height, so if PopupAnimation targeted it directly, the
    // entrance animation would finish by hard-setting `y` to some value,
    // permanently detaching it from `parent.height - card.height` — which
    // is exactly why it flashed open then vanished. By keeping the
    // open/close animation on a target that never resizes, there's nothing
    // for it to conflict with.
    Item {
        id: rect
        anchors.fill: parent

        // ── The visible card ──
        // This is the piece that actually grows/shrinks on screen, nested
        // inside the stable `rect` above so its own height animation never
        // interacts with the open/close slide.
        Rectangle {
            id: card
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: content.implicitHeight + 32
            color: "transparent"
            radius: 12

            Behavior on height {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

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
                    Layout.preferredHeight: Math.min(root.maxResultsHeight, filteredModel.count * 44)
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

                        HoverHandler {
                            id: resultHover
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            onTapped: root.launch(resultCell.entry)
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

                    onTextChanged: root.updateFilteredModel()

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
}
