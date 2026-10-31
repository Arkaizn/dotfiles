import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.components
import qs.services

// A module on the bar layout page. Drag it to another zone (or within one);
// × takes it off the bar. While it's dragged, a ghost (on the page) follows the
// pointer and the chip itself fades.
Rectangle {
    id: chip
    required property string modId
    required property string zone          // "" = not on the bar
    required property Item page            // BarLayoutPage (drag state + ghost)

    // other layout pages (dashboard, control center) bring their own info() / addZone
    readonly property var mod: page.info ? page.info(modId) : BarLayout.module(modId)
    readonly property bool dragged: page.dragId === modId

    implicitWidth: row.implicitWidth + 20
    implicitHeight: 34
    radius: 9
    opacity: dragged ? 0.3 : 1
    color: mouse.containsMouse && page.editable ? Colors.fade(0.10) : Colors.fade(0.05)
    border.width: 1
    border.color: zone === "" ? Colors.fade(0.10) : Colors.alpha(Colors.color6, 0.35)
    Behavior on color { ColorAnimation { duration: Anim.fast } }
    Behavior on opacity { NumberAnimation { duration: Anim.fast } }

    HoverTip { shown: mouse.containsMouse && page.dragId === "" && mod.desc !== ""; text: mod.desc }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: chip.page.editable
        cursorShape: chip.page.editable ? (drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor
        preventStealing: true
        drag.target: chip.page.ghost
        drag.threshold: 4
        onPressed: chip.page.prepareDrag(chip)
        drag.onActiveChanged: if (drag.active) chip.page.startDrag(chip.modId, chip.zone)
        onReleased: chip.page.endDrag()
        onCanceled: chip.page.cancelDrag()
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 7
        Text {
            text: chip.mod.icon
            color: chip.zone === "" ? Colors.fade(0.5) : Colors.color6
            font.pixelSize: Tokens.font.label
            font.family: Properties.fontFamily
        }
        Text {
            text: chip.mod.name
            color: chip.zone === "" ? Colors.fade(0.6) : Colors.ink
            font.pixelSize: Tokens.font.small
            font.family: Properties.fontFamily
        }
        // take off the bar / put on the bar (right end)
        Text {
            visible: chip.page.editable
            text: chip.zone === "" ? "󰐕" : "󰅖"
            color: xMouse.containsMouse ? (chip.zone === "" ? Colors.color6 : Colors.red) : Colors.fade(0.4)
            font.pixelSize: Tokens.font.body
            font.family: Properties.fontFamily
            MouseArea {
                id: xMouse
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: chip.zone === "" ? chip.page.place(chip.modId, chip.page.addZone ?? "right", chip.page.addIndex ?? 0)
                                            : chip.page.place(chip.modId, "", 0)
            }
        }
    }
}
