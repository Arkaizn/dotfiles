import Quickshell
import Quickshell.Networking
import QtQuick
import qs.components
import qs.services

// One button of the control center (PanelLayout.items): a small icon button in
// the clock card (`compact`), a tile everywhere else. `host` is the control
// center (state, close / runCapture / runTool, the two-click confirm, live editing).
// While the buttons are edited live it wiggles, − hides it, dragging moves it.
Item {
    id: root
    required property string itemId
    property var host: null
    property bool compact: false

    readonly property bool ccItem: true          // found by the control center's drop logic
    readonly property var info: PanelLayout.item(itemId)
    readonly property bool editing: host?.editButtons ?? false
    readonly property bool dragged: host?.dragId === itemId
    readonly property bool armed: host?.armed === itemId

    implicitWidth: compact ? Properties.buttonHeight : 120
    implicitHeight: compact ? Properties.buttonHeight : 56
    rotation: editing && !dragged ? EditMode.wiggle(EditMode.seed(itemId), compact ? 3 : 1.2) : 0
    opacity: dragged ? 0.3 : 1

    // ── what it shows ──
    readonly property var bt: host?.btAdapter ?? null
    readonly property string icon: {
        switch (itemId) {
        case "wifi": return !Networking.wifiEnabled ? "󰤮" : host?.wifiNetwork ? "󰤨" : host?.wiredDevice?.connected ? "󰈀" : "󰤯"
        case "bluetooth": return !bt?.enabled ? Icons.get("btOff") : host.btConnected.length === 1 ? BluetoothPower.iconFor(host.btConnected[0])
                              : host.btConnected.length > 0 ? Icons.get("btConnected") : Icons.get("btOn")
        case "dnd": return Notifs.dnd ? "󰂛" : "󰂚"
        case "powerprofile": return Power.icons[Power.current] ?? info.icon
        case "record": return Capture.recording ? "󰓛" : info.icon
        }
        return info.icon
    }
    readonly property string title: itemId === "record" && Capture.recording ? "Stop" : info.name
    readonly property string subtitle: {
        if (armed) return "Click again"
        switch (itemId) {
        case "wifi": return !host?.wifiDevice ? (host?.wiredDevice?.connected ? "Ethernet" : "No Wi-Fi device")
                          : !Networking.wifiEnabled ? (host.wiredDevice?.connected ? "Off · Ethernet" : "Off")
                          : host.wifiNetwork ? host.wifiNetwork.name
                          : host.wiredDevice?.connected ? "Ethernet" : "Not connected"
        case "bluetooth": return !bt ? "No adapter" : !bt.enabled ? "Off"
                               : host.btConnected.length === 1 ? host.btConnected[0].name
                               : host.btConnected.length > 1 ? host.btConnected.length + " devices" : "On"
        case "dnd": return Notifs.dnd ? (Notifs.dndScheduled && !Notifs.dndManual ? "On (schedule)" : "On") : "Off"
        case "powerprofile": return Power.current
        case "record": return Capture.recording ? Math.floor(Capture.elapsed / 60) + ":" + String(Capture.elapsed % 60).padStart(2, "0") : info.desc
        }
        return info.desc
    }
    readonly property bool active: itemId === "wifi" ? Networking.wifiEnabled && host?.wifiDevice !== null
                                 : itemId === "bluetooth" ? (bt?.enabled ?? false)
                                 : itemId === "dnd" ? Notifs.dnd
                                 : itemId === "record" ? Capture.recording
                                 : armed
    // Wi-Fi / Bluetooth tiles open their list (in the card they're in)
    readonly property bool expandable: !compact && (itemId === "wifi" ? host?.wifiDevice !== null
                                                  : itemId === "bluetooth" ? bt !== null : false)
    readonly property bool danger: armed || itemId === "poweroff"

    // ── what it does ──
    function ipc(args) { host?.close(); Quickshell.execDetached(["qs", "ipc", "call"].concat(args)) }
    function activate() {
        if (info.confirm && !host?.confirm(itemId)) return
        switch (itemId) {
        case "wifi": Networking.wifiEnabled = !Networking.wifiEnabled; break
        case "bluetooth": BluetoothPower.toggle(); break
        case "dnd": Notifs.setDnd(!Notifs.dndManual); break
        case "powerprofile": Power.cycle(); break
        case "screenshot": host?.runCapture(() => Capture.screenshot("region")); break
        case "screenfull": host?.runCapture(() => Capture.screenshot("screen")); break
        case "ocr": host?.runCapture(() => Capture.ocr()); break
        case "record": Capture.recording ? Capture.stop() : host?.runCapture(() => Capture.record("screen")); break
        case "color": host?.runTool("c=$(hyprpicker -a -f hex) && [ -n \"$c\" ]"
                                    + " && notify-send -a 'Control center' 'Color picker' \"$c copied to clipboard\""); break
        case "capture": host?.close(); Capture.menuOpen = true; break
        case "launcher": ipc(["Launcher", "toggleAppSearch"]); break
        case "clipboard": ipc(["Launcher", "toggleClipboard"]); break
        case "wallpapers": ipc(["Launcher", "toggleWallpapers"]); break
        case "connections": ipc(["Launcher", "toggleConnections"]); break
        case "dashboard": ipc(["dashboard", "open"]); break
        case "calendar": ipc(["calendar", "open"]); break
        case "perfmon": ipc(["perfmon", "toggle"]); break
        case "keybinds": ipc(["Launcher", "toggleKeybinds"]); break
        case "settings": ipc(["settings", "open"]); break
        case "lock": host?.runTool("bash ~/.config/quickshell/scripts/lock.sh"); break
        case "suspend": host?.runTool("systemctl suspend || loginctl suspend"); break
        case "logout": host?.runTool(Compositor.quitCommand); break
        case "reboot": host?.runTool("systemctl reboot || loginctl reboot"); break
        case "poweroff": host?.runTool("systemctl poweroff || loginctl poweroff"); break
        }
    }

    Loader {
        anchors.fill: parent
        enabled: !root.editing
        sourceComponent: root.compact ? smallButton : tile
    }

    Component {
        id: smallButton
        IconButton {
            icon: root.icon
            tooltip: root.armed ? "Click again to " + root.info.name.toLowerCase() : root.info.name
            active: root.active
            textColor: root.danger ? Colors.red : Properties.color
            onClicked: root.activate()
        }
    }
    Component {
        id: tile
        QuickTile {
            icon: root.icon
            title: root.title
            subtitle: root.subtitle
            active: root.active
            expandable: root.expandable
            expanded: root.host?.expanded === root.itemId
            onToggled: root.activate()
            onExpandClicked: root.host.expanded = expanded ? "" : root.itemId
        }
    }

    // ── live editing (the buttons) ──
    MouseArea {
        anchors.fill: parent
        visible: root.editing
        hoverEnabled: true
        preventStealing: true
        cursorShape: root.dragged ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property point press: Qt.point(0, 0)
        onPressed: m => press = Qt.point(m.x, m.y)
        onPositionChanged: m => {
            if (!pressed) return
            if (root.host.dragId === "" && Math.hypot(m.x - press.x, m.y - press.y) > 4)
                root.host.beginDrag("item", root.itemId, root, press.x, press.y)
            if (root.dragged) root.host.track(mapToItem(root.host.overlay, m.x, m.y))
        }
        onReleased: root.host.endDrag()
        onCanceled: root.host.cancelDrag()
    }
    EditBadge {
        x: root.compact ? -5 : -6
        y: root.compact ? -5 : -6
        visible: root.editing && root.host.dragId === ""
        onClicked: PanelLayout.ccRemoveItem(root.itemId)
    }
}
