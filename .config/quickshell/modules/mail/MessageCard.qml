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
// are made for white backgrounds) or, in dark mode (the default), with the
// sender's colors turned dark by mailsync; remote images stay blocked until allowed.
// Links: the one under the pointer goes to linkHover (the reader's bar shows where it
// leads), one that looks like a trick (MailUtil.linkCheck) opens on the second click,
// right-click: open / copy. "Show headers": who sent it to whom, the servers' checks
// (SPF / DKIM / DMARC), how it's built, the raw header. Dates in the text are links
// too (qsdate:, MailUtil.linkDates): a click makes a calendar event. Save .eml: the
// whole message as a file.
Rectangle {
    id: root

    // (first: used further down)
    // over a message view: the link under the pointer (linkAt on every move); its
    // linkChanged goes to hoverLinkAt. The pointing hand: over a link a small spot with the
    // hand follows the pointer (another item under it always updates the shown cursor; a
    // cursorShape changing under a resting pointer may not). Nothing here takes buttons:
    // selecting and clicking links still reach the view
    component LinkHover: MouseArea {
        required property TextEdit view
        property string link: ""
        property point at: Qt.point(0, 0)
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        cursorShape: Qt.IBeamCursor
        onPositionChanged: m => { at = Qt.point(m.x, m.y); link = view.linkAt(m.x, m.y) }
        onExited: link = ""
        MouseArea {
            visible: parent.link !== ""
            x: parent.at.x - 12
            y: parent.at.y - 12
            width: 24
            height: 24
            acceptedButtons: Qt.NoButton
            cursorShape: Qt.PointingHandCursor
        }
    }
    // a small heading in the headers panel
    component SrcTitle: Text {
        color: Colors.fade(0.5)
        font.pixelSize: 10
        font.bold: true
        font.letterSpacing: 1.1
        font.family: Properties.fontFamily
    }

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
    signal linkHover(var info)               // MailUtil.linkCheck + armed, or null

    // ── links ──
    readonly property var linkTexts: body?.html ? MailUtil.anchorTexts(body.html) : ({})
    property string armedLink: ""            // a suspicious link clicked once: the next click opens it
    property string hoveredLink: ""
    function linkInfo(url) {
        if (!url) return null
        const d = MailUtil.parseDateLink(url)
        if (d) return { url: url, scheme: "qsdate", host: "", site: "", warn: "", armed: false, label: dateLabel(d) }
        const i = MailUtil.linkCheck(url, linkTexts[url] ?? [])
        i.armed = armedLink === url
        return i
    }
    function hoverLinkAt(url) { hoveredLink = url; linkHover(linkInfo(url)) }
    function openLink(url) {
        const d = MailUtil.parseDateLink(url)
        if (d) { addDate(d); return }
        const i = linkInfo(url)
        if (i.warn && !i.armed) { armedLink = url; armTimer.restart(); linkHover(linkInfo(url)); return }
        armedLink = ""
        Qt.openUrlExternally(url)
    }
    Timer { id: armTimer; interval: 6000; onTriggered: { root.armedLink = ""; if (root.hoveredLink) root.linkHover(root.linkInfo(root.hoveredLink)) } }
    function copyText(s) { Jobs.run(["wl-copy", "--", s], () => {}) }
    // right-click on a link (x, y in the view's coordinates)
    function linkMenuAt(view, x, y) {
        const l = view.linkAt(x, y)
        if (!l) return
        const d = MailUtil.parseDateLink(l)
        if (d) {
            linkMenu.show(view, x, y, dateLabel(d), [
                { icon: "󰐕", label: "Add to calendar", run: () => root.addDate(d) },
                { icon: "󰃭", label: "Show the day", run: () => Panels.call("calendar", "openDate", Qt.formatDate(new Date(d.start), "yyyy-MM-dd")) }
            ])
            return
        }
        const i = linkInfo(l)
        const mail = i.scheme === "mailto"
        const address = mail ? decodeURIComponent(l.slice(7).split("?")[0]) : ""
        linkMenu.show(view, x, y, mail ? address : (i.host || "Link"), [
            { icon: i.warn ? "󰀦" : mail ? I.mail : "󰏌", label: i.warn ? "Open anyway" : mail ? "Write to it" : "Open link", danger: i.warn !== "",
              run: () => { root.armedLink = l; root.openLink(l) } },
            { icon: "󰆏", label: mail ? "Copy address" : "Copy link", run: () => root.copyText(mail ? address : l) }
        ])
    }
    MailMenu { id: linkMenu; parent: root }

    // ── dates in the text (links, see linkDates) → calendar events ──
    // the event: the subject, the time, who sent it, and the line of the text the date is in
    function addDate(d) {
        const text = String(body?.text ?? "")
        const at = (MailUtil.findDates(text, Date.now(), 0, true).find(x => x.start === d.start) ?? { at: -1 }).at
        const line = at < 0 ? "" : text.slice(text.lastIndexOf("\n", at) + 1, (text.indexOf("\n", at) + 1 || text.length + 1) - 1).trim()
        Panels.call("calendar", "newEventWith", {
            title: msg.subject || "", start: d.start, end: d.end, allDay: d.allDay,
            description: "From the mail \"" + (msg.subject || "") + "\" by " + MailUtil.formatAddress(msg.from)
                         + ", " + MailUtil.longDate(msg.date) + (line ? "\n\n" + line : "")
        })
    }
    // a date link: bold in the accent color, not underlined (unlike a real link);
    // on the light paper (dark mode off) a blue that reads on white
    function dateStyle(onPaper) { return "color:" + (onPaper && !dark ? "#2a62c9" : Colors.color6) + "; text-decoration:none; font-weight:bold" }
    // after each date: a small calendar icon (the shell's Nerd Font; the message's own font has none)
    readonly property string dateMark: '<span style="font-family:\'' + Properties.fontFamily + '\'; font-size:small">\u00a0󰃭</span>'
    function dateLabel(d) {
        const s = new Date(d.start)
        return Qt.formatDate(s, "ddd d MMM") + (d.allDay ? "" : "  " + Qt.formatTime(s, "HH:mm") + (d.end ? "–" + Qt.formatTime(new Date(d.end), "HH:mm") : ""))
    }

    // ── "Show headers" ──
    property bool showSource: false
    readonly property var source: body?.source ?? null
    readonly property var sourceFields: {
        const h = body?.headers
        if (!h) return []
        const fmt = l => (l ?? []).map(a => MailUtil.formatAddress(a)).join(", ")
        const dom = a => String(a?.email ?? a ?? "").split("@")[1]?.toLowerCase() ?? ""
        const fromSite = MailUtil.siteOf(dom((h.from ?? [])[0]))
        const out = [{ k: "From", v: fmt(h.from) }]
        if ((h.replyTo ?? []).length) {
            const other = h.replyTo.some(a => MailUtil.siteOf(dom(a)) !== fromSite)
            out.push({ k: "Reply-To", v: fmt(h.replyTo) + (other ? "   — replies go to another domain" : ""), warn: other })
        }
        if ((source?.sender ?? []).length) out.push({ k: "Sender", v: fmt(source.sender) })
        if (source?.returnPath) out.push({ k: "Return-Path", v: source.returnPath })
        out.push({ k: "To", v: fmt(h.to) || "—" })
        if ((h.cc ?? []).length) out.push({ k: "Cc", v: fmt(h.cc) })
        out.push({ k: "Date", v: h.date || "—" })
        if (h.messageId) out.push({ k: "Message-ID", v: h.messageId })
        return out
    }

    readonly property var atts: body?.attachments ?? []
    readonly property var invites: atts.filter(a => a.type === "text/calendar" || a.type === "application/ics" || /\.ics$/i.test(a.name))
    readonly property var images: atts.filter(a => /^image\/(png|jpeg|gif|webp|bmp)$/.test(a.type))
    readonly property bool dark: MailStore.style === "dark"
    // dark mode with a light theme: the message gets its own dark paper (on a dark theme it sits on the app's background)
    readonly property bool darkPaper: dark && Colors.light

    readonly property var acc: MailStore.accountMap[msg.account]

    onExpandedChanged: if (expanded && !body) load()
    Component.onCompleted: if (expanded) load()
    // the request is cancelled when the card goes away (another message opened):
    // its answer must not land in a destroyed card, and a queued one never runs
    property var request: null
    Component.onDestruction: {
        if (request) request.cancel()
        if (hoveredLink) linkHover(null)
    }
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
            Text {
                text: '<a href="x">' + (root.showSource ? "Hide headers" : "Show headers") + '</a>'
                textFormat: Text.StyledText
                linkColor: Colors.fade(0.55)
                font.pixelSize: 10
                font.family: Properties.fontFamily
                onLinkActivated: root.showSource = !root.showSource
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
        }

        // ── headers: sender / recipients, the servers' checks, the parts, the raw header ──
        Rectangle {
            Layout.fillWidth: true
            visible: root.expanded && root.showSource && root.body !== null
            implicitHeight: srcCol.implicitHeight + 22
            radius: 9
            color: Colors.fade(0.035)
            border.width: 1
            border.color: Colors.fade(0.06)
            ColumnLayout {
                id: srcCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 11 }
                spacing: 10
                Repeater {
                    model: root.sourceFields
                    RowLayout {
                        id: field
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 12
                        Text {
                            Layout.preferredWidth: 84
                            Layout.alignment: Qt.AlignTop
                            text: field.modelData.k
                            color: Colors.fade(0.45)
                            font.pixelSize: 11
                            font.family: Properties.fontFamily
                        }
                        TextEdit {
                            Layout.fillWidth: true
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.Wrap
                            text: field.modelData.v
                            color: field.modelData.warn ? Colors.orange : Colors.fade(0.88)
                            selectionColor: Colors.fade(0.28)
                            font.pixelSize: 11
                            font.family: Properties.fontFamily
                        }
                    }
                }
                SrcTitle { text: "CHECKS BY THE RECEIVING SERVER" }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: ["spf", "dkim", "dmarc"]
                        Rectangle {
                            id: chip
                            required property string modelData
                            readonly property string r: root.source?.auth?.[modelData] ?? ""
                            readonly property color tint: r === "pass" ? Colors.green : /fail|permerror/.test(r) ? Colors.red : Colors.fade(0.5)
                            implicitWidth: chipText.implicitWidth + 18
                            implicitHeight: 22
                            radius: 11
                            color: Qt.rgba(tint.r, tint.g, tint.b, 0.14)
                            border.width: 1
                            border.color: Qt.rgba(tint.r, tint.g, tint.b, 0.5)
                            Text {
                                id: chipText
                                anchors.centerIn: parent
                                text: chip.modelData.toUpperCase() + "  " + (chip.r || "not checked")
                                color: chip.tint
                                font.pixelSize: 10
                                font.bold: true
                                font.family: Properties.fontFamily
                            }
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: "SPF: the sending server may send for the domain · DKIM: the message is signed by it and unchanged · DMARC: the domain's own rule for both. A fail on a known sender: be careful."
                    color: Colors.fade(0.4)
                    font.pixelSize: 10
                    font.family: Properties.fontFamily
                    wrapMode: Text.Wrap
                }
                SrcTitle { text: "STRUCTURE" }
                Column {
                    Layout.fillWidth: true
                    spacing: 2
                    Repeater {
                        model: root.source?.parts ?? []
                        Text {
                            required property var modelData
                            width: parent.width
                            leftPadding: modelData.depth * 16
                            text: (modelData.type.startsWith("multipart/") ? "󰉋 " : modelData.type.startsWith("image/") ? "󰋩 "
                                   : modelData.type.startsWith("text/") ? "󰈙 " : "󰏢 ") + modelData.type
                                  + (modelData.name ? "  ·  " + modelData.name : "")
                                  + (modelData.size ? "  ·  " + Format.bytes(modelData.size) : "")
                                  + (modelData.charset ? "  ·  " + modelData.charset : "")
                            color: Colors.fade(modelData.type.startsWith("multipart/") ? 0.55 : 0.8)
                            font.pixelSize: 11
                            font.family: Properties.fontFamily
                            elide: Text.ElideRight
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    SrcTitle { Layout.fillWidth: true; text: "RAW HEADER" }
                    ActionButton { icon: "󰆏"; text: "Copy"; onClicked: root.copyText(root.source?.header ?? "") }
                }
                TextEdit {
                    Layout.fillWidth: true
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    text: root.showSource ? (root.source?.header ?? "") : ""
                    color: Colors.fade(0.75)
                    selectionColor: Colors.fade(0.28)
                    font.pixelSize: 10
                    font.family: Properties.fontFamily
                }
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
            readonly property real room: width - (root.dark && !root.darkPaper ? 0 : 28)
            readonly property real design: root.body?.htmlWidth ?? 0
            readonly property bool layout: design >= 360
            readonly property real fit: layout && design > room && room > 0 && room / design >= 0.85 ? room / design : 1
            // compact: the room in steps of 40 px, so resizing doesn't lay it out on every pixel
            readonly property int reflowAt: layout && design * 0.85 > room || !layout ? Math.max(200, Math.floor(room / 40) * 40) : 0
            readonly property real textWidth: !layout ? room : fit < 1 ? design : Math.min(design, room)
            implicitHeight: htmlView.implicitHeight * fit + (root.dark && !root.darkPaper ? 4 : 28)
            radius: 10
            color: root.darkPaper ? "#1c1c21" : root.dark ? "transparent" : "#fbfaf8"
            clip: true
            TextEdit {
                id: htmlView
                x: Math.max(root.dark && !root.darkPaper ? 0 : 14, (paper.width - width * paper.fit) / 2)
                y: root.dark && !root.darkPaper ? 2 : 14
                width: paper.textWidth
                scale: paper.fit
                transformOrigin: Item.TopLeft
                readOnly: true
                selectByMouse: true
                textFormat: TextEdit.RichText
                wrapMode: TextEdit.Wrap
                // dark mode: links without their own color in the theme's accent (Qt's default blue is hard to read on dark)
                text: paper.visible && root.body ? (root.dark ? "<style>a { color: " + Colors.color6 + "; }</style>" : "")
                      + MailUtil.linkDates(paper.reflowAt === 0 ? root.body.html
                         : paper.layout ? root.stackCells(root.fitWidths(root.body.html, paper.reflowAt))
                         : root.fitWidths(root.body.html, paper.reflowAt), Date.now(), root.dateStyle(true), root.dateMark) : ""
                color: root.darkPaper ? "#e2e2e6" : root.dark ? Colors.fade(0.88) : "#1d1d1f"
                selectionColor: root.darkPaper ? "#4a5568" : root.dark ? Colors.fade(0.28) : "#a8c7fa"
                selectedTextColor: root.darkPaper ? "#ffffff" : root.dark ? Colors.ink : "#1d1d1f"
                font.pixelSize: 13
                onLinkActivated: link => root.openLink(link)
                LinkHover { view: htmlView; onLinkChanged: root.hoverLinkAt(link) }
                TapHandler { acceptedButtons: Qt.RightButton; onTapped: (p, b) => root.linkMenuAt(htmlView, p.position.x, p.position.y) }
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
            text: visible ? MailUtil.linkDates(root.textHtml(root.body.text), Date.now(), root.dateStyle(false), root.dateMark) : ""
            color: Colors.fade(0.88)
            selectionColor: Colors.fade(0.28)
            font.pixelSize: 13
            font.family: Properties.fontFamily
            onLinkActivated: link => root.openLink(link)
            LinkHover { view: textView; onLinkChanged: root.hoverLinkAt(link) }
            TapHandler { acceptedButtons: Qt.RightButton; onTapped: (p, b) => root.linkMenuAt(textView, p.position.x, p.position.y) }
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
            Text {
                id: emlNote
                Layout.maximumWidth: 260
                color: Colors.color6
                font.pixelSize: 10
                font.family: Properties.fontFamily
                elide: Text.ElideMiddle
            }
            // the whole message as a file (opens in any mail app, also in this one)
            ActionButton {
                visible: !root.msg.file
                icon: I.download
                text: "Save .eml"
                onClicked: MailStore.saveEml(root.msg, res => emlNote.text = res.ok ? "Saved: " + res.path.split("/").pop() : res.error)
            }
        }
    }
}
