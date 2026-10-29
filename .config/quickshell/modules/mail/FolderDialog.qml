import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "../settings"
import "../calendar"
import "MailIcons.js" as I

// A new folder on the server: which account, inside which folder, its name.
//   FolderDialog { onCreated: view => … }   start(accountId, parentPath)
Modal {
    id: root

    cardWidth: 440

    property string account: ""
    property string inside: ""                 // the folder it goes in; "" = top level
    property string error: ""
    property bool busy: false
    signal created(string view)                // "<account>|<path>"

    readonly property var folders: (MailStore.accountMap[account]?.folders ?? [])

    function start(acc, parentPath) {
        account = acc || (MailStore.activeAccounts[0]?.id ?? "")
        inside = parentPath ?? ""
        error = ""
        busy = false
        nameField.text = ""
        open()
        nameField.forceActiveFocus()
    }
    function save() {
        const name = nameField.text.trim()
        if (!name || busy) return
        busy = true
        error = ""
        MailStore.createFolder(account, name, inside, res => {
            busy = false
            if (!res.ok) { error = res.error || "Couldn't create the folder"; return }
            const v = account + "|" + res.path
            close()
            created(v)
        })
    }

    ColumnLayout {
        width: parent.width
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text { text: I.folder; color: Colors.color6; font.pixelSize: 20; font.family: Properties.fontFamily }
            Text {
                Layout.fillWidth: true
                text: "New folder"
                color: Colors.ink
                font.pixelSize: 16
                font.bold: true
                font.family: Properties.fontFamily
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 12
            rowSpacing: 8

            Text {
                visible: MailStore.activeAccounts.length > 1
                text: "Account"; color: Colors.fade(0.6); font.pixelSize: 12; font.family: Properties.fontFamily
            }
            DropdownControl {
                visible: MailStore.activeAccounts.length > 1
                Layout.fillWidth: true
                listWidth: 320
                options: MailStore.activeAccounts.map(a => ({ label: a.name || a.email, value: a.id, hint: a.email, color: a.color }))
                value: root.account
                onEdited: v => { root.account = v; root.inside = "" }
            }

            Text { text: "Inside"; color: Colors.fade(0.6); font.pixelSize: 12; font.family: Properties.fontFamily }
            DropdownControl {
                Layout.fillWidth: true
                listWidth: 320
                options: [{ label: "Top level", value: "" }].concat(root.folders.map(f => ({
                    label: (f.role === "inbox" ? "Inbox" : f.path), value: f.path })))
                value: root.inside
                onEdited: v => root.inside = v
            }

            Text { text: "Name"; color: Colors.fade(0.6); font.pixelSize: 12; font.family: Properties.fontFamily }
            SearchField {
                id: nameField
                Layout.fillWidth: true
                icon: ""; clearable: false
                placeholderText: "e.g. Bills"
                onAccepted: root.save()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: root.error || (root.busy ? "Creating it on the server…" : "")
                color: root.error ? Colors.red : Colors.fade(0.45)
                font.pixelSize: 11
                font.family: Properties.fontFamily
                wrapMode: Text.Wrap
            }
            ActionButton { text: "Cancel"; onClicked: root.close() }
            ActionButton {
                icon: "󰄬"
                text: root.busy ? "Creating…" : "Create"
                primary: true
                interactive: !root.busy && nameField.text.trim() !== "" && root.account !== ""
                onClicked: root.save()
            }
        }
    }
}
