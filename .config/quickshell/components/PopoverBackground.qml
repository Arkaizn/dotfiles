import QtQuick
import qs.services

// The surface of every popover (dropdown lists, menus, date / time pickers,
// suggestion lists):  Popup { background: PopoverBackground {} … }
Rectangle {
    radius: Tokens.radius.xl
    color: Colors.surfacePopover
    border.width: Properties.panelBorderWidth
    border.color: Properties.panelBorder
}
