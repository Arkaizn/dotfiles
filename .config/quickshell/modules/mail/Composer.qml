import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import "../settings"
import "../calendar"
import "MailIcons.js" as I

// Writing a message: new, reply (all), forward, or a saved draft.
// Saved as a draft (on this computer) while you type; closing keeps the draft,
// "Discard" throws it away. Ctrl+Enter sends.
// The text is formatted (bold, lists, links, pasted pictures, …: the bar above
// it, Ctrl+B / I / U / K) and goes out as HTML with a plain-text copy.
//   compose(to)  reply(m, all)  forward(m)  openDraft(d)
Modal {
    id: root

    cardWidth: 760

    property string draftId: ""
    property string account: ""
    property string fTo: ""
    property string fCc: ""
    property string fBcc: ""
    property bool showCc: false
    property string fSubject: ""
    property string fText: ""               // the text as plain text (drafts, checks, the text part)
    property string fHtml: ""               // … and formatted (the HTML part)
    property var attachments: []            // paths
    property string inReplyTo: ""
    property var references: []
    property var replyTo: null              // { id, folder, uid, flag }
    property bool sending: false
    property string error: ""
    property string note: ""                // "Loading the quoted message…" etc.

    readonly property var acc: MailStore.accountMap[account] ?? null
    readonly property bool empty: fTo.trim() === "" && fCc.trim() === "" && fBcc.trim() === "" && fSubject.trim() === ""
                                  && fText.replace(signatureText(acc), "").trim() === "" && attachments.length === 0

    function defaultAccount() {
        const a = MailStore.activeAccounts
        return a.length ? a[0].id : ""
    }
    function signatureText(a) { return a && (a.signature ?? "").trim() ? "\n\n-- \n" + a.signature.trim() : "" }
    // another sender: its signature replaces the old one — or goes where one
    // would be (above the quoted / forwarded part) when the old account had none
    function switchAccount(v) {
        const old = signatureText(acc)
        account = v
        const sig = signatureText(acc)
        // positions in the plain text are positions in the editor (one per character / line break)
        const plain = plainText()
        const oldCore = old.replace(/^\n+/, ""), sigCore = sig.replace(/^\n+/, "")
        const i = oldCore ? plain.indexOf(oldCore) : -1
        if (i >= 0) {
            body.remove(i, i + oldCore.length)
            if (sigCore) body.insert(i, MailUtil.textToHtml(sigCore))
            return
        }
        if (!sig) return
        const at = plain.search(/\n\n(On .*wrote:\n|-------- Forwarded message --------\n)/)
        const end = plain.replace(/\s+$/, "").length
        body.insert(at >= 0 ? at : end, "<br><br>" + MailUtil.textToHtml(sigCore))
    }

    // ── the editor's content ──
    property bool settingBody: false
    function plainText() { return body.getText(0, body.length).replace(/[\u2028\u2029]/g, "\n") }
    // (a picture in the text is one "\uFFFC" there: "[image]" in the plain-text copy)
    function readBody() { fText = plainText().replace(/\uFFFC/g, "[image]"); fHtml = body.getFormattedText(0, body.length) }
    function setBodyHtml(h) { settingBody = true; body.text = h; settingBody = false; readBody() }
    function setBodyText(t) { setBodyHtml(MailUtil.textToHtml(t)) }
    function appendText(t) { body.insert(body.length, "<br><br>" + MailUtil.textToHtml(t)); readBody() }

    function reset() {
        draftId = "d" + Date.now().toString(36)
        account = defaultAccount()
        fTo = ""; fCc = ""; fBcc = ""; showCc = false; fSubject = ""; setBodyText("")
        attachments = []; inReplyTo = ""; references = []; replyTo = null
        error = ""; note = ""; sending = false
    }
    function show(focusBody) {
        open()
        Qt.callLater(() => focusBody ? body.forceActiveFocus() : toField.forceActiveFocus())
        if (focusBody) Qt.callLater(() => body.cursorPosition = 0)
    }

    function compose(to) {
        reset()
        fTo = to ? to + ", " : ""
        setBodyText(signatureText(acc))
        show(!!to)
    }

    function accountFor(m) {
        return MailStore.accountMap[m.account]?.enabled !== false ? m.account : defaultAccount()
    }

    function reply(m, all) {
        reset()
        account = accountFor(m)
        const r = MailUtil.replyRecipients(m, MailStore.accounts.map(a => a.email), all)
        fTo = r.to.map(MailUtil.formatAddress).join(", ")
        fCc = r.cc.map(MailUtil.formatAddress).join(", ")
        showCc = fCc !== ""
        fSubject = MailUtil.replySubject(m.subject)
        inReplyTo = m.messageId || ""
        references = (m.refs ?? []).concat(m.messageId ? [m.messageId] : [])
        replyTo = { id: m.id, folder: m.folder, uid: m.uid, flag: "answered" }
        setBodyText(signatureText(acc))
        note = "Loading the message to quote…"
        show(true)
        const id = draftId
        MailStore.loadBody(m, false, res => {
            if (draftId !== id) return
            note = res.ok ? "" : "Couldn't load the message to quote: " + res.error
            if (res.ok) appendText(MailUtil.quote(res.text, m.from, m.date))
        })
    }

    function forward(m) {
        reset()
        account = accountFor(m)
        fSubject = MailUtil.forwardSubject(m.subject)
        replyTo = { id: m.id, folder: m.folder, uid: m.uid, flag: "forwarded" }
        setBodyText(signatureText(acc))
        note = "Loading the message…"
        show(false)
        const id = draftId
        MailStore.loadBody(m, false, res => {
            if (draftId !== id) return
            if (!res.ok) { note = "Couldn't load the message: " + res.error; return }
            appendText(MailUtil.forwardText(m, res.text))
            if (res.attachments.length === 0) { note = ""; return }
            note = "Loading the attachments…"
            MailStore.fetchAttachments(m, res.attachments, (paths, errs) => {
                if (draftId !== id) return
                attachments = attachments.concat(paths)
                note = errs.length ? "Not all attachments could be added: " + errs.join("; ") : ""
            })
        })
    }

    function openDraft(d) {
        reset()
        draftId = d.id
        account = MailStore.accountMap[d.account] ? d.account : defaultAccount()
        fTo = d.toText ?? ""; fCc = d.ccText ?? ""; fBcc = d.bccText ?? ""; showCc = !!(fCc || fBcc)
        fSubject = d.subject ?? ""; attachments = d.attachments ?? []
        if (d.html) setBodyHtml(d.html); else setBodyText(d.text ?? "")
        inReplyTo = d.inReplyTo ?? ""; references = d.references ?? []; replyTo = d.replyTo ?? null
        show(true)
    }

    function draft() {
        return {
            id: draftId, account: account, saved: Date.now(),
            toText: fTo, ccText: fCc, bccText: fBcc,
            to: MailUtil.parseAddresses(fTo).list, cc: MailUtil.parseAddresses(fCc).list, bcc: MailUtil.parseAddresses(fBcc).list,
            subject: fSubject, text: fText, html: fHtml, attachments: attachments,
            inReplyTo: inReplyTo, references: references, replyTo: replyTo
        }
    }

    // saved a moment after the last change; closing saves at once (or drops an empty one)
    Timer { id: saveTimer; interval: 1500; onTriggered: root.saveDraft() }
    function changed() { if (shown && !sending) saveTimer.restart() }
    onFToChanged: changed()
    onFCcChanged: changed()
    onFBccChanged: changed()
    onFSubjectChanged: { changed(); subjectArm.armed = false }
    onAttachmentsChanged: { changed(); subjectArm.attachOk = false }
    onFTextChanged: changed()
    function saveDraft() {
        saveTimer.stop()
        if (empty) MailStore.dropDraft(draftId)
        else MailStore.putDraft(draft())
    }
    onClosed: if (!sending) saveDraft()

    // the form is emptied first, so closing doesn't save it again as a draft
    function discard() {
        saveTimer.stop()
        MailStore.dropDraft(draftId)
        reset()
        close()
    }

    function send() {
        if (sending) return
        const bad = [].concat(MailUtil.parseAddresses(fTo).bad, MailUtil.parseAddresses(fCc).bad, MailUtil.parseAddresses(fBcc).bad)
        if (bad.length) { error = "Not an address: " + bad.join(", "); return }
        const d = draft()
        if (d.to.length + d.cc.length + d.bcc.length === 0) { error = "Add a recipient"; return }
        if (!acc) { error = "Add an account first"; return }
        if (d.subject.trim() === "" && !subjectArm.armed) { subjectArm.armed = true; error = "No subject — press Send again to send anyway"; return }
        // like Thunderbird: "anbei" / "attached" written, nothing attached
        if (MailStore.attachmentReminder && attachments.length === 0 && MailUtil.mentionsAttachment(fText) && !subjectArm.attachOk) {
            subjectArm.attachOk = true
            error = "You mention an attachment, but nothing is attached — Attach, or Send again to send without"
            return
        }
        saveTimer.stop()
        MailStore.putDraft(d)              // kept if sending fails or the shell quits meanwhile
        sending = true
        error = ""
        MailStore.send(d, res => {
            sending = false
            if (!res.ok) { error = res.error; return }
            if (res.warning) MailStore.lastError = res.warning
            reset()
            close()
        })
    }
    QtObject { id: subjectArm; property bool armed: false; property bool attachOk: false }

    function pickFiles() {
        Jobs.run(["zenity", "--file-selection", "--multiple", "--separator=\n", "--title=Attach files"], (code, out) => {
            if (code === 0) attachments = attachments.concat(out.split("\n").filter(p => p && !attachments.includes(p)))
        })
    }

    ColumnLayout {
        id: form
        width: parent.width
        height: Math.min(720, root.height - 100)
        spacing: 8

        Keys.onPressed: event => {
            if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                root.send()
                event.accepted = true
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                text: root.replyTo?.flag === "forwarded" ? I.forward : root.replyTo ? I.reply : I.draft
                color: Colors.color6
                font.pixelSize: 20
                font.family: Properties.fontFamily
            }
            Text {
                Layout.fillWidth: true
                text: root.fSubject.trim() || (root.replyTo ? "Reply" : "New message")
                color: Colors.ink
                font.pixelSize: 17
                font.bold: true
                font.family: Properties.fontFamily
                elide: Text.ElideRight
            }
            DropdownControl {
                visible: MailStore.activeAccounts.length > 1
                implicitWidth: 240
                listWidth: 360
                options: MailStore.activeAccounts.map(a => ({ label: a.name || a.email, value: a.id, hint: a.email }))
                value: root.account
                onEdited: v => root.switchAccount(v)
            }
            IconButton { implicitWidth: 30; implicitHeight: 30; icon: I.close; tooltip: "Close (kept as a draft)"; onClicked: root.close() }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            AddressField {
                id: toField
                Layout.fillWidth: true
                label: "To"
                text: root.fTo
                onTextChanged: if (text !== root.fTo) root.fTo = text
                error: root.error.startsWith("Not an address") || root.error === "Add a recipient"
                KeyNavigation.tab: root.showCc ? ccField : subject
            }
            ActionButton {
                visible: !root.showCc
                text: "Cc  Bcc"
                onClicked: { root.showCc = true; Qt.callLater(() => ccField.forceActiveFocus()) }
            }
        }
        AddressField {
            id: ccField
            Layout.fillWidth: true
            visible: root.showCc
            label: "Cc"
            text: root.fCc
            onTextChanged: if (text !== root.fCc) root.fCc = text
        }
        AddressField {
            Layout.fillWidth: true
            visible: root.showCc
            label: "Bcc"
            text: root.fBcc
            onTextChanged: if (text !== root.fBcc) root.fBcc = text
        }
        SearchField {
            id: subject
            Layout.fillWidth: true
            icon: ""; clearable: false
            placeholderText: "Subject"
            text: root.fSubject
            onTextEdited: root.fSubject = text
            onAccepted: body.forceActiveFocus()
        }

        FormatBar { id: fmt; Layout.fillWidth: true; editor: body; composeDir: MailStore.composeDir }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 12
            color: Colors.card
            border.width: Properties.panelBorderWidth
            border.color: body.activeFocus ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.45) : Properties.cardBorder
            ScrollView {
                id: bodyScroll
                anchors.fill: parent
                anchors.margins: 2
                ScrollBar.vertical: CalScrollBar {}
                SmoothWheel { flick: bodyScroll.contentItem; step: 120 }
                TextArea {
                    id: body
                    textFormat: TextEdit.RichText
                    onTextChanged: if (!root.settingBody) root.readBody()
                    placeholderText: "Write your message"
                    wrapMode: TextEdit.Wrap
                    color: Properties.color
                    placeholderTextColor: Colors.fade(0.35)
                    selectionColor: Colors.fade(0.28)
                    selectByMouse: true
                    persistentSelection: true            // stays while a toolbar button is clicked
                    font.pixelSize: 14
                    font.family: "Noto Sans"              // the message's font (mailsync adds fallbacks for other apps)
                    leftPadding: 14; rightPadding: 14; topPadding: 12; bottomPadding: 12
                    background: null
                    onCursorPositionChanged: fmt.refresh()
                    onSelectedTextChanged: fmt.refresh()
                    Keys.onPressed: event => {
                        const ctrl = event.modifiers & Qt.ControlModifier
                        if (ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) root.send()
                        else if (ctrl && event.key === Qt.Key_B) fmt.toggle("bold")
                        else if (ctrl && event.key === Qt.Key_I) fmt.toggle("italic")
                        else if (ctrl && event.key === Qt.Key_U) fmt.toggle("underline")
                        else if (ctrl && event.key === Qt.Key_K) fmt.askLink()
                        else if (ctrl && event.key === Qt.Key_V && !(event.modifiers & Qt.ShiftModifier)) fmt.paste()
                        else return
                        event.accepted = true
                    }
                    // Ctrl + click opens a link (a plain click just places the cursor, like in other editors)
                    TapHandler {
                        acceptedModifiers: Qt.ControlModifier
                        onTapped: (p, button) => {
                            const l = body.linkAt(p.position.x, p.position.y)
                            if (l) Qt.openUrlExternally(l)
                        }
                    }
                    HoverHandler { cursorShape: body.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
                }
            }
            DropArea {
                id: drop
                anchors.fill: parent
                keys: ["text/uri-list"]
                onEntered: drag => drag.accepted = drag.hasUrls
                onDropped: d => {
                    const p = d.urls.map(u => decodeURIComponent(String(u).replace(/^file:\/\//, ""))).filter(x => x.startsWith("/"))
                    root.attachments = root.attachments.concat(p.filter(x => !root.attachments.includes(x)))
                    d.accept()
                }
            }
            DropZone {
                anchors.fill: parent
                anchors.margins: 6
                radius: 10
                shown: drop.containsDrag
                hot: true
                Text {
                    anchors.centerIn: parent
                    text: I.clip + "  Drop to attach"
                    color: Colors.ink
                    font.pixelSize: 14
                    font.family: Properties.fontFamily
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            visible: root.attachments.length > 0
            spacing: 6
            Repeater {
                model: root.attachments
                Rectangle {
                    required property var modelData
                    required property int index
                    implicitWidth: aRow.implicitWidth + 12
                    implicitHeight: 28
                    radius: 8
                    color: Colors.fade(0.05)
                    RowLayout {
                        id: aRow
                        anchors.verticalCenter: parent.verticalCenter
                        x: 8
                        spacing: 4
                        Text { text: I.clip; color: Colors.fade(0.5); font.pixelSize: 11; font.family: Properties.fontFamily }
                        Text { Layout.maximumWidth: 220; text: modelData.split("/").pop(); color: Colors.fade(0.85)
                               font.pixelSize: 11; font.family: Properties.fontFamily; elide: Text.ElideMiddle }
                        IconButton { implicitWidth: 20; implicitHeight: 20; iconSize: 10; icon: I.close; tooltip: "Remove"
                                     onClicked: root.attachments = root.attachments.filter((_, i) => i !== index) }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            ActionButton { icon: I.clip; text: "Attach"; onClicked: root.pickFiles() }
            Text {
                Layout.fillWidth: true
                text: root.error || root.note || (root.acc ? "From " + MailUtil.formatAddress({ name: root.acc.displayName, email: root.acc.email }) : "No account to send from")
                color: root.error ? Colors.red : Colors.fade(0.45)
                font.pixelSize: 11
                font.family: Properties.fontFamily
                elide: Text.ElideRight
                wrapMode: root.error ? Text.Wrap : Text.NoWrap
                maximumLineCount: 2
            }
            ActionButton { icon: I.trash; text: "Discard"; onClicked: root.discard() }
            ActionButton {
                icon: I.send
                text: root.sending ? "Sending…" : "Send"
                primary: true
                interactive: !root.sending
                onClicked: root.send()
            }
        }
    }
}
