import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.components
import qs.services
import "lib/FmIcons.js" as FmIcons
import "lib/FmFormat.js" as FmFormat
import "lib/FmPath.js" as FmPath

// Copy to… / Move to…: pick a folder. The places as chips, up, and the open
// folder's subfolders (click one to go in); the button takes the folder shown.
//   FolderPicker { backend; places }   start({ title, action: "Copy here", path, run: dest => … })
Modal {
    id: root

    required property var backend
    property var places: null
    cardWidth: 520

    property var opt: ({})
    property string path: "/"
    property var names: []
    property bool loading: false
    property string error: ""

    function start(o) {
        opt = o
        open()
        go(o.path || Quickshell.env("HOME"))
    }
    property int _req: 0
    function go(p) {
        path = p
        loading = true
        error = ""
        const req = ++_req
        backend.request("dirs", { path: p }, {
            done: res => { if (req !== root._req) return; root.names = res.names.filter(n => !n.startsWith(".")); root.loading = false },
            error: msg => { if (req !== root._req) return; root.names = []; root.error = msg; root.loading = false }
        })
    }
    readonly property var chips: {
        const pl = places, out = [{ name: "Home", path: Quickshell.env("HOME"), icon: FmIcons.g.home }]
        if (!pl) return out
        for (const x of pl.xdg ?? []) out.push({ name: x.name, path: x.path, icon: FmIcons.place(x.kind) })
        for (const b of pl.bookmarks ?? []) if (b.path && !b.missing) out.push({ name: b.name, path: b.path, icon: FmIcons.g.bookmark })
        for (const m of pl.mounts ?? []) if (m.path) out.push({ name: m.name, path: m.path, icon: FmIcons.g.usb })
        return out
    }

    ColumnLayout {
        width: parent.width
        spacing: Tokens.space.s12

        Text {
            Layout.fillWidth: true
            text: root.opt.title ?? ""
            color: Colors.ink
            font.pixelSize: Tokens.font.subtitle
            font.bold: true
            font.family: Properties.fontFamily
            elide: Text.ElideMiddle
            textFormat: Text.PlainText
        }

        Flow {
            Layout.fillWidth: true
            spacing: Tokens.space.s6
            Repeater {
                model: root.chips
                FilterChip {
                    required property var modelData
                    icon: modelData.icon
                    text: FmFormat.shown(modelData.name)
                    checked: root.path === modelData.path
                    onClicked: root.go(modelData.path)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s6
            IconButton { icon: FmIcons.g.up; tooltip: "Up"; interactive: root.path !== "/"; onClicked: root.go(FmPath.parent(root.path)) }
            Text {
                Layout.fillWidth: true
                text: root.path
                color: Colors.fade(0.75)
                font.pixelSize: Tokens.font.small
                font.family: Properties.fontFamily
                elide: Text.ElideLeft
                textFormat: Text.PlainText
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Tokens.size.row * 6
            radius: Tokens.radius.lg
            color: Colors.surfaceWell
            clip: true
            ListView {
                id: list
                anchors.fill: parent
                anchors.margins: Tokens.space.s4
                model: root.names
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: SlimScrollBar {}
                SmoothWheel { flick: list; step: 100 }
                delegate: Pressable {
                    id: row
                    required property string modelData
                    width: ListView.view.width
                    height: Tokens.size.controlSmall + Tokens.space.s4
                    accessibleName: modelData
                    onClicked: root.go(FmPath.join(root.path, modelData))
                    Rectangle { anchors.fill: parent; radius: Tokens.radius.md; color: row.hovered ? Colors.fillHover : "transparent" }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        x: Tokens.space.s10
                        width: parent.width - 2 * Tokens.space.s10
                        text: FmIcons.g.folder + "  " + FmFormat.shown(row.modelData)
                        color: Colors.fade(0.85)
                        font.pixelSize: Tokens.font.small
                        font.family: Properties.fontFamily
                        elide: Text.ElideMiddle
                        textFormat: Text.PlainText
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: !root.loading && root.names.length === 0
                text: root.error || "No folders inside"
                color: Colors.fade(0.45)
                font.pixelSize: Tokens.font.small
                font.family: Properties.fontFamily
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s8
            Item { Layout.fillWidth: true }
            ActionButton { text: "Cancel"; variant: "ghost"; onClicked: root.close() }
            ActionButton {
                text: root.opt.action ?? "Choose"
                variant: "primary"
                interactive: root.error === ""
                onClicked: { const d = root.path; root.close(); root.opt.run(d) }
            }
        }
    }
}
