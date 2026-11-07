import QtQuick
import QtQuick.Layouts
import qs.services

// A small capital heading in the sidebar ("BOOKMARKS", "DRIVES"), like Mail's.
Text {
    Layout.leftMargin: Tokens.space.s4
    Layout.bottomMargin: Tokens.space.s2
    color: Colors.fade(0.4)
    font.pixelSize: Tokens.font.micro
    font.bold: true
    font.letterSpacing: 1.2
    font.family: Properties.fontFamily
}
