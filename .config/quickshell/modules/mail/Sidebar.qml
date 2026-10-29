import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import "../calendar"
import "MailIcons.js" as I

// Folder list: the unified views, local drafts, then each account with its folders.
Flickable {
    id: root

    property string view: "unified:inbox"
    signal picked(string view)
    signal accountMenu(string id)

    contentHeight: col.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: CalScrollBar {}
    SmoothWheel { flick: root; step: 100 }       // like the settings app's page list

    ColumnLayout {
        id: col
        width: root.width
        spacing: 1

        Label { text: "FAVORITES" }
        // the unified views switched on in the settings (Mail → Favorites)
        Repeater {
            model: MailStore.favorites
            Entry {
                required property string modelData
                readonly property bool many: MailStore.activeAccounts.length > 1
                v: "unified:" + modelData
                current: root.view === v
                onActivated: root.picked(v)
                icon: modelData === "unread" ? I.mail : modelData === "flagged" ? I.star : I.role(modelData)
                label: ({ inbox: many ? "All inboxes" : "Inbox", unread: "Unread", flagged: "Starred",
                          sent: many ? "All sent" : "Sent", drafts: many ? "All drafts" : "Drafts",
                          archive: many ? "All archived" : "Archive", trash: many ? "All deleted" : "Trash",
                          junk: many ? "All junk" : "Junk" })[modelData]
                count: modelData === "inbox" || modelData === "unread" ? MailStore.unread : 0
                muted: modelData !== "inbox"
            }
        }
        Entry { v: "local:drafts"; current: root.view === v; onActivated: root.picked(v); icon: I.draft; label: "Unsent drafts"; visible: MailStore.drafts.length > 0
                count: MailStore.drafts.length; muted: true }
        // pinned folders (the pin on a folder's row)
        Repeater {
            model: MailStore.pinnedViews
            Entry {
                required property var modelData
                v: modelData.view
                current: root.view === v
                onActivated: root.picked(v)
                icon: I.role(modelData.folder.role)
                label: modelData.folder.role === "inbox" ? "Inbox" : modelData.folder.name
                hint: MailStore.activeAccounts.length > 1 ? (modelData.account.name || modelData.account.email) : ""
                dot: MailStore.activeAccounts.length > 1 ? (modelData.account.color ?? "") : ""
                count: MailStore.unreadIn(modelData.account.id, modelData.folder.path)
                muted: modelData.folder.role !== "inbox"
                pinnable: true
                pinned: true
                onPinToggled: MailStore.togglePin(modelData.account.id, modelData.folder.path)
            }
        }

        Repeater {
            model: MailStore.accounts
            ColumnLayout {
                id: acc
                required property var modelData
                readonly property bool on: modelData.enabled !== false
                readonly property string error: MailStore.errors[modelData.id] ?? ""
                property bool collapsed: false
                Layout.fillWidth: true
                Layout.topMargin: 10
                spacing: 1

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 24
                    HoverHandler { id: accHover }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 4
                        spacing: 6
                        Rectangle { implicitWidth: 7; implicitHeight: 7; radius: 4; color: acc.modelData.color ?? Colors.color6
                                    opacity: acc.on ? 1 : 0.35 }
                        Text {
                            Layout.fillWidth: true
                            text: (acc.modelData.name || acc.modelData.email).toUpperCase()
                            color: Colors.fade(acc.on ? 0.45 : 0.25)
                            font.pixelSize: 10
                            font.bold: true
                            font.letterSpacing: 1.1
                            font.family: Properties.fontFamily
                            elide: Text.ElideRight
                        }
                        Text {
                            visible: acc.error !== ""
                            text: I.junk
                            color: Colors.red
                            font.pixelSize: 12
                            font.family: Properties.fontFamily
                            HoverHandler { id: errHover }
                            ToolTip.visible: errHover.hovered
                            ToolTip.text: acc.error
                        }
                        Text {
                            text: acc.collapsed ? I.right : I.down
                            color: Colors.fade(accHover.hovered ? 0.5 : 0)
                            font.pixelSize: 12
                            font.family: Properties.fontFamily
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: m => m.button === Qt.RightButton ? root.accountMenu(acc.modelData.id) : acc.collapsed = !acc.collapsed
                    }
                }
                Text {
                    visible: !acc.on
                    Layout.leftMargin: 17
                    text: "Off — not checked"
                    color: Colors.fade(0.3)
                    font.pixelSize: 10
                    font.family: Properties.fontFamily
                }
                Repeater {
                    model: acc.on && !acc.collapsed ? (acc.modelData.folders ?? []) : []
                    Entry {
                        required property var modelData
                        v: acc.modelData.id + "|" + modelData.path
                        current: root.view === v
                        onActivated: root.picked(v)
                        icon: I.role(modelData.role)
                        label: modelData.role === "inbox" ? "Inbox" : modelData.name
                        indent: Math.min(3, modelData.depth ?? 0)
                        count: ["sent", "drafts", "trash", "junk", "all"].includes(modelData.role) ? 0
                             : MailStore.unreadIn(acc.modelData.id, modelData.path) || (modelData.unread ?? 0)
                        muted: modelData.role !== "inbox"
                        pinnable: true
                        pinned: MailStore.isPinned(acc.modelData.id, modelData.path)
                        onPinToggled: MailStore.togglePin(acc.modelData.id, modelData.path)
                    }
                }
            }
        }
    }

    component Label: Text {
        Layout.leftMargin: 4
        Layout.bottomMargin: 2
        color: Colors.fade(0.4)
        font.pixelSize: 10
        font.bold: true
        font.letterSpacing: 1.2
        font.family: Properties.fontFamily
    }

    component Entry: Rectangle {
        id: e
        property string v
        property string icon
        property string label
        property int count: 0
        property bool muted: false
        property int indent: 0
        property bool current: false
        property string hint: ""             // e.g. the account of a pinned folder
        property string dot: ""              // a color dot (the account) in front
        property bool pinnable: false
        property bool pinned: false
        signal activated()
        signal pinToggled()
        Layout.fillWidth: true
        implicitHeight: 30
        radius: 8
        color: current ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.16)
             : eHover.hovered ? Colors.fade(0.06) : "transparent"
        HoverHandler { id: eHover }
        Behavior on color { ColorAnimation { duration: 100 } }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8 + e.indent * 12
            anchors.rightMargin: 8
            spacing: 9
            Text {
                text: e.icon
                color: e.current ? Colors.color6 : Colors.fade(0.55)
                font.pixelSize: 14
                font.family: Properties.fontFamily
                Rectangle {
                    visible: e.dot !== ""
                    anchors { right: parent.right; bottom: parent.bottom; rightMargin: -2; bottomMargin: 0 }
                    width: 6; height: 6; radius: 3
                    color: e.dot || "transparent"
                    border.width: 1
                    border.color: Colors.background
                }
            }
            Text {
                Layout.fillWidth: true
                text: e.label + (e.hint ? '<font color="' + Colors.fade(0.4) + '">  ·  ' + e.hint + '</font>' : "")
                textFormat: e.hint ? Text.StyledText : Text.PlainText
                color: e.current ? Colors.ink : Colors.fade(0.78)
                font.pixelSize: 12
                font.bold: e.count > 0 && !e.muted
                font.family: Properties.fontFamily
                elide: Text.ElideRight
            }
            // pin to the favorites / unpin (on hover)
            Text {
                visible: e.pinnable && eHover.hovered
                text: e.pinned ? "󰤰" : "󰐃"
                color: pinHover.containsMouse ? Colors.color6 : Colors.fade(0.5)
                font.pixelSize: 12
                font.family: Properties.fontFamily
                // a MouseArea (not a TapHandler): the click must not also open the folder
                MouseArea {
                    id: pinHover
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: e.pinToggled()
                }
                ToolTip.visible: pinHover.containsMouse
                ToolTip.text: e.pinned ? "Remove from favorites" : "Pin to favorites"
                ToolTip.delay: 400
            }
            Text {
                visible: e.count > 0 && !(e.pinnable && eHover.hovered)
                text: e.count > 999 ? "999+" : e.count
                color: e.muted ? Colors.fade(0.45) : Colors.color6
                font.pixelSize: 11
                font.bold: !e.muted
                font.family: Properties.fontFamily
            }
        }
        MouseArea {
            id: eMouse
            z: -1                         // under the row's content: the pin takes its own clicks
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: e.activated()
        }
    }
}
