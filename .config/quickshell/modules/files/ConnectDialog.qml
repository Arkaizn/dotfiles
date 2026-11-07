import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.components
import qs.services
import "lib/FmIcons.js" as FmIcons

// Connect to a server: an address (smb://, sftp://, ftp://, dav(s)://, nfs://);
// GVfs mounts it, the password is asked for if needed (and kept in the keyring
// if you tick "Remember"); "Show it in the sidebar" keeps the address there.
// Addresses used before are listed under the field (the ones with the typed
// text in them, newest first): the top one is picked and shows greyed after
// the text — Enter connects to it, Tab fills it in, ↑/↓ pick another (↑ from
// the top: just what's typed); × forgets one.
//   ConnectDialog { known: [{ uri, name }]; history: [uri]; onConnect: (uri, keep) => …; onForget: uri => … }   open()
Modal {
    id: root

    signal connect(string uri, bool keep)
    signal forget(string uri)
    cardWidth: 480
    property var known: []
    property var history: []

    // the history first (newest first), then saved servers not in it
    readonly property var offers: {
        const q = field.text.trim().toLowerCase()
        const all = history.concat(known.map(k => k.uri).filter(u => history.indexOf(u) < 0))
        return all.filter(u => u.toLowerCase().includes(q) && u.toLowerCase() !== q).slice(0, 6)
    }
    property int picked: -1
    onOffersChanged: picked = offers.length && field.text.trim() !== "" ? 0 : -1
    readonly property string ghost: {
        const o = offers[picked], t = field.text
        return picked === 0 && o && t !== "" && o.toLowerCase().startsWith(t.toLowerCase()) ? o.slice(t.length) : ""
    }

    readonly property bool valid: /^(smb|sftp|ssh|ftp|ftps|dav|davs|nfs|afp):\/\/[^\s]+$/i.test(field.text.trim())
    onShownChanged: if (shown) { field.text = ""; keep.checked = true; Qt.callLater(() => field.forceActiveFocus()) }
    function go() {
        if (picked >= 0 && offers[picked]) field.text = offers[picked]
        if (!valid) return
        close()
        connect(field.text.trim(), keep.checked)
    }

    ColumnLayout {
        width: parent.width
        spacing: Tokens.space.s12

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s12
            Rectangle {
                implicitWidth: Tokens.size.controlLarge; implicitHeight: Tokens.size.controlLarge; radius: Tokens.radius.xl
                color: Colors.alpha(Colors.accent, 0.14)
                Text { anchors.centerIn: parent; text: "\u{F048B}"; color: Colors.accent; font.pixelSize: Tokens.font.title; font.family: Properties.fontFamily }
            }
            Text { Layout.fillWidth: true; text: "Connect to a server"; color: Colors.ink; font.pixelSize: Tokens.font.subtitle; font.bold: true; font.family: Properties.fontFamily }
        }
        SearchField {
            id: field
            Layout.fillWidth: true
            icon: "\u{F0318}"
            placeholderText: "smb://nas/share"
            onAccepted: root.go()
            Keys.onPressed: event => {
                const n = root.offers.length
                if (event.key === Qt.Key_Down && n) { root.picked = (root.picked + 1) % n; event.accepted = true }
                else if (event.key === Qt.Key_Up && n) { root.picked = root.picked === 0 ? -1 : root.picked < 0 ? n - 1 : root.picked - 1; event.accepted = true }
                else if (event.key === Qt.Key_Tab && root.picked >= 0) { field.text = root.offers[root.picked]; field.cursorPosition = field.text.length; event.accepted = true }
            }
            // the picked one's rest, greyed after the text
            Text {
                visible: root.ghost !== "" && field.activeFocus
                x: field.leftPadding + field.contentWidth
                anchors.verticalCenter: parent.verticalCenter
                text: root.ghost
                color: Colors.fade(0.35)
                font: field.font
                textFormat: Text.PlainText
            }
        }
        // used before
        Column {
            Layout.fillWidth: true
            visible: root.offers.length > 0
            spacing: Tokens.space.s1
            Text {
                text: field.text.trim() === "" ? "Recent" : "Used before"
                color: Colors.fade(0.45); font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily
                bottomPadding: Tokens.space.s4
            }
            Repeater {
                model: root.offers
                Pressable {
                    id: offer
                    required property string modelData
                    required property int index
                    width: parent.width
                    height: Tokens.size.controlSmall
                    accessibleName: modelData
                    onClicked: { field.text = modelData; root.picked = -1; root.go() }
                    Rectangle {
                        anchors.fill: parent
                        radius: Tokens.radius.md
                        color: offer.index === root.picked ? Colors.fillPressed : offer.hovered ? Colors.fillHover : "transparent"
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        x: Tokens.space.s10
                        width: parent.width - 2 * Tokens.space.s10 - forgetButton.width
                        text: "\u{F048B}  " + offer.modelData
                        color: offer.index === root.picked ? Colors.ink : Colors.fade(0.8)
                        font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily
                        elide: Text.ElideMiddle; textFormat: Text.PlainText
                    }
                    IconButton {
                        id: forgetButton
                        visible: root.history.indexOf(offer.modelData) >= 0
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        iconSize: Tokens.icon.sm
                        icon: "󰅖"
                        tooltip: "Forget this address"
                        onClicked: root.forget(offer.modelData)
                    }
                }
            }
        }
        Text {
            Layout.fillWidth: true
            text: "smb://host/share  ·  sftp://user@host/path  ·  ftp://host  ·  davs://host/path  ·  nfs://host/export"
            color: Colors.fade(0.45); font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily; wrapMode: Text.Wrap
        }
        Checkbox { id: keep; Layout.fillWidth: true; label: "Show it in the sidebar"; onClicked: checked = !checked }
        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            ActionButton { text: "Cancel"; variant: "ghost"; onClicked: root.close() }
            ActionButton { text: "Connect"; variant: "primary"; interactive: root.valid || root.picked >= 0; onClicked: root.go() }
        }
    }
}
