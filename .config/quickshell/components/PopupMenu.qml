import QtQuick
import QtQuick.Controls
import qs.services

// A small right-click menu: a title, then entries.
//   PopupMenu { id: m; parent: someItem }
//   m.show(item, x, y, "Inbox", [{ icon, label, run, danger, sep }])   (x, y in item's coordinates)
//   backdrop: someItem   what's behind shows through blurred (the file manager's window)
// iconColor: the icon in that colour (a colour choice's preview).
// An entry with sep: true is a line. run() is called after the menu closed,
// so it may change what the menu was opened on.
// Keyboard: ↑/↓ move the highlight, Enter / Space runs it, Esc closes.
Popup {
    id: root
    // the app window's zoom (Ctrl +/−): popups are drawn above it, not inside
    scale: AppZoom.at(parent)
    transformOrigin: Popup.TopLeft

    property string title: ""
    property var entries: []
    property var chosen: null
    property int current: -1          // highlighted by the keyboard
    focus: true
    function step(d) {
        let i = current
        for (let n = 0; n < entries.length; n++) {
            i = (i + d + entries.length) % entries.length
            if (!entries[i].sep) { current = i; return }
        }
    }
    function runCurrent() {
        if (current < 0 || !entries[current] || entries[current].sep) return
        chosen = entries[current].run
        close()
    }

    function show(item, px, py, t, list) {
        title = t ?? ""
        entries = list
        current = -1
        const p = item.mapToItem(parent, px, py)
        // inside the parent: flipped up / left when it would run out
        x = Math.max(4, Math.min(p.x, parent.width - width - 4))
        y = p.y + implicitHeight > parent.height - 4 ? Math.max(4, p.y - implicitHeight) : p.y
        open()
    }
    // one tick later: Qt hands the focus back to where it was before the menu (after onClosed);
    // a dialog the entry opens must get it after that, not lose it to it
    onClosed: if (chosen) { const f = chosen; chosen = null; Qt.callLater(f) }

    padding: 5
    width: 210
    closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Anim.fast; easing.type: Anim.standard }
        NumberAnimation { property: "scale"; from: 0.96 * AppZoom.at(root.parent); to: AppZoom.at(root.parent); duration: Anim.fast; easing.type: Anim.standard }
    }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Anim.instant } }
    // an item of the window to show blurred behind the menu (see PopoverBackground)
    property Item backdrop: null
    background: PopoverBackground { backdrop: root.backdrop }
    contentItem: Column {
        spacing: Tokens.space.s1
        focus: true
        Keys.onUpPressed: root.step(-1)
        Keys.onDownPressed: root.step(1)
        Keys.onReturnPressed: root.runCurrent()
        Keys.onEnterPressed: root.runCurrent()
        Keys.onSpacePressed: root.runCurrent()
        Text {
            visible: root.title !== ""
            width: parent.width
            leftPadding: 9
            topPadding: 3
            bottomPadding: 5
            text: root.title
            color: Colors.fade(0.4)
            font.pixelSize: Tokens.font.micro
            font.bold: true
            font.letterSpacing: 0.6
            font.family: Properties.fontFamily
            elide: Text.ElideRight
        }
        Repeater {
            model: root.entries
            Item {
                id: entry
                required property var modelData
                required property int index
                readonly property bool lit: mouse.containsMouse || root.current === index
                Accessible.role: entry.modelData.sep ? Accessible.Separator : Accessible.MenuItem
                Accessible.name: entry.modelData.label ?? ""
                width: parent.width
                height: modelData.sep ? 9 : 30
                Rectangle {
                    visible: entry.modelData.sep === true
                    anchors.centerIn: parent
                    width: parent.width - 12
                    height: 1
                    color: Colors.fade(0.08)
                }
                Rectangle {
                    visible: !entry.modelData.sep
                    anchors.fill: parent
                    radius: Tokens.radius.md
                    color: entry.lit ? (entry.modelData.danger ? Colors.alpha(Colors.danger, 0.14) : Colors.fillHover) : "transparent"
                    Behavior on color { ColorAnimation { duration: Anim.instant } }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 9
                        spacing: Tokens.space.s10
                        Text {
                            width: 16
                            horizontalAlignment: Text.AlignHCenter
                            text: entry.modelData.icon ?? ""
                            color: entry.modelData.danger ? Colors.danger : entry.modelData.iconColor ?? Icons.tint(text, entry.lit ? Colors.accent : Colors.fade(0.55))
                            font.pixelSize: Tokens.font.body
                            font.family: Properties.fontFamily
                        }
                        Text {
                            text: entry.modelData.label ?? ""
                            color: entry.modelData.danger ? Colors.danger : Colors.fade(0.88)
                            font.pixelSize: Tokens.font.small
                            font.family: Properties.fontFamily
                        }
                    }
                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.current = -1
                        onClicked: { root.chosen = entry.modelData.run; root.close() }
                    }
                }
            }
        }
    }
}
