import QtQuick
import qs.services

// A module's icon in the bar preview of the layout page.
Text {
    property string modId
    property bool strong: false
    text: BarLayout.module(modId).icon
    color: strong ? Colors.color6 : Colors.fade(0.8)
    font.pixelSize: 15
    font.family: Properties.fontFamily
}
