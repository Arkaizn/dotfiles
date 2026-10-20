import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services

// Tray app menu, hanging from the bar under the clicked icon like the other
// bar popups (window/shape/animation from BarPopup).
// Submenus open inside the same panel: the list slides over and a back row
// appears at the top.
BarPopup {
    id: root
    side: "at"
    panelWidth: 260
    maxHeight: 620   // fixed surface; the panel itself animates between menu heights
    // while a menu is still loading, hold the current size (no shrink-then-grow)
    panelHeight: loading ? heldHeight : Math.min(col.implicitHeight + padding * 2, maxHeight)
    Behavior on panelHeight {
        enabled: root.shown && root.reveal === 1
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    property var trayItem: null
    property var stack: []          // opened submenu entries, deepest last
    readonly property var currentMenu: stack.length > 0 ? stack[stack.length - 1] : (trayItem?.menu ?? null)

    // ── Waiting for the app's menu ──
    // Some apps (Steam) send their menu empty and fill it in ~100ms later.
    // Opening/switching right away showed the empty menu first, then the panel
    // grew. So: switch the menu, wait until it has entries (max 400ms), then
    // open / move / slide in.
    property bool loading: false
    property real heldHeight: 0
    property var _onLoaded: null

    function afterLoad(fn) {
        heldHeight = panelHeight
        loading = true
        _onLoaded = fn
        loadTimer.elapsed = 0
        loadTimer.restart()
    }

    Timer {
        id: loadTimer
        property int elapsed: 0
        interval: 15
        repeat: true
        onTriggered: {
            elapsed += interval
            if ((opener.children?.values?.length ?? 0) === 0 && elapsed < 400) return
            stop()
            root.loading = false
            const fn = root._onLoaded
            root._onLoaded = null
            if (fn) fn()
        }
    }

    // Right click on the same icon again closes it, another icon switches over
    function toggleFor(item, scr, x) {
        if (shown && trayItem === item) { close(); return }
        const switching = shown && scr === screen
        const dir = x > atX ? 1 : -1
        trayItem = item
        stack = []
        afterLoad(() => {
            atX = x            // panel glides over (BarPopup animates ox)
            if (switching) slide(dir)   // content comes in from the side we moved to
            else open(scr)
        })
    }

    onPopupClosed: { loadTimer.stop(); loading = false; stack = []; trayItem = null }

    function enter(entry) {
        stack = stack.concat([entry])
        afterLoad(() => slide(1))
    }
    function back() {
        stack = stack.slice(0, -1)
        slide(-1)
    }
    function slide(dir) {
        slideAnim.stop()
        slideAnim.from = dir * 50
        slideAnim.start()
    }

    QsMenuOpener {
        id: opener
        menu: root.currentMenu
    }
    // Keep the app's menu and every submenu on the way open while inside one:
    // with only the opener above, switching it to a submenu released the menu
    // that submenu belongs to, and DBus menus (Tailscale's "Exit Nodes", …)
    // then showed the submenu empty.
    QsMenuOpener { menu: root.trayItem?.menu ?? null }
    Instantiator {
        model: root.stack
        delegate: QsMenuOpener {
            required property var modelData
            menu: modelData
        }
    }

    ParallelAnimation {
        id: slideAnim
        property real from: 0
        NumberAnimation { target: list; property: "slideX"; from: slideAnim.from; to: 0; duration: 200; easing.type: Easing.OutCubic }
        NumberAnimation { target: list; property: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutCubic }
    }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 6

        // ── Header: app icon + name, or "‹ submenu" when inside one ──
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 34
            radius: 10
            color: headerMouse.containsMouse && root.stack.length > 0 ? Colors.fade(0.08) : "transparent"
            Behavior on color { ColorAnimation { duration: 80 } }

            MouseArea {
                id: headerMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: root.stack.length > 0
                cursorShape: Qt.PointingHandCursor
                onClicked: root.back()
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                spacing: 8

                Text {
                    visible: root.stack.length > 0
                    text: "󰅁"
                    color: Colors.ink
                    font.pixelSize: 14
                    font.family: Properties.fontFamily
                }
                IconImage {
                    visible: root.stack.length === 0
                    source: root.trayItem?.icon ?? ""
                    implicitSize: 16
                }
                Text {
                    Layout.fillWidth: true
                    text: root.stack.length > 0
                        ? root.stack[root.stack.length - 1].text.replace(/_/g, "")
                        // title is the short app name; tooltips can be multi-line status text
                        : (root.trayItem?.title || (root.trayItem?.tooltipTitle ?? "").split("\n")[0] || root.trayItem?.id || "")
                    textFormat: Text.PlainText
                    maximumLineCount: 1
                    wrapMode: Text.NoWrap
                    color: Colors.ink
                    font.pixelSize: 13
                    font.bold: true
                    elide: Text.ElideRight
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Colors.fade(0.13) }

        // ── Entries ──
        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(list.implicitHeight, root.maxHeight - 34 - 13 - root.padding * 2)
            contentHeight: list.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: list
                width: flick.width
                spacing: 2
                visible: !root.loading
                property real slideX: 0
                transform: Translate { x: list.slideX }

                Repeater {
                    model: opener.children

                    delegate: TrayMenuEntry {
                        required property var modelData
                        Layout.fillWidth: true
                        entry: modelData
                        onActivated: {
                            if (entry.hasChildren) {
                                root.enter(entry)
                            } else {
                                entry.triggered()
                                root.close()
                            }
                        }
                    }
                }
            }
        }
    }
}
