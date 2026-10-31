import QtQuick
import QtQuick.Layouts
import qs.services

// A hairline between rows of a card, inset like the rows' text.
Rectangle {
    Layout.fillWidth: true
    Layout.leftMargin: Tokens.space.s16
    Layout.rightMargin: Tokens.space.s16
    implicitHeight: 1
    color: Colors.divider
}
