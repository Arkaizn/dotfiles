import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import "lib/FmFormat.js" as FmFormat
import "lib/FmPath.js" as FmPath

// Open with…: the apps for the file's type (recommended first, the default
// marked), or every app on the computer ("Show all apps"); the field filters
// them by name. A click opens the file(s) in it. "Always use it for <type>"
// makes it the default for that type (the backend backs up mimeapps.list first;
// Settings → Default apps shows the result).
//   OpenWithDialog { backend; onFailed: msg => … }   start(paths, type)
Modal {
    id: root

    required property var backend
    signal failed(string msg)
    cardWidth: 460

    property var paths: []
    property string mime: ""
    property var apps: []
    property string description: ""
    property bool always: false
    property bool loading: false
    property bool all: false
    property var allApps: []
    readonly property var shown: {
        const q = search.text.trim().toLowerCase()
        return (all ? allApps : apps).filter(a => q === "" || a.name.toLowerCase().includes(q) || a.id.toLowerCase().includes(q))
    }

    function start(list, type) {
        paths = list
        mime = type
        apps = []
        always = false
        all = false
        search.text = ""
        loading = true
        open()
        search.forceActiveFocus()
        backend.request("apps", { type: type }, {
            done: res => { root.apps = res.apps; root.description = res.description; root.loading = false },
            error: msg => { root.loading = false; root.failed(msg) }
        })
    }
    function pick(app) {
        close()
        if (always) backend.request("setDefault", { type: mime, app: app.id }, { error: msg => root.failed(msg) })
        backend.request("launchWith", { paths: paths, app: app.id }, { error: msg => root.failed(msg) })
    }

    ColumnLayout {
        width: parent.width
        spacing: Tokens.space.s12

        Text {
            Layout.fillWidth: true
            text: "Open " + (root.paths.length === 1 ? "“" + FmFormat.shown(FmPath.base(root.paths[0])) + "”" : root.paths.length + " files") + " with"
            color: Colors.ink; font.pixelSize: Tokens.font.subtitle; font.bold: true; font.family: Properties.fontFamily
            elide: Text.ElideMiddle; textFormat: Text.PlainText
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s8
            SearchField {
                id: search
                Layout.fillWidth: true
                placeholderText: "Search apps"
                onAccepted: if (root.shown.length) root.pick(root.shown[0])
            }
            ActionButton {
                text: root.all ? "Suggested apps" : "Show all apps"
                onClicked: {
                    root.all = !root.all
                    if (root.all && root.allApps.length === 0)
                        root.backend.request("apps", { all: true }, { done: res => root.allApps = res.apps, error: msg => root.failed(msg) })
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Tokens.size.row * 7
            radius: Tokens.radius.lg
            color: Colors.surfaceWell
            clip: true
            ListView {
                id: list
                anchors.fill: parent
                anchors.margins: Tokens.space.s4
                model: root.shown
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: SlimScrollBar {}
                SmoothWheel { flick: list; step: 100 }
                delegate: Pressable {
                    id: row
                    required property var modelData
                    width: ListView.view.width
                    height: Tokens.size.control
                    accessibleName: modelData.name
                    onClicked: root.pick(modelData)
                    Rectangle { anchors.fill: parent; radius: Tokens.radius.md; color: row.hovered ? Colors.fillHover : "transparent" }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.space.s10
                        anchors.rightMargin: Tokens.space.s10
                        spacing: Tokens.space.s10
                        Image {
                            Layout.preferredWidth: Tokens.icon.lg
                            Layout.preferredHeight: Tokens.icon.lg
                            sourceSize: Qt.size(Tokens.icon.lg * 2, Tokens.icon.lg * 2)
                            source: row.modelData.icon && !row.modelData.icon.includes(" ") ? Quickshell.iconPath(row.modelData.icon, true) : ""
                        }
                        Text { Layout.fillWidth: true; text: row.modelData.name; color: Colors.ink; font.pixelSize: Tokens.font.small
                               font.family: Properties.fontFamily; elide: Text.ElideRight }
                        Text { visible: row.modelData.default === true; text: "default"; color: Colors.fade(0.45); font.pixelSize: Tokens.font.micro; font.family: Properties.fontFamily }
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: !root.loading && root.shown.length === 0
                text: search.text !== "" ? "No app matches" : root.all ? "Loading…" : "No app is registered for this kind of file — try “Show all apps”"
                color: Colors.fade(0.45); font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily
            }
        }
        Checkbox {
            Layout.fillWidth: true
            label: "Always use it for " + (root.description || root.mime)
            checked: root.always
            onClicked: root.always = !root.always
        }
        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            ActionButton { text: "Cancel"; variant: "ghost"; onClicked: root.close() }
        }
    }
}
