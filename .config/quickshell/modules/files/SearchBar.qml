import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import "lib/FmIcons.js" as FmIcons
import "lib/FmFormat.js" as FmFormat

// Search, like Nautilus: it takes the path bar's place while it's open. Typing
// in a folder opens it (the letter goes in), Ctrl+F too; the results follow the
// typing; the filter button limits them by kind and date. Esc (or the ×)
// goes back to the folder; ↓ / Enter go to the results. It searches this folder
// and its subfolders; "Everywhere" searches the whole computer instead. A click
// anywhere else while nothing is typed closes it.
//   SearchBar { here: "Downloads"; onSearch: (query, opts) => …; onFinished; onToResults }
//   start(text)   opts: { kinds: ["image", …], since: epoch seconds | 0, everywhere: bool }
RowLayout {
    id: root

    property Item backdrop: null          // shown blurred behind its popover (the window's content)

    property string here: ""
    property alias text: field.text
    signal search(string query, var opts)
    signal finished()
    signal toResults()
    signal openFirst()                   // Enter: the first result (or the one picked) opens

    property var kinds: []
    property bool everywhere: false
    property string when: "any"
    readonly property var whens: [["any", "Any time"], ["day", "Today"], ["week", "This week"], ["month", "This month"], ["year", "This year"]]
    readonly property var kindList: [["folder", "Folders", FmIcons.g.folder], ["document", "Documents", FmIcons.g.doc],
                                     ["image", "Pictures", FmIcons.g.image], ["audio", "Music", FmIcons.g.audio],
                                     ["video", "Videos", FmIcons.g.video], ["text", "Text", FmIcons.g.text],
                                     ["archive", "Archives", FmIcons.g.archive], ["other", "Other", FmIcons.g.file]]
    readonly property bool filtered: kinds.length > 0 || when !== "any"

    spacing: Tokens.space.s6

    // (shown while the tab searches: the window binds `visible`)
    function start(text) {
        field.text = text ?? ""
        field.forceActiveFocus()
        field.cursorPosition = field.text.length
        if (field.text !== "") emit()
    }
    function finish() {
        everywhere = false
        kinds = []
        when = "any"
        finished()
    }
    function since() {
        const d = new Date(), start = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        switch (when) {
        case "day": return start.getTime() / 1000
        case "week": return start.getTime() / 1000 - 6 * 86400
        case "month": return new Date(d.getFullYear(), d.getMonth(), 1).getTime() / 1000
        case "year": return new Date(d.getFullYear(), 0, 1).getTime() / 1000
        }
        return 0
    }
    property string lastSent: ""
    function emit() { lastSent = field.text; search(field.text, { kinds: kinds, since: since(), everywhere: everywhere }) }
    onEverywhereChanged: if (field.text !== "") emit()
    // focus gone elsewhere (a click in the folder, the sidebar …) with nothing typed: the bar closes
    // (not while its own buttons / filter menu have it, nor when only the window lost focus)
    function _maybeClose() {
        if (!root.visible || field.text !== "" || field.activeFocus || filterMenu.opened || !root.Window.active) return
        for (let it = root.Window.activeFocusItem; it; it = it.parent) if (it === root) return
        finish()
    }
    Timer { id: typing; interval: Anim.medium; onTriggered: root.emit() }

    SearchField {
        id: field
        Layout.fillWidth: true
        Layout.minimumWidth: Tokens.size.row * 4
        icon: FmIcons.g.search
        placeholderText: root.everywhere ? "Search everywhere" : "Search in " + root.here + " and below"
        onActiveFocusChanged: if (!activeFocus) Qt.callLater(root._maybeClose)
        onTextEdited: typing.restart()
        onAccepted: { typing.stop(); if (root.lastSent !== text) root.emit(); root.openFirst() }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) { root.finish(); event.accepted = true }
            else if (event.key === Qt.Key_Down) { root.toResults(); event.accepted = true }
        }
    }
    // where: this folder and below (off) or the whole computer (on; the placeholder says which)
    IconButton {
        icon: "\u{F01E7}"
        active: root.everywhere
        tooltip: root.everywhere ? "Searching everywhere — click for this folder only" : "Search everywhere (the whole computer)"
        onClicked: { root.everywhere = !root.everywhere; field.forceActiveFocus() }
    }
    IconButton {
        id: filterButton
        icon: "󰈲"
        active: root.filtered || filterMenu.opened
        tooltip: "Filter by kind and date"
        onClicked: filterMenu.opened ? filterMenu.close() : filterMenu.open()
        Popup {
            id: filterMenu
            scale: AppZoom.at(filterButton)
            transformOrigin: Popup.TopRight
            x: filterButton.width - width
            y: filterButton.height + Tokens.space.s6
            width: Tokens.size.row * 6
            padding: Tokens.space.s10
            background: PopoverBackground { backdrop: root.backdrop }
        // a press on its own button doesn't close it: the click then closes it (toggle, no reopen)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
            enter: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Anim.fast; easing.type: Anim.standard }
                NumberAnimation { property: "scale"; from: 0.96 * AppZoom.at(filterButton); to: AppZoom.at(filterButton); duration: Anim.fast; easing.type: Anim.standard }
            }
            exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Anim.instant } }
            onClosed: field.forceActiveFocus()
            contentItem: ColumnLayout {
                spacing: Tokens.space.s8
                Text { text: "WHAT"; color: Colors.fade(0.4); font.pixelSize: Tokens.font.micro; font.bold: true; font.letterSpacing: 0.6; font.family: Properties.fontFamily }
                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.space.s6
                    Repeater {
                        model: root.kindList
                        FilterChip {
                            required property var modelData
                            icon: modelData[2]
                            text: modelData[1]
                            checked: root.kinds.includes(modelData[0])
                            onClicked: {
                                const k = modelData[0]
                                root.kinds = checked ? root.kinds.filter(x => x !== k) : root.kinds.concat([k])
                                root.emit()
                            }
                        }
                    }
                }
                Text { text: "CHANGED"; color: Colors.fade(0.4); font.pixelSize: Tokens.font.micro; font.bold: true; font.letterSpacing: 0.6; font.family: Properties.fontFamily }
                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.space.s6
                    Repeater {
                        model: root.whens
                        FilterChip {
                            required property var modelData
                            text: modelData[1]
                            checked: root.when === modelData[0]
                            onClicked: { root.when = modelData[0]; root.emit() }
                        }
                    }
                }
            }
        }
    }
    IconButton {
        icon: "󰅖"
        tooltip: "Close the search  (Esc)"
        onClicked: root.finish()
    }
}
