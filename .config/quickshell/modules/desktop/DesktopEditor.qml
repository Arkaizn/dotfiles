import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import "../settings"
import "../settings/network"

// Live editor for the desktop widgets on one monitor (overlay above windows
// while it's open; the real widgets hide meanwhile).
//   drag            move (hold Ctrl: snaps to an invisible 16 px grid)
//   top handle      rotate (sticks to right angles; Ctrl: 15° steps)
//   corner handle   resize (Ctrl: steps of 10 %)
//   click           select → options on the right; empty spot: deselect
//   keys            Esc (deselect / close), Delete, Ctrl+D duplicate,
//                   arrows nudge (Shift: 10×), R reset rotation and size
PanelWindow {
    id: ed
    required property var modelData
    screen: modelData
    readonly property string screenName: modelData.name
    readonly property bool hasKeyboard: DesktopWidgets.editScreen === screenName

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:desktop-editor"
    WlrLayershell.keyboardFocus: hasKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    // a file dialog is open: step aside so it can be seen
    visible: !DesktopWidgets.fileDialog

    readonly property var ids: DesktopWidgets.idsFor(screenName)
    readonly property var sel: DesktopWidgets.byId[DesktopWidgets.selected] ?? null
    readonly property bool selHere: sel !== null && ids.includes(sel.id)

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.32)
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity { NumberAnimation { duration: 180 } }
    }

    // empty spot: deselect, take the keyboard
    MouseArea {
        anchors.fill: parent
        onPressed: { DesktopWidgets.editScreen = ed.screenName; DesktopWidgets.selected = ""; palette.open = false }
    }

    // ── keyboard ────────────────────────────────────────────────────────────
    Item {
        id: keys
        focus: ed.hasKeyboard
        Keys.onPressed: e => {
            const s = ed.selHere ? ed.sel : null
            if (e.key === Qt.Key_Escape) { if (palette.open) palette.open = false; else if (DesktopWidgets.selected !== "") DesktopWidgets.selected = ""; else DesktopWidgets.stopEdit() }
            else if (!s) return
            else if (e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) DesktopWidgets.remove(s.id)
            else if (e.key === Qt.Key_D && (e.modifiers & Qt.ControlModifier)) DesktopWidgets.duplicate(s.id)
            else if (e.key === Qt.Key_R) DesktopWidgets.update(s.id, { rot: 0, scale: 1 })
            else if ([Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down].includes(e.key)) {
                const step = (e.modifiers & Qt.ShiftModifier) ? 10 : 1
                const dx = e.key === Qt.Key_Left ? -step : e.key === Qt.Key_Right ? step : 0
                const dy = e.key === Qt.Key_Up ? -step : e.key === Qt.Key_Down ? step : 0
                DesktopWidgets.update(s.id, { x: DeskWidgets.toRel(s.x * ed.width + dx, ed.width), y: DeskWidgets.toRel(s.y * ed.height + dy, ed.height) })
            }
            else return
            e.accepted = true
        }
    }

    // ── the widgets ─────────────────────────────────────────────────────────
    Repeater {
        model: ed.ids
        Item {
            id: it
            required property string modelData
            readonly property var inst: DesktopWidgets.byId[modelData] ?? null
            readonly property bool selected: DesktopWidgets.selected === modelData
            z: selected ? 2 : 1

            // while dragging / rotating / resizing: live values, saved on release
            property bool manip: false
            property real liveX: 0
            property real liveY: 0
            property real liveRot: 0
            property real liveScale: 1
            readonly property real cx: manip ? liveX : (inst?.x ?? 0.5) * ed.width
            readonly property real cy: manip ? liveY : (inst?.y ?? 0.5) * ed.height
            readonly property real rot: manip ? liveRot : (inst?.rot ?? 0)
            readonly property real sc: manip ? liveScale : (inst?.scale ?? 1)

            function begin() {
                liveX = cx; liveY = cy; liveRot = rot; liveScale = sc
                manip = true
                DesktopWidgets.selected = modelData
                DesktopWidgets.editScreen = ed.screenName
                palette.open = false
            }
            // keep the whole (rotated, scaled) widget on the screen, like the desktop does
            function commit() {
                const b = DeskWidgets.bounds(body.width * liveScale, body.height * liveScale, liveRot)
                const x = DeskWidgets.clamp(liveX, Math.min(b.w / 2, ed.width / 2), Math.max(ed.width - b.w / 2, ed.width / 2))
                const y = DeskWidgets.clamp(liveY, Math.min(b.h / 2, ed.height / 2), Math.max(ed.height - b.h / 2, ed.height / 2))
                DesktopWidgets.update(modelData, { x: DeskWidgets.toRel(x, ed.width), y: DeskWidgets.toRel(y, ed.height),
                                                   rot: liveRot, scale: liveScale })
                manip = false
            }
            function at(item, m) { return item.mapToItem(ed.contentItem, m.x, m.y) }

            Item {
                id: body
                width: frame.implicitWidth
                height: frame.implicitHeight
                x: it.cx - width / 2
                y: it.cy - height / 2
                scale: it.sc
                rotation: it.rot

                WidgetFrame {
                    id: frame
                    anchors.fill: parent
                    inst: it.inst
                    interactive: false
                }
                // outline: dashed look via a soft border; the selected one in the accent color
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -4 / it.sc
                    radius: 24
                    color: "transparent"
                    border.width: (it.selected ? 2 : 1) / it.sc
                    border.color: it.selected ? Colors.color6 : Colors.fade(drag.containsMouse ? 0.6 : 0.3)
                }
                MouseArea {
                    id: drag
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    property point off
                    onPressed: m => { it.begin(); const p = it.at(drag, m); off = Qt.point(p.x - it.cx, p.y - it.cy) }
                    onPositionChanged: m => {
                        if (!pressed) return
                        const p = it.at(drag, m)
                        let x = p.x - off.x, y = p.y - off.y
                        if (m.modifiers & Qt.ControlModifier) { x = DeskWidgets.snap(x); y = DeskWidgets.snap(y) }
                        it.liveX = x; it.liveY = y
                    }
                    onReleased: it.commit()
                    onDoubleClicked: DesktopWidgets.raise(it.modelData)
                }

                // rotate: a knob above the top edge
                Rectangle {
                    visible: it.selected
                    width: 2 / it.sc; height: 26 / it.sc
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.top }
                    color: Colors.color6
                }
                Rectangle {
                    id: rotKnob
                    visible: it.selected
                    width: 22 / it.sc; height: width; radius: width / 2
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.top; bottomMargin: 22 / it.sc }
                    color: Colors.color6
                    Text { anchors.centerIn: parent; text: "󰑓"; color: Colors.background; font.pixelSize: 12 / it.sc; font.family: Properties.fontFamily }
                    MouseArea {
                        id: rotArea
                        anchors.fill: parent
                        anchors.margins: -6 / it.sc
                        cursorShape: Qt.SizeAllCursor
                        onPressed: it.begin()
                        onPositionChanged: m => {
                            if (!pressed) return
                            const p = it.at(rotArea, m)
                            it.liveRot = DeskWidgets.snapAngle(DeskWidgets.angleOf(it.cx, it.cy, p.x, p.y), m.modifiers & Qt.ControlModifier)
                        }
                        onReleased: it.commit()
                    }
                }
                // resize: the bottom-right corner
                Rectangle {
                    visible: it.selected
                    width: 18 / it.sc; height: width; radius: 5 / it.sc
                    x: parent.width - width / 2; y: parent.height - height / 2
                    color: Colors.color6
                    border.width: 2 / it.sc
                    border.color: Colors.background
                    MouseArea {
                        id: scaleArea
                        anchors.fill: parent
                        anchors.margins: -6 / it.sc
                        cursorShape: Qt.SizeFDiagCursor
                        property real d0: 1
                        property real s0: 1
                        onPressed: m => { it.begin(); const p = it.at(scaleArea, m); d0 = Math.max(10, Math.hypot(p.x - it.cx, p.y - it.cy)); s0 = it.sc }
                        onPositionChanged: m => {
                            if (!pressed) return
                            const p = it.at(scaleArea, m)
                            it.liveScale = DeskWidgets.snapScale(s0 * Math.hypot(p.x - it.cx, p.y - it.cy) / d0, m.modifiers & Qt.ControlModifier)
                        }
                        onReleased: it.commit()
                    }
                }
            }

            // live readout while changing
            Rectangle {
                visible: it.manip
                x: it.cx - width / 2
                y: Math.min(ed.height - height - 8, it.cy + body.height * it.sc / 2 + 18)
                width: readout.implicitWidth + 16; height: 24; radius: 12
                color: Properties.panelColor
                Text {
                    id: readout
                    anchors.centerIn: parent
                    text: Math.round(it.liveX) + ", " + Math.round(it.liveY) + "   " + Math.round(it.liveRot) + "°   " + Math.round(it.liveScale * 100) + " %"
                    color: Colors.ink
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                }
            }
        }
    }

    // ── toolbar ─────────────────────────────────────────────────────────────
    Rectangle {
        id: toolbar
        z: 10
        anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 18 }
        width: tbRow.implicitWidth + 20
        height: 48
        radius: 24
        color: Properties.panelColor
        border.width: 1
        border.color: Properties.cardBorder
        MouseArea { anchors.fill: parent }          // not the backdrop
        RowLayout {
            id: tbRow
            anchors.centerIn: parent
            spacing: 10
            Text {
                text: "󰕮  Desktop widgets"
                color: Colors.ink
                font.pixelSize: 13
                font.bold: true
                font.family: Properties.fontFamily
            }
            ActionButton {
                icon: "󰐕"
                text: "Add"
                primary: true
                onClicked: palette.open = !palette.open
            }
            ActionButton {
                icon: "󰍹"
                text: "Monitors"
                onClicked: monitorsPop.open = !monitorsPop.open
            }
            Text {
                visible: ed.width >= 1400
                text: "drag · Ctrl snaps · double-click: to front · Del · Ctrl+D"
                color: Colors.fade(0.5)
                font.pixelSize: 11
                font.family: Properties.fontFamily
            }
            ActionButton {
                icon: "󰄬"
                text: "Done"
                onClicked: DesktopWidgets.stopEdit()
            }
        }
    }

    // ── "all widgets on" monitors ───────────────────────────────────────────
    Rectangle {
        id: monitorsPop
        z: 10
        property bool open: false
        visible: open
        anchors { top: toolbar.bottom; horizontalCenter: toolbar.horizontalCenter; topMargin: 8 }
        width: Math.min(560, ed.width - 40)
        height: monCol.implicitHeight + 28
        radius: 18
        color: Properties.panelColor
        border.width: 1
        border.color: Properties.cardBorder
        MouseArea { anchors.fill: parent }
        ColumnLayout {
            id: monCol
            anchors { fill: parent; margins: 14 }
            spacing: 8
            Text { text: "Show all widgets on"; color: Colors.ink; font.pixelSize: 13; font.bold: true; font.family: Properties.fontFamily }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: "A widget can choose its own monitors in its options. \"All monitors\" puts each widget on every monitor at the same place."
                color: Colors.fade(0.55); font.pixelSize: 11; font.family: Properties.fontFamily
            }
            MonitorChips {
                Layout.fillWidth: true
                value: DesktopWidgets.monitors
                onEdited: v => DesktopWidgets.setMonitors(v ?? [])
            }
        }
    }

    // ── palette: add a widget ───────────────────────────────────────────────
    Rectangle {
        id: palette
        z: 10
        property bool open: false
        visible: open
        anchors { top: toolbar.bottom; horizontalCenter: toolbar.horizontalCenter; topMargin: 8 }
        width: Math.min(640, ed.width - 40)
        height: palGrid.implicitHeight + 24
        radius: 18
        color: Properties.panelColor
        border.width: 1
        border.color: Properties.cardBorder
        MouseArea { anchors.fill: parent }
        GridLayout {
            id: palGrid
            anchors { fill: parent; margins: 12 }
            columns: 3
            rowSpacing: 8
            columnSpacing: 8
            Repeater {
                model: DesktopWidgets.types
                Rectangle {
                    id: tcell
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 58
                    radius: 12
                    color: tmouse.containsMouse ? Colors.fade(0.1) : Colors.fade(0.04)
                    RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 10 }
                        spacing: 10
                        Text { text: tcell.modelData.icon; color: Colors.color6; font.pixelSize: 20; font.family: Properties.fontFamily }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text { text: tcell.modelData.name; color: Colors.ink; font.pixelSize: 12; font.bold: true; font.family: Properties.fontFamily }
                            Text { Layout.fillWidth: true; text: tcell.modelData.desc; color: Colors.fade(0.5); font.pixelSize: 10; elide: Text.ElideRight; font.family: Properties.fontFamily }
                        }
                    }
                    MouseArea {
                        id: tmouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            palette.open = false
                            DesktopWidgets.editScreen = ed.screenName
                            DesktopWidgets.add(tcell.modelData.type, 0.5, 0.45, ed.screenName)
                        }
                    }
                }
            }
        }
    }

    // ── options of the selected widget ──────────────────────────────────────
    Rectangle {
        id: panel
        z: 10
        visible: ed.selHere
        // on the side away from the selected widget
        readonly property bool leftSide: (ed.sel?.x ?? 0) > 0.5
        x: leftSide ? 18 : ed.width - width - 18
        anchors.verticalCenter: parent.verticalCenter
        width: 400
        height: Math.min(ed.height - 120, panelCol.implicitHeight + 28)
        radius: 20
        color: Properties.panelColor
        border.width: 1
        border.color: Properties.cardBorder
        MouseArea { anchors.fill: parent; onPressed: DesktopWidgets.editScreen = ed.screenName }
        Flickable {
            anchors { fill: parent; margins: 14 }
            contentHeight: panelCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            ColumnLayout {
                id: panelCol
                width: parent.width
                spacing: 10
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: DesktopWidgets.typeInfo(ed.sel?.type ?? "").icon; color: Colors.color6; font.pixelSize: 18; font.family: Properties.fontFamily }
                    Text {
                        Layout.fillWidth: true
                        text: DesktopWidgets.typeInfo(ed.sel?.type ?? "").name + "  ·  " + (ed.sel?.id ?? "")
                        color: Colors.ink; font.pixelSize: 13; font.bold: true; font.family: Properties.fontFamily
                    }
                    IconButton { icon: "󰑓"; tooltip: "Reset rotation and size (R)"; onClicked: DesktopWidgets.update(ed.sel.id, { rot: 0, scale: 1 }) }
                    IconButton { icon: "󰆏"; tooltip: "Duplicate (Ctrl+D)"; onClicked: DesktopWidgets.duplicate(ed.sel.id) }
                    IconButton { icon: "󰆴"; tooltip: "Remove (Delete)"; onClicked: DesktopWidgets.remove(ed.sel.id) }
                }
                Text { text: "Monitors"; color: Colors.fade(0.6); font.pixelSize: 11; font.family: Properties.fontFamily }
                MonitorChips {
                    Layout.fillWidth: true
                    allowInherit: true
                    value: ed.sel?.monitors ?? null
                    onEdited: v => DesktopWidgets.update(ed.sel.id, { monitors: v })
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: opts.implicitHeight
                    radius: 14
                    color: Colors.card
                    border.width: 1
                    border.color: Properties.cardBorder
                    WidgetOptions {
                        id: opts
                        width: parent.width
                        instId: ed.sel?.id ?? ""
                        onChoosingFile: on => DesktopWidgets.fileDialog = on
                    }
                }
            }
        }
    }
}
