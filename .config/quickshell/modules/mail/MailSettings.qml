import QtQuick
import QtQuick.Layouts
import qs.services
import "../calendar"
import "MailIcons.js" as I

// Mail app settings, one page each (list on the left): new mail, reading,
// writing, actions, the sidebar's favorites (the same keys as the settings
// app's Mail page, Settings.mail), then a page per account (name, color,
// signature, notifications, on / off, servers, remove) and export / import.
// The pages themselves: MailSettingsPages (also in the settings app).
//   openAccount(id)  — straight to an account's page
PagedModal {
    id: root

    title: "Mail settings"
    icon: I.cog
    signal editAccount(var account)
    signal transfer(string mode)
    signal addAccount()
    onShownChanged: if (shown) DefaultApps.refresh()
    function openAccount(id) { openPage("acc:" + id) }
    onActionPicked: id => { if (id === "add") { close(); addAccount() } }

    pages: MailStore.settingsPages

    MailSettingsPages {
        Layout.fillWidth: true
        page: root.page
        showAll: root.query !== ""
        onEditAccount: a => { root.close(); root.editAccount(a) }
        onTransfer: mode => { root.close(); root.transfer(mode) }
        onOpenPage: id => root.page = id
    }
}
