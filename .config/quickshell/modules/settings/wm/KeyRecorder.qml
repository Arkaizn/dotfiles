import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."

// Button that records the next key combo pressed (Esc cancels).
// Emits keys in niri spelling: ["Mod", "Shift", "Y"].
// While recording, the window asks the compositor to pass all shortcuts to it
// (keyboard-shortcuts-inhibit), so combos niri / Hyprland already use are
// recorded instead of run. (Binds marked allow-inhibiting=false in niri still
// run — e.g. an escape hatch.)
Item {
    id: root
    property bool recording: false
    signal recorded(var keys)

    implicitWidth: btn.implicitWidth + 26
    implicitHeight: Properties.buttonHeight

    // Qt key → XKB name (what niri / Hyprland expect)
    readonly property var names: {
        const m = {}
        m[Qt.Key_Return] = "Return"; m[Qt.Key_Enter] = "Return"; m[Qt.Key_Tab] = "Tab"; m[Qt.Key_Backtab] = "Tab"
        m[Qt.Key_Space] = "space"; m[Qt.Key_Backspace] = "BackSpace"; m[Qt.Key_Delete] = "Delete"; m[Qt.Key_Insert] = "Insert"
        m[Qt.Key_Home] = "Home"; m[Qt.Key_End] = "End"; m[Qt.Key_PageUp] = "Page_Up"; m[Qt.Key_PageDown] = "Page_Down"
        m[Qt.Key_Left] = "Left"; m[Qt.Key_Right] = "Right"; m[Qt.Key_Up] = "Up"; m[Qt.Key_Down] = "Down"
        m[Qt.Key_Print] = "Print"; m[Qt.Key_Comma] = "comma"; m[Qt.Key_Period] = "period"; m[Qt.Key_Slash] = "slash"
        m[Qt.Key_Minus] = "minus"; m[Qt.Key_Equal] = "equal"; m[Qt.Key_Plus] = "plus"; m[Qt.Key_Semicolon] = "semicolon"
        m[Qt.Key_Apostrophe] = "apostrophe"; m[Qt.Key_BracketLeft] = "bracketleft"; m[Qt.Key_BracketRight] = "bracketright"
        m[Qt.Key_Backslash] = "backslash"; m[Qt.Key_QuoteLeft] = "grave"; m[Qt.Key_section] = "section"
        m[Qt.Key_VolumeUp] = "XF86AudioRaiseVolume"; m[Qt.Key_VolumeDown] = "XF86AudioLowerVolume"; m[Qt.Key_VolumeMute] = "XF86AudioMute"
        m[Qt.Key_MediaPlay] = "XF86AudioPlay"; m[Qt.Key_MediaNext] = "XF86AudioNext"; m[Qt.Key_MediaPrevious] = "XF86AudioPrev"
        return m
    }

    function keyName(e) {
        if (names[e.key]) return names[e.key]
        if (e.key >= Qt.Key_F1 && e.key <= Qt.Key_F24) return "F" + (e.key - Qt.Key_F1 + 1)
        if (e.key >= Qt.Key_A && e.key <= Qt.Key_Z) return String.fromCharCode(e.key)
        if (e.key >= Qt.Key_0 && e.key <= Qt.Key_9) return String.fromCharCode(e.key)
        return e.text && e.text.trim() !== "" ? e.text.toUpperCase() : ""
    }

    function start() { recording = true; catcher.forceActiveFocus() }

    // compositor shortcuts off while recording
    ShortcutInhibitor {
        window: root.QsWindow.window
        enabled: root.recording
        onCancelled: root.recording = false
    }

    Item {
        id: catcher
        focus: root.recording
        Keys.onPressed: e => {
            if (!root.recording) return
            e.accepted = true
            if ([Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_Control, Qt.Key_Shift, Qt.Key_Alt, Qt.Key_AltGr].includes(e.key)) return
            if (e.key === Qt.Key_Escape && e.modifiers === Qt.NoModifier) { root.recording = false; return }
            const k = root.keyName(e)
            if (k === "") return
            const keys = []
            if (e.modifiers & Qt.MetaModifier) keys.push("Mod")
            if (e.modifiers & Qt.ControlModifier) keys.push("Ctrl")
            if (e.modifiers & Qt.AltModifier) keys.push("Alt")
            if (e.modifiers & Qt.ShiftModifier) keys.push("Shift")
            keys.push(k)
            root.recording = false
            root.recorded(keys)
        }
        onActiveFocusChanged: if (!activeFocus) root.recording = false
    }

    ActionButton {
        id: btn
        anchors.fill: parent
        icon: root.recording ? "󰑊" : "󰌌"
        text: root.recording ? "Press keys…  (Esc)" : "Record keys"
        primary: root.recording
        onClicked: root.recording ? root.recording = false : root.start()
    }
    // pulse while waiting
    SequentialAnimation on opacity {
        running: root.recording
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { to: 0.6; duration: 500; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutSine }
    }
}
