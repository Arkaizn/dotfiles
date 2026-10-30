import QtQuick
import QtQuick.Layouts
import qs.services

// Calendar app settings, one page each (list on the left): reminders, view,
// sync, then a page per account (its calendars: color, name, shown,
// reminders; remove) and export / import of the accounts. The general options are the same
// keys as the settings app's Calendar page (Settings.calendar), so both stay
// in sync. The pages themselves: CalendarSettingsPages (also in the settings app).
PagedModal {
    id: root

    title: "Calendar settings"
    icon: "󰒓"
    signal addAccount()
    signal transfer(string mode)
    function openAccount(id) { openPage("acc:" + id) }
    onActionPicked: id => { if (id === "add") { close(); addAccount() } }

    pages: CalendarStore.settingsPages

    CalendarSettingsPages {
        Layout.fillWidth: true
        page: root.page
        showAll: root.query !== ""
        onTransfer: mode => { root.close(); root.transfer(mode) }
    }
}
