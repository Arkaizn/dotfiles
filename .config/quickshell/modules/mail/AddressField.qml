import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib

// To / Cc / Bcc: comma separated addresses, completed from the collected ones
// (people you wrote to — also from other mail apps, via the sent folders — come
// first, then the ones you got mail from). ↑ ↓ pick, Enter / Tab take it.
SearchField {
    id: root

    property string label: ""
    property int pick: 0
    readonly property var hits: activeFocus ? MailUtil.complete(MailStore.book, text, 6) : []
    readonly property var parsed: MailUtil.parseAddresses(text)

    icon: ""
    clearable: false
    leftPadding: lbl.implicitWidth + 22
    onTextEdited: pick = 0

    Text {
        id: lbl
        anchors.verticalCenter: parent.verticalCenter
        x: 12
        text: root.label
        color: Colors.fade(0.45)
        font.pixelSize: 12
        font.family: Properties.fontFamily
    }

    function take() {
        if (hits.length === 0) return false
        text = MailUtil.insertAddress(text, hits[Math.min(pick, hits.length - 1)])
        cursorPosition = text.length
        return true
    }
    Keys.onDownPressed: event => { if (hits.length) pick = (pick + 1) % hits.length; else event.accepted = false }
    Keys.onUpPressed: event => { if (hits.length) pick = (pick - 1 + hits.length) % hits.length; else event.accepted = false }
    Keys.onReturnPressed: event => { if (!take()) event.accepted = false }
    Keys.onTabPressed: event => { if (!take()) event.accepted = false }

    Popup {
        // the app window's zoom (Ctrl +/−): popups are drawn above it, not inside
        scale: AppZoom.at(parent)
        transformOrigin: Popup.TopLeft
        y: root.height + 4
        width: root.width
        padding: 5
        visible: root.hits.length > 0
        closePolicy: Popup.NoAutoClose
        background: Rectangle {
            radius: Properties.popupRadius
            color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.98)
            border.width: Properties.panelBorderWidth
            border.color: Properties.panelBorder
        }
        contentItem: Column {
            spacing: 1
            Repeater {
                model: root.hits
                Rectangle {
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: 32
                    radius: 7
                    color: index === root.pick ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.16)
                         : hitMouse.containsMouse ? Colors.fade(0.06) : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8
                        Avatar { size: 22; person: modelData }
                        Text { text: modelData.name || modelData.email; color: Colors.ink; font.pixelSize: 12; font.family: Properties.fontFamily
                               Layout.fillWidth: !modelData.name; elide: Text.ElideRight }
                        Text {
                            Layout.fillWidth: true
                            visible: !!modelData.name
                            text: modelData.email
                            color: Colors.fade(0.45)
                            font.pixelSize: 11
                            font.family: Properties.fontFamily
                            elide: Text.ElideRight
                        }
                        // someone you wrote to
                        Text {
                            visible: (modelData.sent ?? 0) > 0
                            Layout.alignment: Qt.AlignRight
                            text: "󰒊"
                            color: Colors.fade(0.4)
                            font.pixelSize: 11
                            font.family: Properties.fontFamily
                        }
                    }
                    MouseArea {
                        id: hitMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.pick = index; root.take(); root.forceActiveFocus() }
                    }
                }
            }
        }
    }
}
