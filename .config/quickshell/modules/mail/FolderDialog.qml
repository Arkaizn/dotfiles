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

    cardWidth: 460

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

    readonly property var accObj: MailStore.accountMap[account] ?? null
    readonly property var parentFolder: folders.find(f => f.path === inside) ?? null
    readonly property string parentName: !parentFolder ? "" : parentFolder.role === "inbox" ? "Inbox" : parentFolder.name

    ColumnLayout {
        width: parent.width
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Rectangle {
                implicitWidth: 38; implicitHeight: 38; radius: 12
                color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.14)
                Text { anchors.centerIn: parent; text: I.folder; color: Colors.color6; font.pixelSize: 18; font.family: Properties.fontFamily }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text { text: "New folder"; color: Colors.ink; font.pixelSize: 16; font.bold: true; font.family: Properties.fontFamily }
                // where it goes: account › parent
                Text {
                    Layout.fillWidth: true
                    text: MailStore.accountLabel(root.accObj) + (root.parentName ? "  ›  " + root.parentName : "  ›  top level")
                    color: Colors.fade(0.5)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                    elide: Text.ElideMiddle
                }
            }
            IconButton { implicitWidth: 30; implicitHeight: 30; icon: I.close; onClicked: root.close() }
        }

        SearchField {
            id: nameField
            Layout.fillWidth: true
            icon: I.folder
            clearable: false
            placeholderText: "Folder name, e.g. Bills"
            onAccepted: root.save()
        }

        // which account (only with more than one): its colored chip
        ColumnLayout {
            Layout.fillWidth: true
            visible: MailStore.activeAccounts.length > 1
            spacing: 6
            Text { text: "Account"; color: Colors.fade(0.5); font.pixelSize: 11; font.bold: true; font.family: Properties.fontFamily }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: MailStore.activeAccounts
                    Rectangle {
                        required property var modelData
                        readonly property bool on: root.account === modelData.id
                        width: chipRow.implicitWidth + 20
                        height: 30
                        radius: 15
                        color: on ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.16) : chipMouse.containsMouse ? Colors.fade(0.07) : Colors.fade(0.04)
                        border.width: 1
                        border.color: on ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.6) : Colors.fade(0.1)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 7
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: modelData.color || Colors.color6 }
                            Text { text: MailStore.accountLabel(modelData); color: on ? Colors.ink : Colors.fade(0.75); font.pixelSize: 12; font.family: Properties.fontFamily }
                        }
                        MouseArea {
                            id: chipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.account = modelData.id; root.inside = "" }
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            Text { text: "Inside"; color: Colors.fade(0.5); font.pixelSize: 11; font.bold: true; font.family: Properties.fontFamily }
            DropdownControl {
                Layout.fillWidth: true
                listWidth: 360
                options: [{ label: "Top level", value: "" }].concat(root.folders.map(f => ({
                    label: "    ".repeat(Math.min(3, f.depth ?? 0)) + (f.role === "inbox" ? "Inbox" : f.name), value: f.path })))
                value: root.inside
                onEdited: v => root.inside = v
            }
        }

        RowLayout {
            Layout.fillWidth: true
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
