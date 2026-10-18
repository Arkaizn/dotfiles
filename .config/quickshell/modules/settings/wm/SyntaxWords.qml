import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Syntax page: the names the compositor uses (Syntax.words), editable.
//   SyntaxWords { lg: "niri" }   ("niri" | "hypr")
NetCard {
    id: wc
    required property string lg
    Layout.fillWidth: true
    title: "Words  ·  names " + (lg === "hypr" ? "Hyprland" : "niri") + " uses"
    icon: "󰗊"
    GridLayout {
        Layout.fillWidth: true
        Layout.margins: 14
        columns: 1
        columnSpacing: 14
        rowSpacing: 8
        Repeater {
            model: Object.keys(Syntax.wordDefaults[wc.lg])
            RowLayout {
                id: wr
                required property string modelData
                readonly property bool changed: Syntax.words[wc.lg + "." + modelData] !== undefined
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 6
                Text {
                    Layout.preferredWidth: 230
                    text: "{@" + wr.modelData + "}"
                    color: wr.changed ? Colors.color6 : Colors.fade(0.6)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                    elide: Text.ElideRight
                }
                SearchField {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    icon: ""
                    clearable: false
                    font.pixelSize: 11
                    text: Syntax.word(wc.lg, wr.modelData)
                    onEditingFinished: if (text !== Syntax.word(wc.lg, wr.modelData)) Syntax.setWord(wc.lg, wr.modelData, text.trim())
                }
                IconButton {
                    implicitWidth: 26; implicitHeight: 26; iconSize: 12
                    icon: "󰑓"
                    tooltip: "Back to: " + Syntax.wordDefaults[wc.lg][wr.modelData]
                    opacity: wr.changed ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    onClicked: Syntax.setWord(wc.lg, wr.modelData, "")
                }
            }
        }
    }
}
