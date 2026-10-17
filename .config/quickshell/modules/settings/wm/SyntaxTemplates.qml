import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Syntax page: the templates of one compositor, as cards by topic.
ColumnLayout {
    id: tg
    required property string lg
    required property var groups        // [{ title, icon, names }]
    Layout.fillWidth: true
    spacing: 16
    Repeater {
        model: tg.groups
        NetCard {
            required property var modelData
            Layout.fillWidth: true
            title: modelData.title
            icon: modelData.icon
            Repeater {
                model: modelData.names
                SyntaxTemplateRow { required property string modelData; required property int index; name: modelData; first: index === 0 }
            }
        }
    }
}
