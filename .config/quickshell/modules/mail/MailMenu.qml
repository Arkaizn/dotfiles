import QtQuick
import QtQuick.Controls
import qs.services

// A small right-click menu: a title, then entries.
//   MailMenu { id: m }
//   m.show(item, x, y, "Inbox", [{ icon, label, run, danger, sep }])   (x, y in item's coordinates)
// An entry with sep: true is a line. run() is called after the menu closed,
// so it may change what the menu was opened on.
Popup {
    id: root
    // the app window's zoom (Ctrl +/−): popups are drawn above it, not inside
    scale: AppZoom.at(parent)
    transformOrigin: Popup.TopLeft

    property string title: ""
    property var entries: []
    property var chosen: null

    function show(item, px, py, t, list) {
        title = t ?? ""
        entries = list
        const p = item.mapToItem(parent, px, py)
        // inside the parent: flipped up / left when it would run out
        x = Math.max(4, Math.min(p.x, parent.width - width - 4))
        y = p.y + implicitHeight > parent.height - 4 ? Math.max(4, p.y - implicitHeight) : p.y
        open()
    }
    onClosed: if (chosen) { const f = chosen; chosen = null; f() }

    padding: 5
    width: 210
    closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 110; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 0.96 * AppZoom.at(root.parent); to: AppZoom.at(root.parent); duration: 130; easing.type: Easing.OutCubic }
    }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 90 } }
    background: Rectangle {
        radius: Properties.popupRadius
        color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.98)
        border.width: Properties.panelBorderWidth
        border.color: Properties.panelBorder
    }
    contentItem: Column {
        spacing: 1
        Text {
            visible: root.title !== ""
            width: parent.width
            leftPadding: 9
            topPadding: 3
            bottomPadding: 5
            text: root.title
            color: Colors.fade(0.4)
            font.pixelSize: 10
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
                    radius: 7
                    color: mouse.containsMouse ? (entry.modelData.danger ? Qt.rgba(Colors.red.r, Colors.red.g, Colors.red.b, 0.14) : Colors.fade(0.08)) : "transparent"
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 9
                        spacing: 10
                        Text {
                            width: 16
                            horizontalAlignment: Text.AlignHCenter
                            text: entry.modelData.icon ?? ""
                            color: entry.modelData.danger ? Colors.red : mouse.containsMouse ? Colors.color6 : Colors.fade(0.55)
                            font.pixelSize: 13
                            font.family: Properties.fontFamily
                        }
                        Text {
                            text: entry.modelData.label ?? ""
                            color: entry.modelData.danger ? Colors.red : Colors.fade(0.88)
                            font.pixelSize: 12
                            font.family: Properties.fontFamily
                        }
                    }
                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.chosen = entry.modelData.run; root.close() }
                    }
                }
            }
        }
    }
}
