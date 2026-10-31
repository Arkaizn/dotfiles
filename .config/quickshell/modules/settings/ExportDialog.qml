import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "../calendar"

// What goes into a settings export: the settings groups (all by default), the
// ones bound to this device (monitors: off by default), and — if asked — the
// mail and calendar accounts (with their passwords only encrypted by a
// passphrase). Export… hands the choice to SettingsTransfer.exportWith().
//   ExportDialog { settingsTransfer: someSettingsTransfer }   start()
Modal {
    id: root

    required property var settingsTransfer
    cardWidth: 640

    // device-bound: off unless picked (the monitor layout; with it off, the
    // "which monitor" keys of the bar, lockscreen, widgets … stay out too)
    readonly property var deviceGroups: ["monitors"]
    readonly property var settingGroups: Settings.groups.filter(g => !deviceGroups.includes(g))
    property var picked: ({})
    property bool monitors: false
    property bool mail: false
    property bool calendar: false
    property bool withPasswords: true
    property string pass1: ""
    property string pass2: ""
    property string error: ""

    readonly property bool accounts: (mail && MailStore.accounts.length > 0) || (calendar && CalendarStore.accounts.length > 0)
    readonly property int pickedCount: settingGroups.filter(g => picked[g]).length

    function start() {
        const p = {}
        for (const g of settingGroups) p[g] = true
        picked = p
        monitors = false; mail = false; calendar = false; withPasswords = true
        pass1 = ""; pass2 = ""; error = ""
        open()
    }
    function setAll(v) { const p = {}; for (const g of settingGroups) p[g] = v; picked = p }
    function toggle(g) { const p = Object.assign({}, picked); p[g] = !p[g]; picked = p }

    function go() {
        if (pickedCount === 0 && !monitors && !accounts) { error = "Pick something to export"; return }
        if (accounts && withPasswords && pass1.length < 8) { error = "The passphrase needs at least 8 characters"; return }
        if (accounts && withPasswords && pass1 !== pass2) { error = "The two passphrases aren't the same"; return }
        const opts = {
            groups: settingGroups.filter(g => picked[g]).concat(monitors ? deviceGroups : []),
            monitors: monitors,
            mail: mail && MailStore.accounts.length > 0,
            calendar: calendar && CalendarStore.accounts.length > 0,
            withPasswords: withPasswords,
            passphrase: pass1
        }
        pass1 = ""; pass2 = ""
        close()
        settingsTransfer.exportWith(opts)
    }

    ColumnLayout {
        width: parent.width
        spacing: Tokens.space.s12

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s10
            Text { text: "󰈝"; color: Colors.color6; font.pixelSize: Tokens.font.titleLarge; font.family: Properties.fontFamily }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text { Layout.fillWidth: true; text: "Export settings"; color: Colors.ink; font.pixelSize: Tokens.font.title; font.bold: true; font.family: Properties.fontFamily }
                Text { Layout.fillWidth: true; text: "Pick what goes into the file"; color: Colors.fade(0.5); font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily }
            }
            IconButton { implicitWidth: 30; implicitHeight: 30; icon: "󰅖"; onClicked: root.close() }
        }

        // ── settings ──
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.space.s4
            Text {
                Layout.fillWidth: true
                text: "SETTINGS  ·  " + root.pickedCount + " of " + root.settingGroups.length
                color: Colors.fade(0.45); font.pixelSize: Tokens.font.micro; font.bold: true; font.letterSpacing: 1.1; font.family: Properties.fontFamily
            }
            ActionButton { text: "All"; onClicked: root.setAll(true) }
            ActionButton { text: "None"; onClicked: root.setAll(false) }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: grid.implicitHeight + 16
            radius: Tokens.radius.card
            color: Colors.card
            border.width: Properties.panelBorderWidth
            border.color: Properties.cardBorder
            GridLayout {
                id: grid
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Tokens.space.s8 }
                columns: 3
                columnSpacing: Tokens.space.s4
                rowSpacing: Tokens.space.s2
                Repeater {
                    model: root.settingGroups.slice().sort((a, b) => Settings.groupLabel(a).localeCompare(Settings.groupLabel(b)))
                    Checkbox {
                        required property string modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        label: Settings.groupLabel(modelData)
                        checked: root.picked[modelData] === true
                        onClicked: root.toggle(modelData)
                    }
                }
            }
        }

        // ── this device ──
        Text {
            Layout.topMargin: Tokens.space.s4
            text: "THIS DEVICE"
            color: Colors.fade(0.45); font.pixelSize: Tokens.font.micro; font.bold: true; font.letterSpacing: 1.1; font.family: Properties.fontFamily
        }
        ListCard {
            PlainRow {
                Layout.fillWidth: true
                label: "Monitors"
                desc: "Resolution, scale, position of each monitor, and which monitor the bar, lockscreen and widgets use. Usually only right on this computer; an import keeps the other device's own."
                ToggleSwitch { checked: root.monitors; onToggled: v => root.monitors = v }
            }
        }

        // ── accounts ──
        Text {
            Layout.topMargin: Tokens.space.s4
            text: "ACCOUNTS"
            color: Colors.fade(0.45); font.pixelSize: Tokens.font.micro; font.bold: true; font.letterSpacing: 1.1; font.family: Properties.fontFamily
        }
        ListCard {
            PlainRow {
                Layout.fillWidth: true
                opacity: MailStore.accounts.length > 0 ? 1 : 0.45
                label: "Mail accounts"
                desc: MailStore.accounts.length === 0 ? "None set up" : MailStore.accounts.map(a => a.email).join(", ")
                ToggleSwitch { checked: root.mail; enabled: MailStore.accounts.length > 0; onToggled: v => root.mail = v }
            }
            Divider {}
            PlainRow {
                Layout.fillWidth: true
                opacity: CalendarStore.accounts.length > 0 ? 1 : 0.45
                label: "Calendar accounts"
                desc: CalendarStore.accounts.length === 0 ? "None set up" : CalendarStore.accounts.map(a => a.name).join(", ")
                ToggleSwitch { checked: root.calendar; enabled: CalendarStore.accounts.length > 0; onToggled: v => root.calendar = v }
            }
            Divider { visible: root.accounts }
            PlainRow {
                Layout.fillWidth: true
                visible: root.accounts
                label: "Include the passwords"
                desc: "Then the accounts are encrypted with a passphrase (GnuPG, AES-256); the import asks for it. Without them you sign in once more on the other device."
                ToggleSwitch { checked: root.withPasswords; onToggled: v => root.withPasswords = v }
            }
        }
        SearchField {
            Layout.fillWidth: true
            visible: root.accounts && root.withPasswords
            icon: "󰌋"
            password: true
            placeholderText: "Passphrase (at least 8 characters)"
            text: root.pass1
            onTextEdited: root.pass1 = text
        }
        SearchField {
            Layout.fillWidth: true
            visible: root.accounts && root.withPasswords
            icon: "󰌋"
            password: true
            placeholderText: "Passphrase again"
            text: root.pass2
            onTextEdited: root.pass2 = text
            error: root.pass2 !== "" && root.pass2 !== root.pass1
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.space.s4
            spacing: Tokens.space.s8
            Text {
                Layout.fillWidth: true
                text: root.error
                color: Colors.red
                font.pixelSize: Tokens.font.caption
                font.family: Properties.fontFamily
                wrapMode: Text.Wrap
            }
            ActionButton { text: "Cancel"; onClicked: root.close() }
            ActionButton { icon: "󰈝"; text: "Export…"; primary: true; onClicked: root.go() }
        }
    }

}
