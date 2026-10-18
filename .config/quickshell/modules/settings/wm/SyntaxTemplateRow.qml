import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Syntax page: one template, one line or several (multi-line editor).
NetRow {
    id: tr
    required property string name
    readonly property bool multi: (Syntax.defaults[name] ?? "").includes("\n")
    wide: true
    label: name
    desc: Syntax.docs[name] ?? ""
    changed: Syntax.templates[name] !== undefined
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        // one line
        SearchField {
            visible: !tr.multi
            Layout.fillWidth: true
            implicitHeight: Properties.buttonHeight
            icon: ""
            clearable: false
            font.pixelSize: 12
            text: Syntax.template(tr.name)
            onEditingFinished: if (text !== Syntax.template(tr.name)) Syntax.setTemplate(tr.name, text)
        }
        // several lines
        Rectangle {
            visible: tr.multi
            Layout.fillWidth: true
            implicitHeight: area.implicitHeight + 4
            radius: Properties.radius
            color: Qt.rgba(0, 0, 0, 0.3)
            border.width: 1
            border.color: area.activeFocus ? Colors.fade(0.3) : Properties.cardBorder
            Behavior on border.color { ColorAnimation { duration: 150 } }
            TextArea {
                id: area
                anchors.fill: parent
                padding: 10
                color: Properties.color
                selectionColor: Colors.fade(0.28)
                font.pixelSize: 12
                font.family: Properties.fontFamily
                wrapMode: TextEdit.NoWrap
                background: null
                text: Syntax.template(tr.name)
                onActiveFocusChanged: if (!activeFocus && text !== Syntax.template(tr.name)) Syntax.setTemplate(tr.name, text)
            }
        }
        IconButton {
            Layout.alignment: Qt.AlignTop
            icon: "󰑓"
            tooltip: "Back to default"
            opacity: tr.changed ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            onClicked: Syntax.setTemplate(tr.name, Syntax.defaults[tr.name])
        }
    }
}
