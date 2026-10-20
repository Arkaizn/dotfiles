import Quickshell
import Quickshell.Networking
import QtQuick
import qs.components
import qs.services

// One button of the control center (PanelLayout.items): a small icon button in
// the clock card (`compact`), a tile everywhere else. `host` is the control
// center (state, close / runClosed / runTool, the two-click confirm, live editing).
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
        case "vpn": return Vpn.upNames.length > 0 ? Vpn.upNames.join(", ") : Vpn.available ? "Off" : "None found"
        }
        return info.desc
    }
    readonly property bool active: itemId === "wifi" ? Networking.wifiEnabled && host?.wifiDevice !== null
                                 : itemId === "bluetooth" ? (bt?.enabled ?? false)
                                 : itemId === "dnd" ? Notifs.dnd
                                 : itemId === "record" ? Capture.recording
                                 : itemId === "vpn" ? Vpn.upNames.length > 0
                                 : armed
    // Wi-Fi / Bluetooth tiles open their list (in the card they're in)
    readonly property bool expandable: !compact && (itemId === "vpn" ? true : itemId === "wifi" ? host?.wifiDevice !== null
                                                  : itemId === "bluetooth" ? bt !== null : false)
    readonly property bool danger: armed || itemId === "poweroff"

    // the VPN tile reads the VPNs while the control center is open
    readonly property bool vpnWatch: itemId === "vpn" && (host?.shown ?? false)
    property bool vpnWatching: false
    onVpnWatchChanged: { if (vpnWatch !== vpnWatching) { Vpn.watchers += vpnWatch ? 1 : -1; vpnWatching = vpnWatch } }
    Component.onDestruction: if (vpnWatching) Vpn.watchers -= 1

    // ── what it does ──
    // another surface (Panels), with the control center out of the way
    function show(name, fn) { host?.close(); Panels.call(name, fn) }
    function activate() {
        if (info.confirm && !host?.confirm(itemId)) return
        switch (itemId) {
        case "wifi": Networking.wifiEnabled = !Networking.wifiEnabled; break
        case "bluetooth": BluetoothPower.toggle(); break
        case "dnd": Notifs.setDnd(!Notifs.dndManual); break
        case "powerprofile": Power.cycle(); break
        case "screenshot": host?.runClosed(() => Capture.screenshot("region")); break
        case "screenfull": host?.runClosed(() => Capture.screenshot("screen")); break
        case "ocr": host?.runClosed(() => Capture.ocr()); break
        case "record": Capture.recording ? Capture.stop() : host?.runClosed(() => Capture.record("screen")); break
        case "color": host?.runTool("c=$(hyprpicker -a -f hex) && [ -n \"$c\" ]"
                                    + " && notify-send -a 'Control center' 'Color picker' \"$c copied to clipboard\""); break
        case "capture": show("capture", "open"); break
        case "launcher": show("launcher", "toggle"); break
        case "clipboard": show("clipboard", "toggle"); break
        case "wallpapers": show("wallpapers", "toggle"); break
        case "connections": show("connections", "toggle"); break
        case "dashboard": show("dashboard", "open"); break
        case "calendar": show("calendar", "open"); break
        case "perfmon": show("perfmon", "toggle"); break
        case "keybinds": show("keybinds", "toggle"); break
        case "settings": show("settings", "open"); break
        // the tile: its list (the list reads the VPNs while open)
        case "vpn": if (compact) { host?.close(); Panels.call("settings", "openPage", "vpn") } else if (host) host.expanded = host.expanded === "vpn" ? "" : "vpn"; break
        case "lock": host?.runClosed(() => Session.lock()); break
        case "suspend": host?.runClosed(() => Session.suspend()); break
        case "logout": host?.runClosed(() => Session.logout()); break
        case "reboot": host?.runClosed(() => Session.reboot()); break
        case "poweroff": host?.runClosed(() => Session.poweroff()); break
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
            switchable: root.itemId !== "vpn"
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
