import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "../settings"

// Moving calendar accounts to another device (like the mail app's): export some
// or all to one file — passwords / Microsoft sign-ins only if asked, then the
// whole file is encrypted with a passphrase (GnuPG, AES-256); a local
// calendar's .ics goes along. Import shows what's in a file and takes the
// accounts you pick (one that's already here is updated).
//   start("export" | "import")
Modal {
    id: root

    cardWidth: 560

    property string mode: "export"
    property var picked: ({})              // export: account id → bool; import: index in the file → bool
    property bool withPasswords: true
    property string pass1: ""
    property string pass2: ""
    property string path: ""
    property var found: []                 // import: accounts in the file (no passwords)
    property bool needPass: false
    property bool encrypted: false
    property bool busy: false
    property string error: ""
    property string done: ""

    function start(m) {
        mode = m
        pass1 = ""; pass2 = ""; path = ""; found = []; needPass = false; encrypted = false
        busy = false; error = ""; done = ""; withPasswords = true
        const p = {}
        if (m === "export") for (const a of CalendarStore.accounts) p[a.id] = true
        picked = p
        open()
        if (m === "import") Qt.callLater(pickFile)
        handedFile = ""
    }

    function kind(a) { return a.type === "ics" ? "Subscription" : a.type === "local" ? "Local" : a.type === "graph" ? "Microsoft 365" : /icloud/i.test(a.url) ? "iCloud" : "CalDAV" }
    // a file handed over (the settings import: written to a private temp folder,
    // removed again when the dialog closes)
    property string handedFile: ""
    function startFile(p) {
        start("import-file")
        mode = "import"
        handedFile = p
        path = p
        readFile()
    }
    onClosed: if (handedFile) { Jobs.run(["rm", "-f", "--", handedFile], () => {}); handedFile = "" }

    function toggle(k) { const p = Object.assign({}, picked); p[k] = !p[k]; picked = p }
    readonly property var chosen: Object.keys(picked).filter(k => picked[k])

    // ── export ──
    function exportNow() {
        if (chosen.length === 0) { error = "Pick at least one account"; return }
        if (withPasswords && pass1.length < 8) { error = "The passphrase needs at least 8 characters"; return }
        if (withPasswords && pass1 !== pass2) { error = "The two passphrases aren't the same"; return }
        error = ""
        const name = withPasswords ? "calendar-accounts.qscal" : "calendar-accounts.json"
        Jobs.run(["zenity", "--file-selection", "--save", "--confirm-overwrite", "--title=Export calendar accounts",
                  "--filename=" + Quickshell.env("HOME") + "/" + name], (code, out) => {
            if (code !== 0 || !out.trim()) return
            busy = true
            CalendarStore.exportAccounts(chosen, withPasswords, pass1, out.trim(), res => {
                busy = false
                pass1 = ""; pass2 = ""
                if (!res.ok) { error = res.error; return }
                done = res.count + (res.count === 1 ? " account" : " accounts") + " saved to " + res.path
                     + (res.encrypted ? " (encrypted)" : " (without passwords)")
            })
        })
    }

    // ── import ──
    function pickFile() {
        Jobs.run(["zenity", "--file-selection", "--title=Import calendar accounts", "--file-filter=Calendar accounts | *.qscal *.json",
                  "--file-filter=All files | *"], (code, out) => {
            if (code !== 0 || !out.trim()) { if (found.length === 0) close(); return }
            path = out.trim()
            readFile()
        })
    }
    function readFile() {
        busy = true
        error = ""
        CalendarStore.importRead(path, pass1, res => {
            busy = false
            if (!res.ok) { error = res.error; return }
            encrypted = res.encrypted
            needPass = res.needPassphrase
            found = res.accounts
            const p = {}
            for (const a of res.accounts) p[a.index] = true
            picked = p
        })
    }
    function importNow() {
        if (chosen.length === 0) { error = "Pick at least one account"; return }
        busy = true
        error = ""
        CalendarStore.importAccounts(path, pass1, found, chosen.map(Number), res => {
            busy = false
            pass1 = ""
            if (!res.ok) { error = res.error; return }
            const without = res.accounts.filter(a => !a.passwordStored && (a.type === "caldav" || a.type === "graph")).map(a => a.name)
            done = res.accounts.length + (res.accounts.length === 1 ? " account" : " accounts") + " imported."
                 + (without.length ? " Sign in again for " + without.join(", ") + " (add the account once more: it goes into the one that's there)." : "")
            found = []
        })
    }

    ColumnLayout {
        width: parent.width
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text { text: root.mode === "export" ? "󰈔" : "󰇚"; color: Colors.color6; font.pixelSize: 20; font.family: Properties.fontFamily }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text { Layout.fillWidth: true; text: root.mode === "export" ? "Export calendar accounts" : "Import calendar accounts"
                       color: Colors.ink; font.pixelSize: 17; font.bold: true; font.family: Properties.fontFamily }
                Text { Layout.fillWidth: true; elide: Text.ElideRight; color: Colors.fade(0.5); font.pixelSize: 11; font.family: Properties.fontFamily
                       text: root.mode === "export" ? "To set them up on another device in one go" : (root.path || "Pick the exported file") }
            }
            IconButton { implicitWidth: 30; implicitHeight: 30; icon: "󰅖"; onClicked: root.close() }
        }

        // the accounts
        Repeater {
            model: root.mode === "export" ? CalendarStore.accounts : root.found
            Rectangle {
                id: row
                required property var modelData
                readonly property string k: root.mode === "export" ? modelData.id : String(modelData.index)
                readonly property bool bad: false
                readonly property bool exists: root.mode === "import" && !!CalendarStore.existingFor(modelData)
                Layout.fillWidth: true
                implicitHeight: 46
                radius: 10
                color: rowMouse.containsMouse && !bad ? Colors.fade(0.06) : Colors.fade(0.03)
                opacity: bad ? 0.6 : 1
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10
                    Text {
                        text: root.picked[row.k] ? "󰄵" : "󰄱"
                        color: root.picked[row.k] ? Colors.color6 : Colors.fade(0.4)
                        font.pixelSize: 16
                        font.family: Properties.fontFamily
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text { Layout.fillWidth: true; text: row.modelData.name; color: Colors.ink; font.pixelSize: 12
                               font.family: Properties.fontFamily; elide: Text.ElideRight }
                        Text {
                            Layout.fillWidth: true
                            text: root.kind(row.modelData) + "  ·  " + row.modelData.calendars.length + (row.modelData.calendars.length === 1 ? " calendar" : " calendars")
                                + (root.mode === "import"
                                    ? (row.modelData.type === "local" ? (row.modelData.hasData ? "  ·  with its events" : "") 
                                       : row.modelData.type === "ics" ? "" : row.modelData.hasPassword ? "  ·  with login" : "  ·  no login")
                                      + (row.exists ? "  ·  already here: updated" : "")
                                    : "")
                            color: row.bad ? Colors.red : Colors.fade(0.45)
                            font.pixelSize: 10
                            font.family: Properties.fontFamily
                            elide: Text.ElideRight
                        }
                    }
                }
                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !row.bad
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggle(row.k)
                }
            }
        }

        // export: passwords + passphrase
        PlainRow {
            Layout.fillWidth: true
            visible: root.mode === "export"
            label: "Include the passwords and sign-ins"
            desc: "Then the whole file is encrypted with a passphrase you choose (GnuPG, AES-256). Without them you sign in once more on the other device."
            ToggleSwitch { checked: root.withPasswords; onToggled: v => root.withPasswords = v }
        }
        SearchField {
            Layout.fillWidth: true
            visible: (root.mode === "export" && root.withPasswords) || (root.mode === "import" && root.needPass)
            icon: "󰌋"
            password: true
            placeholderText: root.mode === "export" ? "Passphrase (at least 8 characters)" : "The file's passphrase"
            text: root.pass1
            onTextEdited: root.pass1 = text
            onAccepted: if (root.mode === "import") root.readFile()
        }
        SearchField {
            Layout.fillWidth: true
            visible: root.mode === "export" && root.withPasswords
            icon: "󰌋"
            password: true
            placeholderText: "Passphrase again"
            text: root.pass2
            onTextEdited: root.pass2 = text
            error: root.pass2 !== "" && root.pass2 !== root.pass1
        }

        Text {
            Layout.fillWidth: true
            visible: text !== ""
            text: root.error || root.done || (root.busy ? (root.mode === "export" ? "Exporting…" : "Reading…") : "")
            color: root.error ? Colors.red : root.done ? Colors.color6 : Colors.fade(0.5)
            font.pixelSize: 11
            font.family: Properties.fontFamily
            wrapMode: Text.Wrap
        }
        Text {
            Layout.fillWidth: true
            visible: root.mode === "export" && root.withPasswords
            text: "󰌾  Keep the file and the passphrase apart (e.g. the file in your cloud, the passphrase in your head or a password manager)."
            color: Colors.fade(0.4)
            font.pixelSize: 10
            font.family: Properties.fontFamily
            wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            ActionButton { visible: root.mode === "import"; icon: "󰉋"; text: "Other file…"; onClicked: root.pickFile() }
            Item { Layout.fillWidth: true }
            ActionButton { text: root.done ? "Close" : "Cancel"; onClicked: root.close() }
            ActionButton {
                visible: root.done === ""
                icon: root.mode === "export" ? "󰈔" : "󰇚"
                primary: true
                interactive: !root.busy && (root.mode === "export" || root.found.length > 0 || root.needPass)
                text: root.mode === "export" ? "Export…" : root.needPass && root.found.length === 0 ? "Unlock" : "Import"
                onClicked: root.mode === "export" ? root.exportNow() : root.needPass && root.found.length === 0 ? root.readFile() : root.importNow()
            }
        }
    }
}
