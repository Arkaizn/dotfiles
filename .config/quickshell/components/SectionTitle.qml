import QtQuick
import QtQuick.Layouts
import qs.services

// The small bold heading above a card (what Section draws for its title).
//   SectionTitle { text: "Reminders" }
Text {
    Layout.leftMargin: Tokens.space.s6
    Layout.topMargin: Tokens.space.s6
    color: Colors.textMuted
    font.pixelSize: Tokens.font.small
    font.bold: true
    font.family: Properties.fontFamily
    Accessible.role: Accessible.Heading
}
