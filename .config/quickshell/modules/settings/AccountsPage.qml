import QtQuick
import QtQuick.Layouts
import qs.services
import "network"

// Accounts page: the mail and calendar accounts together — which there are,
// adding one, export / import (the apps' own dialogs open for it), and each
// account's settings in its app. The settings export (top of the window) can
// take both along.
ColumnLayout {
    id: page
    spacing: 16

    function calKind(a) { return a.type === "ics" ? "Subscription" : a.type === "local" ? "Local" : a.type === "graph" ? "Microsoft 365" : /icloud/i.test(a.url) ? "iCloud" : "CalDAV" }
    readonly property var calErrors: CalendarStore.errors ?? []

    // ── Mail ──
    NetCard {
        Layout.fillWidth: true
        title: "Mail"
        icon: "󰇮"
        header: [
            ActionButton { icon: "󰐕"; text: "Add"; onClicked: Panels.call("mail", "addAccount") },
            ActionButton { icon: "󰈔"; text: "Export…"; interactive: MailStore.accounts.length > 0; onClicked: Panels.call("mail", "transfer", "export") },
            ActionButton { icon: "󰇚"; text: "Import…"; onClicked: Panels.call("mail", "transfer", "import") }
        ]
        NetRow {
            first: true
            visible: MailStore.accounts.length === 0
            label: "No mail accounts yet"
            desc: "Add one, or import a file exported on another device"
        }
        Repeater {
            model: MailStore.accounts
            AccountRow {
                required property var modelData
                required property int index
                first: index === 0
                color: modelData.color || Colors.color6
                title: MailStore.accountLabel(modelData)
                sub: modelData.email + (modelData.enabled === false ? "  ·  off"
                     : MailStore.errors[modelData.id] ? "  ·  󰀦 " + MailStore.errors[modelData.id] : "")
                error: modelData.enabled !== false && !!MailStore.errors[modelData.id]
                dim: modelData.enabled === false
                onOpen: Panels.call("mail", "settings", "acc:" + modelData.id)
            }
        }
    }

    // ── Calendar ──
    NetCard {
        Layout.fillWidth: true
        title: "Calendar"
        icon: "󰃭"
        header: [
            ActionButton { icon: "󰐕"; text: "Add"; onClicked: Panels.call("calendar", "addAccount") },
            ActionButton { icon: "󰈔"; text: "Export…"; interactive: CalendarStore.accounts.length > 0; onClicked: Panels.call("calendar", "transfer", "export") },
            ActionButton { icon: "󰇚"; text: "Import…"; onClicked: Panels.call("calendar", "transfer", "import") }
        ]
        NetRow {
            first: true
            visible: CalendarStore.accounts.length === 0
            label: "No calendar accounts yet"
            desc: "Add one (iCloud, CalDAV, Microsoft 365, a subscription or a local calendar), or import a file"
        }
        Repeater {
            model: CalendarStore.accounts
            AccountRow {
                required property var modelData
                required property int index
                readonly property int failing: page.calErrors.filter(e => String(e.calendar ?? "").startsWith(modelData.id + "|")).length
                first: index === 0
                color: modelData.calendars?.[0]?.color || Colors.color6
                title: modelData.name
                sub: page.calKind(modelData) + "  ·  " + modelData.calendars.length + (modelData.calendars.length === 1 ? " calendar" : " calendars")
                     + (failing ? "  ·  󰀦 " + failing + " couldn't sync" : "")
                error: failing > 0
                onOpen: Panels.call("calendar", "settings", "acc:" + modelData.id)
            }
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 6
        text: "Passwords stay in the keyring. An export takes them only encrypted with a passphrase you choose. The settings export (󰈝 at the top) can include these accounts too."
        color: Colors.fade(0.42)
        font.pixelSize: 11
        font.family: Properties.fontFamily
        wrapMode: Text.Wrap
    }

    component AccountRow: Item {
        id: row
        property bool first: false
        property color color
        property string title
        property string sub
        property bool error: false
        property bool dim: false
        signal open()
        Layout.fillWidth: true
        implicitHeight: 58
        Rectangle {
            visible: !row.first
            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16 }
            height: 1
            color: Colors.fade(0.06)
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 4
            radius: 10
            color: rowMouse.containsMouse ? Colors.fade(0.04) : "transparent"
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 12
            spacing: 12
            Rectangle {
                implicitWidth: 28; implicitHeight: 28; radius: 14
                color: row.color
                opacity: row.dim ? 0.4 : 1
                Text {
                    anchors.centerIn: parent
                    text: row.title.charAt(0).toUpperCase()
                    color: Colors.background
                    font.pixelSize: 12
                    font.bold: true
                    font.family: Properties.fontFamily
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text { Layout.fillWidth: true; text: row.title; color: row.dim ? Colors.fade(0.5) : Colors.ink; font.pixelSize: 13; font.bold: true
                       font.family: Properties.fontFamily; elide: Text.ElideRight }
                Text { Layout.fillWidth: true; text: row.sub; color: row.error ? Colors.red : Colors.fade(0.45); font.pixelSize: 11
                       font.family: Properties.fontFamily; elide: Text.ElideRight }
            }
            ActionButton { icon: "󰒓"; text: "Settings"; onClicked: row.open() }
        }
        MouseArea { id: rowMouse; z: -1; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: row.open() }
    }
}
