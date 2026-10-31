import QtQuick
import QtQuick.Layouts
import qs.services

// A tinted box with a message inside a page or dialog: something to know
// (info), to watch out for (warn), that went wrong (error) or worked (ok).
// Optional action button on the right and a close ×.
//
//   Banner { tone: "error"; text: "Couldn't save: disk full" }
//   Banner { tone: "warn"; title: "Restart needed"; text: "…"; actionText: "Restart"; onAction: … }
//   Banner { tone: "info"; text: "…"; closable: true; onClosed: hide = true }
Rectangle {
    id: root
    property string tone: "info"          // "info" | "warn" | "error" | "ok"
    property string title: ""
    property string text: ""
    property string icon: tone === "error" ? "󰅙" : tone === "warn" ? "󰀦" : tone === "ok" ? "󰄬" : "󰋼"
    property string actionText: ""
    property bool closable: false
    signal action()
    signal closed()

    readonly property color toneColor: tone === "error" ? Colors.danger : tone === "warn" ? Colors.warning
                                     : tone === "ok" ? Colors.success : Colors.info

    Layout.fillWidth: true
    implicitHeight: row.implicitHeight + 2 * Tokens.space.s12
    radius: Tokens.radius.card
    color: Colors.tint(toneColor, 0.12)
    border.width: Tokens.border.thin
    border.color: Colors.alpha(toneColor, 0.35)
    Accessible.role: Accessible.AlertMessage
    Accessible.name: (title !== "" ? title + ". " : "") + text

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: Tokens.space.s12
        spacing: Tokens.space.s10
        Text {
            Layout.alignment: Qt.AlignTop
            text: root.icon
            color: root.toneColor
            font.pixelSize: Tokens.font.subtitle
            font.family: Properties.fontFamily
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s2
            Text {
                visible: root.title !== ""
                Layout.fillWidth: true
                text: root.title
                color: Colors.ink
                font.pixelSize: Tokens.font.body
                font.bold: true
                font.family: Properties.fontFamily
                wrapMode: Text.Wrap
            }
            Text {
                visible: root.text !== ""
                Layout.fillWidth: true
                text: root.text
                color: Colors.textSecondary
                font.pixelSize: Tokens.font.small
                font.family: Properties.fontFamily
                wrapMode: Text.Wrap
            }
        }
        ActionButton {
            visible: root.actionText !== ""
            Layout.alignment: Qt.AlignVCenter
            text: root.actionText
            onClicked: root.action()
        }
        IconButton {
            visible: root.closable
            Layout.alignment: Qt.AlignTop
            implicitWidth: 24; implicitHeight: 24
            iconSize: Tokens.icon.sm
            icon: "󰅖"
            tooltip: "Dismiss"
            onClicked: root.closed()
        }
    }
}
