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

        // HTML on paper. A layout made for a fixed width (newsletters: 600 px) that's
        // wider than the room here is laid out at that width and scaled down to fit,
        // like phone mail apps do, instead of being cut off on the right.
        Rectangle {
            id: paper
            Layout.fillWidth: true
            visible: root.expanded && root.body !== null && !root.asText && (root.body.html ?? "") !== ""
            readonly property real room: width - (root.dark ? 0 : 28)
            readonly property real design: root.body?.htmlWidth ?? 0
            readonly property real fit: design > room && room > 0 ? Math.max(0.4, room / design) : 1
            implicitHeight: htmlView.implicitHeight * fit + (root.dark ? 4 : 28)
            radius: 10
            color: root.dark ? "transparent" : "#fbfaf8"
            clip: true
            TextEdit {
                id: htmlView
                x: root.dark ? 0 : 14; y: root.dark ? 2 : 14
                width: paper.fit < 1 ? paper.room / paper.fit : paper.room
                scale: paper.fit
                transformOrigin: Item.TopLeft
                readOnly: true
                selectByMouse: true
                textFormat: TextEdit.RichText
                wrapMode: TextEdit.Wrap
                // dark style: links in the theme's accent (Qt's default blue is hard to read on dark)
                text: paper.visible && root.body ? (root.dark ? "<style>a { color: " + Colors.color6 + "; }</style>" : "") + root.body.html : ""
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
