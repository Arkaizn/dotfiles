import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import "../settings"
import "MailIcons.js" as I

// One message of a conversation: header (click to fold), body, attachments.
// The body is loaded when it's unfolded. HTML is shown on a light "paper" (mails
// are made for white backgrounds); remote images stay blocked until allowed.
Rectangle {
    id: root

    required property var msg
    property bool expanded: false
    property bool showQuote: false
    property var body: null              // mailsync's body answer
    property bool loading: false
    property string error: ""
    property bool remote: false          // remote content allowed for this message
    property bool asText: !MailStore.preferHtml
    signal reply(var m, bool all)
    signal forward(var m)
    signal viewAttachment(var m, var atts, int index)

    readonly property var atts: body?.attachments ?? []
    readonly property var invites: atts.filter(a => a.type === "text/calendar" || a.type === "application/ics" || /\.ics$/i.test(a.name))
    readonly property var images: atts.filter(a => /^image\/(png|jpeg|gif|webp|bmp)$/.test(a.type))
    readonly property bool dark: MailStore.style === "dark"

    readonly property var acc: MailStore.accountMap[msg.account]

    onExpandedChanged: if (expanded && !body) load()
    Component.onCompleted: if (expanded) load()
    // the request is cancelled when the card goes away (another message opened):
    // its answer must not land in a destroyed card, and a queued one never runs
    property var request: null
    Component.onDestruction: if (request) request.cancel()
    function load() {
        if (request) request.cancel()
        root.loading = true
        root.error = ""
        const r = MailStore.loadBody(msg, remote, res => {
            root.request = null
            root.loading = false
            if (res.ok) root.body = res
            else root.error = res.error
        })
        // answered from memory right away: already done
        if (root.loading) root.request = r
    }

    // plain text → rich text: links clickable, quoted lines dimmed (and folded away)
    function textHtml(t) {
        const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        const link = s => s.replace(/\b(https?:\/\/[^\s<>"')\]]+)/g, '<a href="$1">$1</a>')
        const lines = String(t || "").replace(/\s+$/, "").split("\n")
        const c = Colors.fade(0.45)
        const dim = "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + c.a.toFixed(2) + ")"
        const out = []
        for (const l of lines) {
            if (/^\s*>/.test(l)) {
                if (root.showQuote) out.push('<span style="color:' + dim + '">' + link(esc(l)) + '</span>')
            } else out.push(link(esc(l)))
        }
        return '<div style="white-space:pre-wrap">' + out.join("<br>") + '</div>'
    }
    // the sanitized HTML laid out for `room` px: fixed widths above it (attribute or
    // style) become 100 %, pictures wider than it shrink to it (height along)
    function fitWidths(h, room) {
        const px = v => { const m = /^\s*(\d+(?:\.\d+)?)\s*(?:px)?\s*$/.exec(v ?? ""); return m ? parseFloat(m[1]) : NaN }
        return h.replace(/<(img|table|td|th|div)\b([^>]*)>/gi, (all, tag, attrs) => {
            let a = attrs
            // style widths: a picture loses them (its attributes say it below), a box goes to 100 %
            const st = /\bstyle="([^"]*)"/i.exec(a)
            let styleW = NaN
            if (st) {
                const css = st[1].replace(/(^|;)\s*((?:min-|max-)?width)\s*:\s*([\d.]+)px\s*/gi, (m, sep, prop, n) => {
                    if (prop.toLowerCase() === "width") styleW = parseFloat(n)
                    if (parseFloat(n) <= room) return m
                    return tag.toLowerCase() === "img" || prop.toLowerCase() !== "width" ? sep : sep + "width:100%"
                })
                a = a.replace(st[0], 'style="' + css + '"')
            }
            const wm = /\swidth="([^"]*)"/i.exec(a)
            const w = wm ? px(wm[1]) : styleW
            const img = tag.toLowerCase() === "img"
            if (!(w > room)) return "<" + tag + a + ">"
            if (!img)
                return "<" + tag + (wm ? a.replace(wm[0], ' width="100%"') : a) + ">"
            const hm = /\sheight="([^"]*)"/i.exec(a)
            const ht = hm ? px(hm[1]) : NaN
            a = wm ? a.replace(wm[0], ' width="' + Math.floor(room) + '"') : a + ' width="' + Math.floor(room) + '"'
            if (ht > 0) a = a.replace(hm[0], ' height="' + Math.round(ht * room / w) + '"')
            return "<" + tag + a + ">"
        })
    }
    // a layout's table cells one below the other (like a newsletter on a phone):
    // Qt's tables add their padding and nesting on top of a cell's width, so side
    // by side they'd stick out of a narrow room again
    function stackCells(h) {
        return h.replace(/<\/?(tbody|thead|tfoot)\b[^>]*>/gi, "")
            .replace(/<(table|tr|td|th)\b([^>]*)>/gi, (m, t, a) => {
                const bg = /\sbgcolor="([^"]*)"/i.exec(a)
                a = a.replace(/\s(width|height|bgcolor|cellpadding|cellspacing|border|colspan|rowspan|valign)="[^"]*"/gi, "")
                if (bg) a = /\sstyle="/i.test(a) ? a.replace(/\sstyle="/i, ' style="background-color:' + bg[1] + ";")
                                                : a + ' style="background-color:' + bg[1] + '"'
                return "<div" + a + ">"
            })
            .replace(/<\/(table|tr|td|th)>/gi, "</div>")
    }
    readonly property int quotedLines: String(body?.text ?? "").split("\n").filter(l => /^\s*>/.test(l)).length

    readonly property string unsubscribeUrl: {
        const m = /<(https:\/\/[^>]+)>/.exec(body?.headers?.unsubscribe ?? "")
        return m ? m[1] : ""
    }

    implicitHeight: col.implicitHeight + 24
    radius: 12
    color: Colors.card
    border.width: Properties.panelBorderWidth
    border.color: Properties.cardBorder

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 10

        // ── header ──
        Item {
            Layout.fillWidth: true
            implicitHeight: head.implicitHeight
            RowLayout {
                id: head
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 10
                Avatar { size: 36; person: root.msg.from; Layout.alignment: Qt.AlignTop }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        // narrow: the address gives way first, then name and date get "…"
                        Text {
                            Layout.minimumWidth: Math.min(implicitWidth, 60)
                            Layout.maximumWidth: implicitWidth
                            Layout.fillWidth: true
                            text: MailUtil.displayName(root.msg.from)
                            color: Colors.ink
                            font.pixelSize: 13
                            font.bold: true
                            font.family: Properties.fontFamily
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1000
                            text: root.msg.from?.email ?? ""
                            color: Colors.fade(0.45)
                            font.pixelSize: 11
                            font.family: Properties.fontFamily
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.minimumWidth: Math.min(implicitWidth, 70)
                            Layout.maximumWidth: implicitWidth
                            Layout.fillWidth: true
                            text: MailUtil.longDate(root.msg.date)
                            color: Colors.fade(0.45)
                            font.pixelSize: 10
                            font.family: Properties.fontFamily
                            elide: Text.ElideRight
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.expanded
                            ? "to " + (root.msg.to ?? []).map(a => MailUtil.displayName(a)).join(", ")
                              + ((root.msg.cc ?? []).length ? "  ·  cc " + root.msg.cc.map(a => MailUtil.displayName(a)).join(", ") : "")
                            : (root.msg.preview || "")
                        color: Colors.fade(0.5)
                        font.pixelSize: 11
                        font.family: Properties.fontFamily
                        elide: Text.ElideRight
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.expanded = !root.expanded
            }
        }

        // ── remote content / unsubscribe / format ──
        Rectangle {
            Layout.fillWidth: true
            visible: root.expanded && (root.body?.remoteBlocked ?? 0) > 0 && !root.remote && !root.asText
            implicitHeight: bar.implicitHeight + 12
            radius: 9
            color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.1)
            RowLayout {
                id: bar
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 6 }
                spacing: 8
                Text { text: I.shield; color: Colors.color6; font.pixelSize: 14; font.family: Properties.fontFamily }
                Text {
                    Layout.fillWidth: true
                    text: "Remote content blocked (" + (root.body?.remoteBlocked ?? 0) + ") — it can tell the sender you opened this"
                    color: Colors.fade(0.7)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                    elide: Text.ElideRight
                }
                ActionButton { text: "Load"; onClicked: { root.remote = true; root.load() } }
                ActionButton {
                    text: "Always for this sender"
                    onClicked: { MailStore.allowRemoteFrom(root.msg.from?.email); root.remote = true; root.load() }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.expanded && root.body !== null
            spacing: 6
            Item { Layout.fillWidth: true }
            Text {
                visible: root.unsubscribeUrl !== ""
                text: '<a href="x">Unsubscribe</a>'
                textFormat: Text.StyledText
                linkColor: Colors.fade(0.55)
                font.pixelSize: 10
                font.family: Properties.fontFamily
                onLinkActivated: Qt.openUrlExternally(root.unsubscribeUrl)
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
            Text {
                visible: (root.body?.html ?? "") !== ""
                text: '<a href="x">' + (root.asText ? "Show as HTML" : "Show as text") + '</a>'
                textFormat: Text.StyledText
                linkColor: Colors.fade(0.55)
                font.pixelSize: 10
                font.family: Properties.fontFamily
                onLinkActivated: root.asText = !root.asText
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
        }

        // ── invitation ──
        Rectangle {
            Layout.fillWidth: true
            visible: root.expanded && root.invites.length > 0
            implicitHeight: invRow.implicitHeight + 14
            radius: 9
            color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.1)
            RowLayout {
                id: invRow
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 6 }
                spacing: 8
                Text { text: "󰃭"; color: Colors.color6; font.pixelSize: 15; font.family: Properties.fontFamily }
                Text {
                    id: invNote
                    Layout.fillWidth: true
                    property string state: ""
                    text: state || "Calendar invitation"
                    color: Colors.fade(0.75)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                    elide: Text.ElideRight
                }
                ActionButton {
                    icon: "󰐕"
                    text: "Add to calendar"
                    onClicked: MailStore.addToCalendar(root.msg, root.invites[0].index, res => {
                        invNote.state = res.ok ? "Opened in the calendar's import" : res.error
                    })
                }
            }
        }

        // ── body ──
        RowLayout {
            visible: root.expanded && (root.loading || root.error !== "")
            Layout.fillWidth: true
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: root.loading ? "Loading…" : "󰀦  " + root.error
                color: root.error ? Colors.red : Colors.fade(0.5)
                font.pixelSize: 12
                font.family: Properties.fontFamily
                wrapMode: Text.Wrap
            }
            ActionButton { visible: !root.loading && root.error !== ""; icon: "󰑐"; text: "Try again"; onClicked: root.load() }
        }

        // HTML on paper, sized like a desktop mail app does it. A layout made for a
        // fixed width (newsletters: ~600 px):
        //   room enough   → at that width, in the middle (not a narrow column on the left)
        //   a bit short   → scaled down a little (down to 85 %), the layout stays as made
        //   much too wide → laid out again in the room: widths above it shrink to it,
        //                   pictures with them (compact, readable text — not just smaller)
        // A flowing message takes the room; pictures wider than it shrink to fit.
        Rectangle {
            id: paper
            Layout.fillWidth: true
            visible: root.expanded && root.body !== null && !root.asText && (root.body.html ?? "") !== ""
            readonly property real room: width - (root.dark ? 0 : 28)
            readonly property real design: root.body?.htmlWidth ?? 0
            readonly property bool layout: design >= 360
            readonly property real fit: layout && design > room && room > 0 && room / design >= 0.85 ? room / design : 1
            // compact: the room in steps of 40 px, so resizing doesn't lay it out on every pixel
            readonly property int reflowAt: layout && design * 0.85 > room || !layout ? Math.max(200, Math.floor(room / 40) * 40) : 0
            readonly property real textWidth: !layout ? room : fit < 1 ? design : Math.min(design, room)
            implicitHeight: htmlView.implicitHeight * fit + (root.dark ? 4 : 28)
            radius: 10
            color: root.dark ? "transparent" : "#fbfaf8"
            clip: true
            TextEdit {
                id: htmlView
                x: Math.max(root.dark ? 0 : 14, (paper.width - width * paper.fit) / 2)
                y: root.dark ? 2 : 14
                width: paper.textWidth
                scale: paper.fit
                transformOrigin: Item.TopLeft
                readOnly: true
                selectByMouse: true
                textFormat: TextEdit.RichText
                wrapMode: TextEdit.Wrap
                // dark style: links in the theme's accent (Qt's default blue is hard to read on dark)
                text: paper.visible && root.body ? (root.dark ? "<style>a { color: " + Colors.color6 + "; }</style>" : "")
                      + (paper.reflowAt === 0 ? root.body.html
                         : paper.layout ? root.stackCells(root.fitWidths(root.body.html, paper.reflowAt))
                         : root.fitWidths(root.body.html, paper.reflowAt)) : ""
                color: root.dark ? Colors.fade(0.88) : "#1d1d1f"
                selectionColor: root.dark ? Colors.fade(0.28) : "#a8c7fa"
                selectedTextColor: root.dark ? Colors.ink : "#1d1d1f"
                font.pixelSize: 13
                onLinkActivated: link => Qt.openUrlExternally(link)
                HoverHandler { cursorShape: htmlView.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
            }
        }

        // plain text
        TextEdit {
            id: textView
            Layout.fillWidth: true
            visible: root.expanded && root.body !== null && (root.asText || (root.body.html ?? "") === "")
            readOnly: true
            selectByMouse: true
            textFormat: TextEdit.RichText
            wrapMode: TextEdit.Wrap
            text: visible ? root.textHtml(root.body.text) : ""
            color: Colors.fade(0.88)
            selectionColor: Colors.fade(0.28)
            font.pixelSize: 13
            font.family: Properties.fontFamily
            onLinkActivated: link => Qt.openUrlExternally(link)
            HoverHandler { cursorShape: textView.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
        }
        Text {
            visible: textView.visible && root.quotedLines > 0
            text: '<a href="x">' + (root.showQuote ? "Hide quoted text" : "Show quoted text (" + root.quotedLines + " lines)") + '</a>'
            textFormat: Text.StyledText
            linkColor: Colors.fade(0.5)
            font.pixelSize: 11
            font.family: Properties.fontFamily
            onLinkActivated: root.showQuote = !root.showQuote
            HoverHandler { cursorShape: Qt.PointingHandCursor }
        }

        // ── attachments ──
        Flow {
            Layout.fillWidth: true
            visible: root.expanded && (root.body?.attachments ?? []).length > 0
            spacing: 6
            Repeater {
                model: root.body?.attachments ?? []
                Rectangle {
                    id: att
                    required property var modelData
                    property string note: ""
                    implicitWidth: attRow.implicitWidth + 16
                    implicitHeight: 34
                    radius: 9
                    color: attMouse.containsMouse ? Colors.fade(0.08) : Colors.fade(0.04)
                    border.width: 1
                    border.color: Colors.fade(0.06)
                    RowLayout {
                        id: attRow
                        anchors.verticalCenter: parent.verticalCenter
                        x: 8
                        spacing: 6
                        Text { text: I.clip; color: Colors.fade(0.5); font.pixelSize: 12; font.family: Properties.fontFamily }
                        Text {
                            Layout.maximumWidth: 220
                            text: att.note || att.modelData.name
                            color: att.note ? Colors.color6 : Colors.fade(0.85)
                            font.pixelSize: 11
                            font.family: Properties.fontFamily
                            elide: Text.ElideMiddle
                        }
                        Text { text: Format.bytes(att.modelData.size); color: Colors.fade(0.4); font.pixelSize: 10; font.family: Properties.fontFamily }
                        IconButton {
                            implicitWidth: 22; implicitHeight: 22; iconSize: 11
                            icon: I.download
                            tooltip: "Save to " + MailStore.saveDir
                            onClicked: MailStore.saveAttachment(root.msg, att.modelData.index, false, res => {
                                att.note = res.ok ? "Saved: " + res.path.split("/").pop() : res.error
                            })
                        }
                    }
                    MouseArea {
                        id: attMouse
                        anchors.fill: parent
                        anchors.rightMargin: 30
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.viewAttachment(root.msg, root.atts, att.modelData.index)
                        ToolTip.visible: containsMouse
                        ToolTip.text: "View " + att.modelData.name
                    }
                }
            }
        }

        // image attachments shown under the message (settings: mail → attachments inline)
        Repeater {
            model: root.expanded && MailStore.inlineAttachments ? root.images.slice(0, 8) : []
            Image {
                id: inl
                required property var modelData
                Layout.fillWidth: true
                Layout.maximumWidth: implicitWidth > 0 ? implicitWidth : 600
                Layout.preferredHeight: implicitWidth > 0 ? Math.min(implicitHeight, width * implicitHeight / implicitWidth) : 0
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
                Component.onCompleted: MailStore.view(root.msg, modelData.index, res => { if (res.ok && res.kind === "image") inl.source = "file://" + res.path })
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.viewAttachment(root.msg, root.atts, inl.modelData.index)
                }
            }
        }

        // ── per message ──
        RowLayout {
            Layout.fillWidth: true
            visible: root.expanded
            spacing: 6
            ActionButton { icon: I.reply; text: "Reply"; onClicked: root.reply(root.msg, false) }
            ActionButton { icon: I.replyAll; text: "Reply all"; visible: (root.msg.to ?? []).length + (root.msg.cc ?? []).length > 1
                           onClicked: root.reply(root.msg, true) }
            ActionButton { icon: I.forward; text: "Forward"; onClicked: root.forward(root.msg) }
            Item { Layout.fillWidth: true }
        }
    }
}
