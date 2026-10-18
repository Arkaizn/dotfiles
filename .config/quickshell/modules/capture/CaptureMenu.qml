import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "../settings"
import "../settings/network"

// Screenshot / recording menu (services/Capture.qml), on the focused monitor.
// Keys: 1 region · 2 screen · 3 window · 4 record region · 5 record screen ·
// Esc closes. `qs ipc call capture menu` toggles it.
PanelWindow {
    id: win
    visible: false
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-capture"

    property string after: Settings.capture.after ?? "save"
    property string delay: Settings.capture.delay ?? "0"
    property string audio: Settings.capture.audio ?? "none"

    Connections {
        target: Capture
        function onMenuOpenChanged() {
            if (Capture.menuOpen) {
                win.after = Settings.capture.after ?? "save"
                win.delay = Settings.capture.delay ?? "0"
                win.audio = Settings.capture.audio ?? "none"
                Capture.focusedOutput(name => {
                    const s = Quickshell.screens.find(x => x.name === name)
                    if (s) win.screen = s
                    win.visible = true
                    card.forceActiveFocus()
                })
            } else win.visible = false
        }
    }

    BackgroundEffect.blurRegion: Region { item: card; radius: Properties.panelRadius }

    function shot(what) { Capture.screenshot(what, after, delay) }
    function rec(what) { Capture.record(what, audio) }

    // dim + click outside closes
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.35)
        opacity: win.visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        MouseArea { anchors.fill: parent; onClicked: Capture.menuOpen = false }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 560
        height: col.implicitHeight + 40
        radius: Properties.panelRadius
        color: Properties.panelColor
        border.width: Properties.panelBorderWidth
        border.color: Properties.panelBorder
        focus: true
        MouseArea { anchors.fill: parent }    // clicks on the card don't close it

        Keys.onEscapePressed: Capture.menuOpen = false
        Keys.onPressed: e => {
            const k = { [Qt.Key_1]: () => win.shot("region"), [Qt.Key_2]: () => win.shot("screen"), [Qt.Key_3]: () => win.shot("window"),
                        [Qt.Key_4]: () => win.rec("region"), [Qt.Key_5]: () => win.rec("screen") }[e.key]
            if (k) { k(); e.accepted = true }
        }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "Capture"
                    color: Colors.ink
                    font.pixelSize: 18
                    font.bold: true
                    font.family: Properties.fontFamily
                }
                IconButton {
                    icon: "󰒓"
                    tooltip: "Options"
                    onClicked: { Capture.menuOpen = false; Quickshell.execDetached(["qs", "ipc", "call", "settings", "openPage", "capture"]) }
                }
                IconButton { icon: "󰅖"; tooltip: "Close (Esc)"; onClicked: Capture.menuOpen = false }
            }

            // ── Screenshot ──────────────────────────────────────────────────
            Text { text: "Screenshot"; color: Colors.fade(0.55); font.pixelSize: 12; font.bold: true; font.family: Properties.fontFamily }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                CaptureButton { icon: "󰩭"; text: "Region"; key: "1"; onClicked: win.shot("region") }
                CaptureButton { icon: "󰍹"; text: "Screen"; key: "2"; onClicked: win.shot("screen") }
                CaptureButton { icon: "󰖯"; text: "Window"; key: "3"; onClicked: win.shot("window") }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: "Then"; color: Colors.fade(0.6); font.pixelSize: 12; font.family: Properties.fontFamily }
                Segmented {
                    small: true
                    options: [{ label: "Save & copy", value: "save" }, { label: "Copy", value: "copy" }, { label: "Edit", value: "edit" }]
                    value: win.after
                    onEdited: v => win.after = v
                }
                Item { Layout.fillWidth: true }
                Text { text: "Delay"; color: Colors.fade(0.6); font.pixelSize: 12; font.family: Properties.fontFamily }
                Segmented {
                    small: true
                    options: [{ label: "0", value: "0" }, { label: "3s", value: "3" }, { label: "5s", value: "5" }, { label: "10s", value: "10" }]
                    value: win.delay
                    onEdited: v => win.delay = v
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Colors.fade(0.08) }

            // ── Recording ───────────────────────────────────────────────────
            Text { text: "Record"; color: Colors.fade(0.55); font.pixelSize: 12; font.bold: true; font.family: Properties.fontFamily }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                visible: !Capture.recording
                CaptureButton { icon: "󰑋"; text: "Region"; key: "4"; onClicked: win.rec("region") }
                CaptureButton { icon: "󰕧"; text: "Screen"; key: "5"; onClicked: win.rec("screen") }
            }
            CaptureButton {
                Layout.fillWidth: true
                visible: Capture.recording
                danger: true
                icon: "󰓛"
                text: "Stop recording  " + Math.floor(Capture.elapsed / 60) + ":" + String(Capture.elapsed % 60).padStart(2, "0")
                onClicked: { Capture.stop(); Capture.menuOpen = false }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                visible: !Capture.recording
                Text { text: "Sound"; color: Colors.fade(0.6); font.pixelSize: 12; font.family: Properties.fontFamily }
                Segmented {
                    small: true
                    options: [{ label: "None", value: "none" }, { label: "Desktop", value: "desktop" }, { label: "Microphone", value: "mic" }]
                    value: win.audio
                    onEdited: v => win.audio = v
                }
                Item { Layout.fillWidth: true }
            }

            Text {
                Layout.fillWidth: true
                text: "Screenshots → " + Capture.shotDir.replace(Capture.home, "~") + "   ·   Videos → " + Capture.videoDir.replace(Capture.home, "~")
                color: Colors.fade(0.35)
                font.pixelSize: 11
                font.family: Properties.fontFamily
                elide: Text.ElideMiddle
            }
        }
    }
}
