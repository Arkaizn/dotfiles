import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "../settings"
import "../settings/network"

// Screenshot / recording menu (services/Capture.qml), on the focused monitor.
// Keys: 1 region · 2 screen · 3 window (click it) · 4 text (OCR) ·
// 5 record a window · 6 record a screen · Esc closes. With several monitors,
// "Screen" first shows them as laid out: click one, or "All screens" (keys too). `qs ipc call capture menu` toggles it.
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
    property string audio: Settings.capture.audio ?? "both"

    // Panels.toggle("capture") / open / close; the state stays Capture.menuOpen
    // (the capture service closes the menu itself when it starts a capture)
    readonly property var api: ({
        toggle: () => Capture.menuOpen = !Capture.menuOpen,
        open: () => Capture.menuOpen = true,
        close: () => Capture.menuOpen = false
    })
    Component.onCompleted: Panels.register("capture", api)
    Component.onDestruction: Panels.unregister("capture", api)

    // its monitor unplugged while open (undocking): closed for real, so the next
    // shortcut opens it again instead of only "closing" a menu that's gone
    Connections {
        target: Quickshell
        function onScreensChanged() { if (Capture.menuOpen && !Quickshell.screens.includes(win.screen)) Capture.menuOpen = false }
    }

    Connections {
        target: Capture
        function onMenuOpenChanged() {
            if (Capture.menuOpen) {
                win.after = Settings.capture.after ?? "save"
                win.delay = Settings.capture.delay ?? "0"
                win.audio = Settings.capture.audio ?? "both"
                win.screenFor = ""
                Compositor.focusedOutput(name => {
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

    // "Screen": with several monitors, pick one (or all) first
    property string screenFor: ""          // "" | "shot" | "rec": the monitor picker is showing
    function chooseScreen(kind) {
        if (Quickshell.screens.length < 2) pickScreen(kind, "")
        else screenFor = kind
    }
    function pickScreen(kind, name) {
        screenFor = ""
        if (kind === "shot") Capture.screenshot("screen", after, delay, name)
        else Capture.record("screen", audio, name)
    }

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
        height: (win.screenFor ? picker.implicitHeight : col.implicitHeight) + 40
        clip: true
        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        radius: Properties.panelRadius
        color: Properties.panelColor
        border.width: Properties.panelBorderWidth
        border.color: Properties.panelBorder
        focus: true
        MouseArea { anchors.fill: parent }    // clicks on the card don't close it

        Keys.onEscapePressed: if (win.screenFor) win.screenFor = ""; else Capture.menuOpen = false
        Keys.onPressed: e => {
            const n = e.key - Qt.Key_1      // 0 for "1"
            if (win.screenFor) {
                const scr = Quickshell.screens
                if (n >= 0 && n < scr.length) win.pickScreen(win.screenFor, scr[n].name)
                else if (n === scr.length) win.pickScreen(win.screenFor, "all")
                else return
                e.accepted = true
                return
            }
            const k = [() => win.shot("region"), () => win.chooseScreen("shot"), () => win.shot("window"),
                       () => Capture.ocr(), () => win.rec("window"), () => win.chooseScreen("rec")][n]
            if (k) { k(); e.accepted = true }
        }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: 14
            opacity: win.screenFor ? 0 : 1
            visible: opacity > 0
            enabled: !win.screenFor
            transform: Translate { x: win.screenFor ? -40 : 0; Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } } }
            Behavior on opacity { NumberAnimation { duration: 160 } }

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
                    onClicked: { Capture.menuOpen = false; Panels.call("settings", "openPage", "capture") }
                }
                IconButton { icon: "󰅖"; tooltip: "Close (Esc)"; onClicked: Capture.menuOpen = false }
            }

            // ── Screenshot ──────────────────────────────────────────────────
            Text { text: "Screenshot"; color: Colors.fade(0.55); font.pixelSize: 12; font.bold: true; font.family: Properties.fontFamily }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                CaptureButton { icon: "󰩭"; text: "Region"; key: "1"; onClicked: win.shot("region") }
                CaptureButton { icon: "󰍹"; text: "Screen"; key: "2"; onClicked: win.chooseScreen("shot") }
                CaptureButton { icon: "󰖯"; text: "Window"; key: "3"; onClicked: win.shot("window") }
                CaptureButton { icon: "󰊄"; text: "Text (OCR)"; key: "4"; onClicked: Capture.ocr() }
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
                CaptureButton { icon: "󰖯"; text: "Window"; key: "5"; onClicked: win.rec("window") }
                CaptureButton { icon: "󰕧"; text: "Screen"; key: "6"; onClicked: win.chooseScreen("rec") }
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
                    options: [{ label: "Desktop + mic", value: "both" }, { label: "Desktop", value: "desktop" }, { label: "Microphone", value: "mic" }, { label: "None", value: "none" }]
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

        // ── Monitor picker (Screen with several monitors) ──────────────────
        ColumnLayout {
            id: picker
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: 14
            opacity: win.screenFor ? 1 : 0
            visible: opacity > 0
            enabled: !!win.screenFor
            transform: Translate { x: win.screenFor ? 0 : 40; Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } } }
            Behavior on opacity { NumberAnimation { duration: 160 } }

            RowLayout {
                Layout.fillWidth: true
                IconButton { icon: "󰁍"; tooltip: "Back (Esc)"; onClicked: win.screenFor = "" }
                Text {
                    Layout.fillWidth: true
                    text: win.screenFor === "rec" ? "Record which screen?" : "Screenshot of which screen?"
                    color: Colors.ink
                    font.pixelSize: 16
                    font.bold: true
                    font.family: Properties.fontFamily
                }
            }

            // the monitors as they're laid out, scaled to fit
            Item {
                id: layoutView
                Layout.fillWidth: true
                Layout.preferredHeight: 190
                readonly property var scr: Quickshell.screens
                readonly property real minX: Math.min(...scr.map(s => s.x))
                readonly property real minY: Math.min(...scr.map(s => s.y))
                readonly property real spanW: Math.max(...scr.map(s => s.x + s.width)) - minX
                readonly property real spanH: Math.max(...scr.map(s => s.y + s.height)) - minY
                readonly property real k: Math.min((width - 8 * (scr.length - 1)) / spanW, height / spanH)
                readonly property real offX: (width - spanW * k - 8 * (scr.length - 1)) / 2
                readonly property real offY: (height - spanH * k) / 2

                Repeater {
                    model: layoutView.scr
                    Rectangle {
                        id: mon
                        required property var modelData
                        required property int index
                        // monitors further right get a small gap, so they read as separate
                        x: layoutView.offX + (modelData.x - layoutView.minX) * layoutView.k + 8 * layoutView.scr.filter(s => s.x < mon.modelData.x).length
                        y: layoutView.offY + (modelData.y - layoutView.minY) * layoutView.k
                        width: modelData.width * layoutView.k
                        height: modelData.height * layoutView.k
                        radius: 10
                        readonly property color tint: win.screenFor === "rec" ? Colors.red : Colors.color6
                        color: monMouse.containsMouse ? Qt.rgba(tint.r, tint.g, tint.b, 0.2) : Colors.fade(0.05)
                        border.width: 1.5
                        border.color: monMouse.containsMouse ? Qt.rgba(tint.r, tint.g, tint.b, 0.7) : Colors.fade(0.14)
                        scale: monMouse.pressed ? 0.96 : monMouse.containsMouse ? 1.03 : 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                        MouseArea {
                            id: monMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.pickScreen(win.screenFor, mon.modelData.name)
                        }
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "󰍹"
                                color: monMouse.containsMouse ? mon.tint : Colors.fade(0.6)
                                font.pixelSize: 22
                                font.family: Properties.fontFamily
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: mon.modelData.name
                                color: Colors.ink
                                font.pixelSize: 12
                                font.bold: true
                                font.family: Properties.fontFamily
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: mon.modelData.width + "×" + mon.modelData.height
                                color: Colors.fade(0.5)
                                font.pixelSize: 10
                                font.family: Properties.fontFamily
                            }
                        }
                        Text {
                            anchors { top: parent.top; right: parent.right; margins: 7 }
                            text: mon.index + 1
                            color: Colors.fade(0.35)
                            font.pixelSize: 10
                            font.family: Properties.fontFamily
                        }
                    }
                }
            }

            CaptureButton {
                Layout.fillWidth: true
                implicitHeight: 52
                danger: win.screenFor === "rec"
                icon: "󰍺"
                text: "All screens" + (win.screenFor === "rec" ? "  ·  merged into one video" : "")
                key: String(Quickshell.screens.length + 1)
                onClicked: win.pickScreen(win.screenFor, "all")
            }
        }

    }
}
