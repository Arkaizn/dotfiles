import Quickshell
import Quickshell.Io
import QtQuick
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

    spacing: 8

    onActiveChanged: if (active) refresh()
    onQueryChanged: updateFilteredModel()

    // Raw parsed rows from the last `cliphist list` call: [{ id, preview, isImage }]
    property var rawEntries: []

    function refresh() {
        listProc.running = false
        listProc.running = true
    }

    // `cliphist list` prints one entry per line as `<id>\t<preview>`. For
    // images the preview is a "[[ binary data ... ]]" placeholder rather
    // than readable text, which we swap for a friendlier label.
    Process {
        id: listProc
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.rawEntries = this.text
                    .split("\n")
                    .map(line => {
                        const tab = line.indexOf("\t")
                        if (tab === -1) return null
                        const id = line.slice(0, tab)
                        // cliphist ids are always numeric. If that's ever
                        // not true, skip the line rather than risk shell-
                        // interpolating something unexpected when copying
                        // it back below.
                        if (!/^\d+$/.test(id)) return null
                        const preview = line.slice(tab + 1)
                        const isImage = preview.startsWith("[[ binary data")
                        return { id: id, preview: isImage ? "Image" : preview, isImage: isImage }
                    })
                    .filter(e => e !== null)
                root.updateFilteredModel()
            }
        }
    }

    // Fire-and-forget: decode the entry by id and push it back onto the
    // system clipboard via wl-copy. `entry.id` is validated as digits-only
    // above, so it's the only thing ever interpolated into the shell
    // command — there's nothing here that needs escaping.
    Process {
        id: copyProc
    }

    function copyEntry(entry) {
        if (!entry) return
        copyProc.command = ["sh", "-c", "printf '%s\\t' " + entry.id + " | cliphist decode | wl-copy"]
        copyProc.running = false
        copyProc.running = true
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
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(root.maxHeight, Math.max(filteredModel.count, 1) * 44)
        clip: true
        model: filteredModel
        highlightMoveDuration: 80

        Behavior on Layout.preferredHeight {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }

        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120; easing.type: Easing.OutCubic }
            NumberAnimation { property: "y"; from: 40; duration: 120; easing.type: Easing.OutCubic }
        }
        remove: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: 100; easing.type: Easing.InCubic }
        }
        displaced: Transition {
            NumberAnimation { properties: "y"; duration: 120; easing.type: Easing.OutCubic }
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
                anchors.margins: 2
                radius: 6
                visible: cell.isCurrent
                color: Qt.rgba(1, 1, 1, 0.13)
                border.color: Qt.rgba(1, 1, 1, 0.22)
                border.width: 0.5
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: 6
                visible: cellHover.hovered && !cell.isCurrent
                color: Qt.rgba(1, 1, 1, 0.08)
                Behavior on color { ColorAnimation { duration: 80 } }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                Text {
                    text: cell.entry.isImage ? "🖼" : "📋"
                    font.pixelSize: 14
                }

                Text {
                    text: cell.entry.preview
                    color: cell.isCurrent ? "white" : Qt.rgba(1, 1, 1, 0.75)
                    font.pixelSize: 14
                    font.weight: cell.isCurrent ? Font.Medium : Font.Normal
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    Behavior on color { ColorAnimation { duration: 80 } }
                }
            }
        }

        // Friendly empty state — different message depending on whether
        // there's simply no history yet, vs. a query that matched nothing.
        Text {
            anchors.centerIn: parent
            visible: filteredModel.count === 0
            text: root.rawEntries.length === 0 ? "No clipboard history" : "No matching entries"
            color: Qt.rgba(1, 1, 1, 0.35)
            font.pixelSize: 13
        }
    }
}
