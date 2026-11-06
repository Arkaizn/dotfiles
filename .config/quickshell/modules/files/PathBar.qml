import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "lib/FmIcons.js" as FmIcons
import "lib/FmFormat.js" as FmFormat
import "lib/FmPath.js" as FmPath

// Back / forward / up and the breadcrumb path. Going up keeps the folders
// below as dimmed crumbs (the trail), so you can step back down.
//   PathBar { path; home; canBack; canForward; onBack; onForward; onUp; onGo: p => …; onEditRequested }
// A click on the empty part of the well (right of the crumbs) asks to type a path (editRequested).
// At the well's right end a flat star: yellow when this folder is bookmarked, grey when not;
// a click toggles it (bookmarkable: false hides it — views, not folders).
//   PathBar { …; bookmarked; bookmarkable; onToggleBookmark }
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

    spacing: Tokens.space.s4

    // the deepest path seen on this branch: crumbs past `path` stay until you leave it
    property string trail: path
    onPathChanged: if (path.startsWith("/") && !FmPath.under(trail, path)) trail = path
    readonly property var crumbs: specialName !== "" ? [{ label: specialName, path: path, home: false }] : FmPath.crumbs(trail, home)

    IconButton { icon: FmIcons.g.back; tooltip: "Back  (Alt+←)"; interactive: root.canBack; onClicked: root.back() }
    IconButton { icon: FmIcons.g.forward; tooltip: "Forward  (Alt+→)"; interactive: root.canForward; onClicked: root.forward() }
    IconButton { icon: FmIcons.g.up; tooltip: "Up  (Alt+↑)"; interactive: root.path !== "/" && root.specialName === ""; onClicked: root.up() }

    // the crumbs in a well; when they don't fit, the end (where you are) stays visible
    Rectangle {
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
                text: root.bookmarked ? "\u{F04CE}" : "\u{F04D2}"
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
                const it = crumbRepeater.itemAt(root.crumbs.findIndex(c => c.path === root.path))
                if (!it) return
                const x = it.x + it.width
                if (x > contentX + width) contentX = x - width
                else if (it.x < contentX) contentX = it.x
            }
            onWidthChanged: Qt.callLater(reveal)
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
