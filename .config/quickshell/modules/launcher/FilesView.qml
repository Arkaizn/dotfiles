import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// Files in home by name (the file manager's search: scripts/files/filesd.py
// --search, one short process per query, the one before stopped). Enter opens
// the file in its app (a folder in Files); the button on a row shows it in its
// folder.
//
// Sibling of AppSearch.qml — same contract, so Launcher.qml can drive it the
// same way.
ColumnLayout {
    id: root

    property string query: ""
    property int maxHeight: 360
    property bool active: false

    signal closeRequested()

    spacing: Tokens.space.s8

    readonly property string home: Quickshell.env("HOME")
    property var results: []
    property bool searching: false

    // a moment after the last key, one search; a new one stops the last
    onQueryChanged: typing.restart()
    onActiveChanged: if (active) typing.restart()
    Timer { id: typing; interval: Anim.medium; onTriggered: root.search() }
    function search() {
        Jobs.cancel("launcher-files")
        const q = query.trim()
        if (!active || q.length < 2) { results = []; searching = false; return }
        searching = true
        const found = []
        Jobs.start("launcher-files", ["python3", "-I", Quickshell.shellDir + "/scripts/files/filesd.py", "--search", home, q], {
            timeout: 15000, store: false,
            onLine: (text, isErr) => {
                if (isErr) return
                try { found.push(JSON.parse(text)) } catch (e) {}
            },
            onExit: code => { if (q === root.query.trim()) { root.results = found; root.searching = false } }
        })
    }
    onResultsChanged: list.currentIndex = results.length > 0 ? 0 : -1

    function moveDown() { list.incrementCurrentIndex() }
    function moveUp() { list.decrementCurrentIndex() }
    function openItem(r) {
        if (r.dir) FileManager.open(r.path)
        else Jobs.detached(["gio", "open", r.path])
        root.closeRequested()
    }
    function activateCurrent() { const r = results[list.currentIndex]; if (r) openItem(r) }

    function glyph(r) {
        const t = r.type || ""
        return r.dir ? "󰉋" : t.startsWith("image/") ? "󰈟" : t.startsWith("video/") ? "󰈫" : t.startsWith("audio/") ? "󰈣"
             : t === "application/pdf" ? "󰈦" : t.startsWith("text/") ? "󰈙" : "󰈔"
    }

    ListView {
        id: list
        SmoothWheel { flick: list; step: 100 }
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(root.maxHeight, Math.max(root.results.length, 1) * 52)
        clip: true
        model: root.results
        highlightMoveDuration: 80
        Behavior on Layout.preferredHeight { NumberAnimation { duration: Anim.normal; easing.type: Anim.standard } }

        delegate: Pressable {
            id: cell
            required property var modelData
            required property int index
            readonly property bool isCurrent: list.currentIndex === index
            width: ListView.view.width
            height: 52
            accessibleName: modelData.name
            onClicked: root.openItem(modelData)
            Rectangle {
                anchors.fill: parent
                anchors.margins: Tokens.space.s2
                radius: Tokens.radius.lg
                color: cell.isCurrent ? Colors.fillPressed : cell.hovered ? Colors.fillHover : "transparent"
                Behavior on color { ColorAnimation { duration: Anim.fast } }
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.space.s12
                anchors.rightMargin: Tokens.space.s8
                spacing: Tokens.space.s10
                Text { text: root.glyph(cell.modelData); color: cell.modelData.dir ? Colors.accent : Colors.fade(0.6)
                       font.pixelSize: Tokens.font.title; font.family: Properties.fontFamily }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space.s1
                    Text { Layout.fillWidth: true; text: cell.modelData.name; color: Colors.ink; font.pixelSize: Tokens.font.body
                           font.family: Properties.fontFamily; elide: Text.ElideMiddle; textFormat: Text.PlainText }
                    Text { Layout.fillWidth: true; text: "~/" + cell.modelData.loc; color: Colors.fade(0.45); font.pixelSize: Tokens.font.caption
                           font.family: Properties.fontFamily; elide: Text.ElideLeft; textFormat: Text.PlainText }
                }
                IconButton {
                    icon: "󰉋"
                    tooltip: "Show in its folder"
                    onClicked: { FileManager.select(cell.modelData.path); root.closeRequested() }
                }
            }
        }
    }
    Text {
        visible: root.results.length === 0
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: root.query.trim().length < 2 ? "Type a name to find a file in your home folder"
            : root.searching ? "Searching…" : "Nothing found"
        color: Colors.fade(0.45)
        font.pixelSize: Tokens.font.small
        font.family: Properties.fontFamily
    }
}
