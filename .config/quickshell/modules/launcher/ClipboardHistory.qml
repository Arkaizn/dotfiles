import Quickshell
import Quickshell.Io
import QtQuick
import qs.components
import qs.services
import QtQuick.Layouts

// Clipboard history, backed by `cliphist` (+ `wl-copy` to restore an entry
// to the clipboard). Requires both binaries on PATH, and that something is
// actually feeding cliphist (e.g. `wl-paste --watch cliphist store` running
// as a background service).
//
// Sibling of AppSearch.qml — same contract, so Launcher.qml can drive
// either view identically. See that file for what each property/function
// means.
ColumnLayout {
    id: root

    property string query: ""
    property int maxHeight: 360
    // Only hit the `cliphist list` subprocess while this view is actually
    // the one on screen — no point polling clipboard history for a panel
    // nobody's looking at. Launcher.qml binds this to `root.mode === "clipboard"`.
    property bool active: false
    readonly property bool isSearching: query.trim().length > 0

    signal closeRequested()

    spacing: Tokens.space.s8

    onActiveChanged: if (active) refresh()
    onQueryChanged: updateFilteredModel()

    // Raw parsed rows from the last `cliphist list` call: [{ id, preview, isImage }]
    property var rawEntries: []

    function refresh() {
        Clipboard.history(list => { root.rawEntries = list; root.updateFilteredModel() })
    }



    function copyEntry(entry) {
        if (!entry) return
        Clipboard.copyEntry(entry.id)
    }

    function scoreEntry(entry, q) {
        const preview = (entry.preview || "").toLowerCase()
        if (preview.startsWith(q)) return 90
        if (preview.includes(q)) return 50
        return -1
    }

    function entryKey(e) {
        return e.id
    }

    // Same incremental-sync ListModel as AppSearch.qml — see that file for
    // the reasoning (it's what makes the add/remove/displaced transitions
    // fire instead of the list just snapping to the new contents).
    ListModel {
        id: filteredModel
    }

    function updateFilteredModel() {
        const q = root.query.trim().toLowerCase()

        const newItems = q === "" ? root.rawEntries : root.rawEntries
            .map(e => ({ entry: e, score: root.scoreEntry(e, q) }))
            .filter(r => r.score > 0)
            .sort((a, b) => b.score - a.score)
            .map(r => r.entry)

        root.syncListModel(filteredModel, newItems)
        historyList.currentIndex = newItems.length > 0 ? 0 : -1
    }

    // Duplicated from AppSearch.qml rather than shared, so each view stays a
    // self-contained, drop-in file. If the duplication starts to bother you,
    // pull this into a qs/services/ListSync.js singleton and import it from
    // both — it's a pure function, trivial to share.
    function syncListModel(model, newArr) {
        const newKeys = newArr.map(root.entryKey)

        for (let i = model.count - 1; i >= 0; i--) {
            const k = root.entryKey(model.get(i).entry)
            if (newKeys.indexOf(k) === -1) model.remove(i)
        }

        for (let i = 0; i < newArr.length; i++) {
            const k = newKeys[i]
            let curIndex = -1
            for (let j = 0; j < model.count; j++) {
                if (root.entryKey(model.get(j).entry) === k) { curIndex = j; break }
            }
            if (curIndex === -1) model.insert(i, { entry: newArr[i] })
            else if (curIndex !== i) model.move(curIndex, i, 1)
        }
    }

    function moveDown() { historyList.incrementCurrentIndex() }
    function moveUp() { historyList.decrementCurrentIndex() }
    function activateCurrent() {
        const entry = historyList.currentItem?.entry
        if (!entry) return
        root.copyEntry(entry)
        root.closeRequested()
    }

    // ── History list — always shown for this view; `query` just narrows it ──
    ListView {
        id: historyList
        // same wheel feel as the settings sidebar
        SmoothWheel { flick: historyList; step: 100 }
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(root.maxHeight, Math.max(filteredModel.count, 1) * 44)
        clip: true
        model: filteredModel
        highlightMoveDuration: 80

        Behavior on Layout.preferredHeight {
            NumberAnimation { duration: Anim.normal; easing.type: Anim.standard }
        }

        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Anim.fast; easing.type: Anim.standard }
            NumberAnimation { property: "y"; from: 40; duration: Anim.fast; easing.type: Anim.standard }
        }
        remove: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: Anim.fast; easing.type: Anim.exit }
        }
        displaced: Transition {
            NumberAnimation { properties: "y"; duration: Anim.fast; easing.type: Anim.standard }
        }

        delegate: Item {
            id: cell
            required property var entry
            required property int index
            width: historyList.width
            height: 44

            HoverHandler {
                id: cellHover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                onTapped: {
                    root.copyEntry(cell.entry)
                    root.closeRequested()
                }
            }

            readonly property bool isCurrent: historyList.currentIndex === cell.index

            Rectangle {
                anchors.fill: parent
                anchors.margins: Tokens.space.s2
                radius: 6
                visible: cell.isCurrent
                color: Colors.fade(0.13)
                border.color: Colors.line(0.22)
                border.width: 0.5
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: Tokens.space.s2
                radius: 6
                visible: cellHover.hovered && !cell.isCurrent
                color: Colors.fade(0.08)
                Behavior on color { ColorAnimation { duration: Anim.instant } }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: Tokens.space.s8
                spacing: Tokens.space.s8

                Text {
                    font.family: Properties.fontFamily
                    text: cell.entry.isImage ? "🖼" : "📋"
                    font.pixelSize: Tokens.font.label
                }

                Text {
                    font.family: Properties.fontFamily
                    text: cell.entry.preview
                    color: cell.isCurrent ? Colors.ink : Colors.fade(0.75)
                    font.pixelSize: Tokens.font.label
                    font.weight: cell.isCurrent ? Font.Medium : Font.Normal
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    Behavior on color { ColorAnimation { duration: Anim.instant } }
                }
            }
        }

        // Friendly empty state — different message depending on whether
        // there's simply no history yet, vs. a query that matched nothing.
        EmptyState {
            anchors.centerIn: parent
            visible: filteredModel.count === 0
            compact: true
            icon: root.rawEntries.length === 0 ? "󰅌" : "󰍉"
            text: root.rawEntries.length === 0 ? "No clipboard history" : "No matching entries"
        }
    }
}
