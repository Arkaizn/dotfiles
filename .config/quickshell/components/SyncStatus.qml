import QtQuick
import QtQuick.Layouts
import qs.services

// The foot of an app sidebar that syncs (mail, calendar): one dim status
// line ("Checked 10:42", red when something failed, hover for details), the
// app's settings button and "sync now" (turns while syncing).
//
//   SyncStatus {
//       text: syncing ? "Checking…" : "Checked 10:42"; error: errs > 0; details: errorText
//       busy: syncing; canSync: accounts > 0; syncTip: "Check now  (F5)"
//       onSettings: settingsDialog.open(); onSync: Store.check(true)
//   }
RowLayout {
    id: root
    property string text: ""
    property bool error: false
    property string details: ""         // tooltip on the status line (error messages)
    property bool busy: false
    property bool canSync: true
    property string settingsTip: "Settings"
    property string syncTip: "Sync now"
    property string settingsIcon: "󰒓"
    property string syncIcon: "󰑐"
    default property alias extra: extraRow.data   // more buttons before settings (e.g. add account)
    signal settings()
    signal sync()

    Layout.fillWidth: true
    spacing: Tokens.space.s4

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.space.s4
        text: root.text
        color: root.error && !root.busy ? Colors.danger : Colors.textMuted
        font.pixelSize: Tokens.font.micro
        font.family: Properties.fontFamily
        elide: Text.ElideRight
        Accessible.role: Accessible.StatusBar
        Accessible.name: root.text
        HoverHandler { id: statusHover }
        HoverTip { shown: statusHover.hovered && root.details !== ""; text: root.details }
    }
    RowLayout { id: extraRow; spacing: Tokens.space.s4 }
    IconButton {
        implicitWidth: 26; implicitHeight: 26; iconSize: Tokens.icon.sm
        icon: root.settingsIcon
        tooltip: root.settingsTip
        onClicked: root.settings()
    }
    IconButton {
        implicitWidth: 26; implicitHeight: 26; iconSize: Tokens.icon.sm
        icon: root.syncIcon
        tooltip: root.syncTip
        interactive: root.canSync
        busy: root.busy
        onClicked: root.sync()
    }
}
