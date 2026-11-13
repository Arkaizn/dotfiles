import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// What Settings shows when it's opened without a page: nothing but a pointer to
// the search and the folded groups in the sidebar.
ColumnLayout {
    Item { implicitHeight: 90 }
    EmptyState {
        Layout.fillWidth: true
        icon: "󰒓"
        text: "Search, or pick a group on the left"
        hint: "Ctrl+F or / starts a search from anywhere in Settings"
    }
}
