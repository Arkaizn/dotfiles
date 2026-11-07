import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "lib/FmIcons.js" as FmIcons
import "lib/FmFormat.js" as FmFormat
import "lib/FmPath.js" as FmPath
import "lib/FmAddress.js" as FmAddress

// Back / forward / up and the breadcrumb path. Going up keeps the folders
// below as dimmed crumbs (the trail), so you can step back down.
//   PathBar { path; home; canBack; canForward; onBack; onForward; onUp; onGo: p => …; onEditRequested }
// A click on the empty part of the well (right of the crumbs) asks to type a path (editRequested).
// At the well's right end a flat bookmark (not a star: that is "Starred"): yellow when this folder is bookmarked, grey when not;
// a click toggles it (bookmarkable: false hides it — views, not folders).
//   PathBar { …; bookmarked; bookmarkable; onToggleBookmark; navOnly }
RowLayout {
    id: root

    property string path: "/"
    property string home: ""
    property string specialName: ""       // a view, not a folder ("Trash"): one crumb
    property bool canBack: false
    property bool canForward: false
    signal back()
    signal forward()
    signal up()
    signal go(string path)
    signal editRequested()
    property bool bookmarked: false
    property bool bookmarkable: true
    signal toggleBookmark()
    // the search / address field has the well's place: only the buttons, greyed (the bar doesn't move)
    property bool navOnly: false
    // mounted servers ([{ uri, path, name }]): in one, the crumbs start at the server
    // ("share on srv"), not at /run/user/…/gvfs
    property var mounts: []

    spacing: Tokens.space.s4

    // the deepest path seen on this branch: crumbs past `path` stay until you leave it
    property string trail: path
    onPathChanged: if (path.startsWith("/") && !FmPath.under(trail, path)) trail = path
    readonly property var crumbs: {
        if (specialName !== "") return [{ label: specialName, path: path, home: false }]
        const m = FmAddress.mountOf(trail, mounts)
        if (!m) return FmPath.crumbs(trail, home)
        const root = m.path.replace(/\/+$/, "")
        return [{ label: m.name || FmAddress.toServer(root, mounts), path: root, home: false }]
            .concat(FmPath.crumbs(trail, home).filter(c => c.path.length > root.length && c.path.startsWith(root + "/")))
    }

    IconButton { icon: FmIcons.g.back; tooltip: "Back  (Alt+←)"; interactive: root.canBack && !root.navOnly; onClicked: root.back() }
    IconButton { icon: FmIcons.g.forward; tooltip: "Forward  (Alt+→)"; interactive: root.canForward && !root.navOnly; onClicked: root.forward() }
    IconButton { icon: FmIcons.g.up; tooltip: "Up  (Alt+↑)"; interactive: root.path !== "/" && root.specialName === "" && !root.navOnly; onClicked: root.up() }

    // the crumbs in a well; when they don't fit, the end (where you are) stays visible
    Rectangle {
        visible: !root.navOnly
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.space.s4
        implicitHeight: Tokens.size.control
        radius: Tokens.radius.lg
        color: Colors.surfaceWell
        border.width: Tokens.border.thin
        border.color: Colors.lineSubtle
        clip: true

        // the empty part: click to type a path (the crumbs take their own clicks)
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.IBeamCursor
            onClicked: root.editRequested()
        }

        // bookmarked or not, at a glance (a flat icon in the well, not a button)
        Pressable {
            id: star
            visible: root.bookmarkable
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: Tokens.space.s4
            width: Tokens.size.controlSmall
            height: Tokens.size.controlSmall
            z: 2
            tooltip: root.bookmarked ? "Bookmarked — click to remove  (Ctrl+D)" : "Bookmark this folder  (Ctrl+D)"
            accessibleName: tooltip
            onClicked: root.toggleBookmark()
            Text {
                anchors.centerIn: parent
                text: root.bookmarked ? "\u{F00C0}" : "\u{F00C3}"
                color: root.bookmarked ? Colors.yellow : star.hovered ? Colors.fade(0.6) : Colors.fade(0.3)
                Behavior on color { ColorAnimation { duration: Anim.fast } }
                scale: star.pressed ? 0.85 : 1
                Behavior on scale { NumberAnimation { duration: Anim.fast; easing.type: Anim.pop } }
                font.pixelSize: Tokens.font.label
                font.family: Properties.fontFamily
            }
        }

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.leftMargin: Tokens.space.s4
            anchors.rightMargin: Tokens.space.s4 + (star.visible ? star.width : 0)
            contentWidth: crumbRow.implicitWidth
            // scrolls only when the crumbs don't fit: else clicks reach the empty part (type a path)
            interactive: contentWidth > width
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick
            // keep the open folder in view
            function reveal() {
                // all of them fit: from the start (an earlier, longer trail may have scrolled it)
                if (contentWidth <= width) { contentX = 0; return }
                const it = crumbRepeater.itemAt(root.crumbs.findIndex(c => c.path === root.path))
                if (!it) return
                const x = it.x + it.width
                if (x > contentX + width) contentX = x - width
                else if (it.x < contentX) contentX = it.x
                contentX = Math.max(0, Math.min(contentX, contentWidth - width))
            }
            onWidthChanged: Qt.callLater(reveal)
            // (the crumbs come in after the path changed: their widths decide where the end is)
            onContentWidthChanged: Qt.callLater(reveal)
            // the crumbs end at the bookmark icon, never run under it
            clip: true
            Connections { target: root; function onCrumbsChanged() { Qt.callLater(flick.reveal) } function onPathChanged() { Qt.callLater(flick.reveal) } }

            Row {
                id: crumbRow
                height: flick.height
                spacing: 0
                Repeater {
                    id: crumbRepeater
                    model: root.crumbs
                    Row {
                        required property var modelData
                        required property int index
                        anchors.verticalCenter: parent?.verticalCenter
                        spacing: 0
                        Text {
                            visible: index > 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: FmIcons.g.chevron
                            color: Colors.fade(0.3)
                            font.pixelSize: Tokens.font.small
                            font.family: Properties.fontFamily
                        }
                        Crumb {
                            anchors.verticalCenter: parent.verticalCenter
                            label: modelData.home ? "Home" : FmFormat.shown(modelData.label)
                            icon: modelData.home ? FmIcons.g.home : modelData.path === "/" ? FmIcons.place("root") : ""
                            current: modelData.path === root.path
                            ahead: FmPath.under(modelData.path, root.path) && modelData.path !== root.path
                            onClicked: root.go(modelData.path)
                        }
                    }
                }
            }
        }
    }
}
