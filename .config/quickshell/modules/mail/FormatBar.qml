import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import "../settings"

// The composer's formatting bar: bold / italic / underline / strike, size,
// font, color, lists, quote, link, clear formatting — on the selection, or on
// what's typed next. Also pasting: a picture goes into the text (saved in
// MailStore.composeDir, sent as an embedded image), a link alone becomes a link.
//   FormatBar { editor: someTextArea; composeDir: … }
//   toggle("bold" | "italic" | "underline" | "strikeout")  askLink()  paste()  refresh()
RowLayout {
    id: root

    property TextArea editor
    property string composeDir: ""
    spacing: 2

    // what the cursor / selection has now (refresh() when it moves)
    property bool bold: false
    property bool italic: false
    property bool underline: false
    property bool strikeout: false
    property string size: "normal"
    property string family: "sans"

    readonly property var sizes: ({ small: 12, normal: 14, large: 18, huge: 24 })
    readonly property var families: ({ sans: "Noto Sans", serif: "Noto Serif", mono: "Noto Sans Mono" })

    // with nothing selected a change is kept for what's typed next ("pending"; Qt
    // drops a format set on a bare cursor) and put on those letters once they're in
    property var pending: null              // { pos, len, changes: [f => …], color }
    function refresh() {
        if (!editor) return
        const f = editor.cursorSelection.font
        if (pending) pending.changes.forEach(c => c(f))
        bold = f.bold; italic = f.italic; underline = f.underline; strikeout = f.strikeout
        const px = f.pixelSize > 0 ? f.pixelSize : Math.round(f.pointSize * 4 / 3)
        size = Object.keys(sizes).reduce((best, k) => Math.abs(sizes[k] - px) < Math.abs(sizes[best] - px) ? k : best, "normal")
        family = Object.keys(families).find(k => families[k] === f.family) ?? "sans"
    }
    function hasSelection() { return editor.selectionStart !== editor.selectionEnd }
    function queue(change, color) {
        if (!pending) pending = { pos: editor.cursorPosition, len: editor.length, changes: [], color: "" }
        if (change) pending.changes.push(change)
        if (color) pending.color = color
        editor.forceActiveFocus()
        refresh()
    }
    function applyPending() {
        const p = pending
        pending = null
        if (!p) return
        const a = p.pos, b = editor.cursorPosition
        if (b > a) {
            editor.select(a, b)
            const f = editor.cursorSelection.font
            p.changes.forEach(c => c(f))
            editor.cursorSelection.font = f
            if (p.color) editor.cursorSelection.color = p.color
            editor.cursorPosition = b
        }
        refresh()
    }
    Connections {
        target: root.editor
        // typed: the new letters get the kept format; moved away without typing: dropped
        function onLengthChanged() { if (root.pending && root.editor.length > root.pending.len) Qt.callLater(root.applyPending) }
        function onCursorPositionChanged() {
            if (root.pending && root.editor.length === root.pending.len && root.editor.cursorPosition !== root.pending.pos) { root.pending = null; root.refresh() }
        }
    }
    function setFont(change) {
        if (!hasSelection()) return queue(change, "")
        const f = editor.cursorSelection.font
        change(f)
        editor.cursorSelection.font = f
        editor.forceActiveFocus()
        refresh()
    }
    function toggle(p) { const v = !root[p]; setFont(f => f[p] = v) }
    function setSize(k) { setFont(f => f.pixelSize = sizes[k]) }
    function setFamily(k) { setFont(f => f.family = families[k]) }
    function setColor(c) {
        if (!hasSelection()) return queue(null, c)
        editor.cursorSelection.color = c; editor.forceActiveFocus()
    }

    // ── whole lines: lists, quote ──
    function plain() { return editor.getText(0, editor.length).replace(/[\u2028\u2029]/g, "\n") }
    // the selection (or the cursor's line), widened to whole lines
    function lineRange() {
        const t = plain()
        const a = Math.min(editor.selectionStart, editor.selectionEnd), b = Math.max(editor.selectionStart, editor.selectionEnd)
        const s = t.lastIndexOf("\n", a - 1) + 1
        let e = t.indexOf("\n", b)
        if (e < 0) e = t.length
        return [s, e]
    }
    // lists and quotes as line prefixes ("• ", "1. ", "> "): Qt's list blocks shift the lines
    // after them too, and plain prefixes look the same in every mail app. Again: removed.
    function prefixLines(kind) {
        const [s, e] = lineRange()
        const t = plain()
        const lines = t.slice(s, e).split("\n")
        const pattern = kind === "bullet" ? /^• / : kind === "number" ? /^\d+\. / : /^> /
        const off = lines.every(l => pattern.test(l))
        // last line first: the positions before it stay valid
        let at = e
        for (let i = lines.length - 1; i >= 0; i--) {
            const start = at - lines[i].length
            if (off) editor.remove(start, start + pattern.exec(lines[i])[0].length)
            else {
                const pre = kind === "bullet" ? "• " : kind === "number" ? (i + 1) + ". " : "&gt; "
                editor.insert(start, kind === "quote" ? '<span style="color:#7f7f7f">' + pre + "</span>" : pre)
            }
            at = start - 1
        }
        editor.forceActiveFocus()
    }
    function list(ordered) { prefixLines(ordered ? "number" : "bullet") }
    function quote() { prefixLines("quote") }
    // the selection without any formatting (as plain lines)
    function clear() {
        const a = Math.min(editor.selectionStart, editor.selectionEnd), b = Math.max(editor.selectionStart, editor.selectionEnd)
        if (b <= a) return
        const t = editor.getText(a, b).replace(/[\u2028\u2029]/g, "\n")
        editor.remove(a, b)
        editor.insert(a, '<span style="font-weight:400; font-style:normal; text-decoration:none;">' + MailUtil.textToHtml(t) + "</span>")
        editor.forceActiveFocus()
        refresh()
    }

    // ── links ──
    property int linkFrom: 0
    property int linkTo: 0
    function askLink() {
        linkFrom = Math.min(editor.selectionStart, editor.selectionEnd)
        linkTo = Math.max(editor.selectionStart, editor.selectionEnd)
        const sel = editor.getText(linkFrom, linkTo)
        linkField.text = MailUtil.isUrl(sel) ? sel.trim() : ""
        linkPopup.open()
        linkField.forceActiveFocus()
    }
    function insertLink(url) {
        let u = url.trim()
        if (!u) return
        if (!/^(https?:|mailto:)/i.test(u)) u = (/^[^\s@]+@[^\s@]+$/.test(u) ? "mailto:" : "https://") + u
        const esc = x => x.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
        const label = linkTo > linkFrom ? editor.getText(linkFrom, linkTo) : u.replace(/^mailto:/i, "")
        // a space after it (unless there is one): what's typed next isn't part of the link
        const next = editor.getText(linkTo, Math.min(editor.length, linkTo + 1))
        editor.remove(linkFrom, linkTo)
        editor.insert(linkFrom, '<a href="' + esc(u) + '">' + esc(label) + "</a>" + (/^\s/.test(next) ? "" : "&nbsp;"))
        editor.forceActiveFocus()
    }

    // ── pasting: pictures into the text, a link alone as a link, else as usual ──
    function insertHtml(h) {
        const a = Math.min(editor.selectionStart, editor.selectionEnd), b = Math.max(editor.selectionStart, editor.selectionEnd)
        if (b > a) editor.remove(a, b)
        editor.insert(Math.min(a, editor.length), h)
    }
    function paste() {
        Jobs.run(["wl-paste", "--list-types"], (code, out) => {
            const types = code === 0 ? out.split("\n") : []
            const img = ["image/png", "image/jpeg", "image/gif", "image/webp"].find(t => types.includes(t))
            if (img) {
                const path = composeDir + "/" + Date.now().toString(36) + "." + img.split("/")[1].replace("jpeg", "jpg")
                Jobs.run(["sh", "-c", 'mkdir -p "$1" && chmod 700 "$1" && umask 077 && wl-paste --no-newline --type "$2" > "$3"',
                          "sh", composeDir, img, path], c => {
                    if (c === 0) { probe.path = path; probe.source = "file://" + path }
                })
                return
            }
            const t = Quickshell.clipboardText
            if (MailUtil.isUrl(t)) {
                const u = t.trim().replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;")
                insertHtml('<a href="' + u + '">' + u + "</a>&nbsp;")
            } else editor.paste()
        })
    }
    // the pasted picture's size first: shown at most as wide as a mail usually is
    Image {
        id: probe
        property string path: ""
        visible: false
        asynchronous: true
        onStatusChanged: {
            if (status === Image.Ready && path) {
                const w = Math.min(implicitWidth, 560)
                root.insertHtml('<img src="file://' + path + '" width="' + Math.round(w) + '">')
                path = ""; source = ""
            } else if (status === Image.Error) { path = ""; source = "" }
        }
    }

    // ── the buttons (IconButtons don't take the focus: the selection stays) ──

    IconButton { implicitWidth: 28; implicitHeight: 28; iconSize: 13; icon: "󰉤"; active: root.bold; tooltip: "Bold  (Ctrl+B)"; onClicked: root.toggle("bold") }
    IconButton { implicitWidth: 28; implicitHeight: 28; iconSize: 13; icon: "󰉷"; active: root.italic; tooltip: "Italic  (Ctrl+I)"; onClicked: root.toggle("italic") }
    IconButton { implicitWidth: 28; implicitHeight: 28; iconSize: 13; icon: "󰊇"; active: root.underline; tooltip: "Underline  (Ctrl+U)"; onClicked: root.toggle("underline") }
    IconButton { implicitWidth: 28; implicitHeight: 28; iconSize: 13; icon: "󰊀"; active: root.strikeout; tooltip: "Strikethrough"; onClicked: root.toggle("strikeout") }
    Item { implicitWidth: 6 }
    DropdownControl {
        implicitWidth: 100
        options: [{ label: "Small", value: "small" }, { label: "Normal", value: "normal" }, { label: "Large", value: "large" }, { label: "Huge", value: "huge" }]
        value: root.size
        onEdited: v => root.setSize(v)
    }
    DropdownControl {
        implicitWidth: 92
        options: [{ label: "Sans", value: "sans" }, { label: "Serif", value: "serif" }, { label: "Mono", value: "mono" }]
        value: root.family
        onEdited: v => root.setFamily(v)
    }
    IconButton {
        implicitWidth: 28; implicitHeight: 28; iconSize: 13
        id: colorButton
        icon: "󰚞"
        tooltip: "Text color"
        onClicked: colorPopup.open()
        Popup {
            id: colorPopup
            y: colorButton.height + 4
            padding: 8
            background: Rectangle {
                radius: Properties.radius + 2
                color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.97)
                border.width: Properties.panelBorderWidth
                border.color: Properties.panelBorder
            }
            enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140; easing.type: Easing.OutCubic } }
            contentItem: Row {
                spacing: 6
                Repeater {
                    model: ["#000000", "#5f6368", "#d93025", "#e8710a", "#188038", "#1a73e8", "#9334e6"]
                    Rectangle {
                        required property string modelData
                        width: 20; height: 20; radius: 10
                        color: modelData
                        border.width: swatch.containsMouse ? 2 : 1
                        border.color: Colors.fade(swatch.containsMouse ? 0.8 : 0.3)
                        MouseArea {
                            id: swatch
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { colorPopup.close(); root.setColor(parent.modelData) }
                        }
                    }
                }
            }
        }
    }
    Item { implicitWidth: 6 }
    IconButton { implicitWidth: 28; implicitHeight: 28; iconSize: 13; icon: "󰉹"; tooltip: "Bulleted list"; onClicked: root.list(false) }
    IconButton { implicitWidth: 28; implicitHeight: 28; iconSize: 13; icon: "󰉻"; tooltip: "Numbered list"; onClicked: root.list(true) }
    IconButton { implicitWidth: 28; implicitHeight: 28; iconSize: 13; icon: "󰝗"; tooltip: "Quote"; onClicked: root.quote() }
    IconButton {
        implicitWidth: 28; implicitHeight: 28; iconSize: 13
        id: linkButton
        icon: "󰌷"
        tooltip: "Link  (Ctrl+K)"
        onClicked: root.askLink()
        Popup {
            id: linkPopup
            y: linkButton.height + 4
            width: 320
            padding: 8
            background: Rectangle {
                radius: Properties.radius + 2
                color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.97)
                border.width: Properties.panelBorderWidth
                border.color: Properties.panelBorder
            }
            enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140; easing.type: Easing.OutCubic } }
            onClosed: root.editor.forceActiveFocus()
            contentItem: RowLayout {
                spacing: 6
                SearchField {
                    id: linkField
                    Layout.fillWidth: true
                    icon: "󰌷"
                    placeholderText: "https://… or an address"
                    onAccepted: { const u = text; linkPopup.close(); root.insertLink(u) }
                }
                ActionButton { text: "Add"; onClicked: { const u = linkField.text; linkPopup.close(); root.insertLink(u) } }
            }
        }
    }
    IconButton { implicitWidth: 28; implicitHeight: 28; iconSize: 13; icon: "󰉥"; tooltip: "Clear formatting (of the selection)"; onClicked: root.clear() }
    Item { Layout.fillWidth: true }
}
