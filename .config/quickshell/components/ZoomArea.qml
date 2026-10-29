import QtQuick
import qs.services

// An app window's content, drawn bigger or smaller (AppZoom): Ctrl + / Ctrl −
// / Ctrl 0 and Ctrl + wheel anywhere in it; a little pill shows the percent.
//   FloatingWindow { ZoomArea { app: "mail"; anchors.fill: parent; …content… } }
// The content lays out in a smaller (or bigger) area and is scaled up to the
// window, so everything — text, icons, spacing — grows together. Popups sit
// above the window, outside of this: they take AppZoom.at(parent) as scale.
Item {
    id: root

    required property string app
    readonly property string zoomApp: app
    readonly property real zoom: AppZoom.of(app)
    // where Ctrl + wheel is someone else's (the calendar's hour grid zooms itself)
    property var wheelExcept: []
    default property alias content: inner.data

    Item {
        id: inner
        width: root.width / root.zoom
        height: root.height / root.zoom
        scale: root.zoom
        transformOrigin: Item.TopLeft

        // Ctrl + wheel: above everything, lets every other wheel through
        MouseArea {
            z: 1000000
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            property real acc: 0
            onWheel: wheel => {
                if (!(wheel.modifiers & Qt.ControlModifier)) { wheel.accepted = false; return }
                for (const it of root.wheelExcept) {
                    if (!it || !it.visible) continue
                    const p = mapToItem(it, wheel.x, wheel.y)
                    if (p.x >= 0 && p.y >= 0 && p.x < it.width && p.y < it.height) { wheel.accepted = false; return }
                }
                acc += wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.pixelDelta.y * 4
                if (Math.abs(acc) >= 120) { root.step(acc > 0 ? 1 : -1); acc = 0 }
            }
        }
    }

    function step(dir) {
        if (dir === 0) AppZoom.reset(app)
        else AppZoom.by(app, dir)
        pill.show()
    }

    // + needs Shift on some layouts (Swiss: Shift 1), = is the US key. Where Qt also
    // matches Ctrl++ for Ctrl+Shift++ it calls that ambiguous: same thing here
    Shortcut {
        sequences: ["Ctrl++", "Ctrl+=", "Ctrl+Shift++", "Ctrl+Shift+="]
        onActivated: root.step(1)
        onActivatedAmbiguously: root.step(1)
    }
    Shortcut { sequences: ["Ctrl+-"]; onActivated: root.step(-1) }
    Shortcut { sequences: ["Ctrl+0"]; onActivated: root.step(0) }

    // the percent, for a moment after a change (not zoomed itself)
    Rectangle {
        id: pill
        function show() { opacity = 1; hideTimer.restart() }
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        z: 1000001
        width: pillRow.implicitWidth + 28
        height: 34
        radius: 17
        color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.95)
        border.width: Properties.panelBorderWidth
        border.color: Properties.panelBorder
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Timer { id: hideTimer; interval: 1400; onTriggered: pill.opacity = 0 }
        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 8
            Text { text: "󰍉"; color: Colors.color6; font.pixelSize: 15; font.family: Properties.fontFamily; anchors.verticalCenter: parent.verticalCenter }
            Text { text: AppZoom.percent(root.app) + "%"; color: Colors.ink; font.pixelSize: 13; font.bold: true; font.family: Properties.fontFamily; anchors.verticalCenter: parent.verticalCenter }
            Text {
                visible: AppZoom.percent(root.app) !== 100
                text: "Ctrl 0 resets"
                color: Colors.fade(0.45); font.pixelSize: 11; font.family: Properties.fontFamily
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
