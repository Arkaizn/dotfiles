import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.services
import qs.components

PanelWindow {
    id: root
    visible: false
    anchors {
        top: true
        right: true
    }
    implicitWidth: 420
    // Fixed surface size: the panel grows/shrinks as notifications come and go,
    // and resizing a layer surface every animation frame causes ghosting.
    // The visible panel (rect) animates inside it; `mask` passes clicks
    // through the empty part.
    implicitHeight: 900
    color: "transparent"
    exclusiveZone: 0

    property bool hasBeenHovered: false
    // Logical open state — `visible` stays true until the close animation finishes.
    property bool shown: false

    BackgroundEffect.blurRegion: Region {
        item: rect
        bottomLeftRadius: 12
        bottomRightRadius: 12
    }
    mask: Region { item: rect }

    PopupAnimation {
        id: anim
        target: rect
        direction: "bottom"   // panel hangs from the top edge → slide down in, up out
        enterDuration: 260
        exitDuration: 200
        onExitFinished: if (!root.shown) root.visible = false
    }

    IpcHandler {
        target: "notifCenter"
        function toggle(): void { root.toggle() }
    }

    function toggle() {
        if (root.shown) close()
        else open()
    }

    function open() {
        autoCloseTimer.stop()
        hasBeenHovered = false
        root.shown = true
        root.visible = true
        BarState.popupOpenRight = true
        enterTimer.start()
    }

    function close() {
        enterTimer.stop()
        autoCloseTimer.stop()
        hasBeenHovered = false
        root.shown = false
        BarState.popupOpenRight = false
        anim.exit()
    }

    Timer {
        id: enterTimer
        interval: 50
        repeat: false
        onTriggered: anim.enter()
    }

    Timer {
        id: autoCloseTimer
        interval: 500
        repeat: false
        onTriggered: root.close()
    }

    // ── Pipewire tracking (must live here so Quickshell manages lifetime) ──
    PwObjectTracker {
        objects: Pipewire.nodes.values.filter(n => n.isSink && n.audio)
    }
    PwObjectTracker {
        objects: Pipewire.nodes.values.filter(n => n.isStream && n.audio && !n.isSink)
    }

    readonly property var outputSinks: Pipewire.nodes.values.filter(n => n.isSink && n.audio)
    readonly property var appStreams:   Pipewire.nodes.values.filter(n => n.isStream && n.audio && !n.isSink)

    function cycleOutput(delta) {
        const sinks = Pipewire.nodes.values.filter(node => {
            return node.audio &&
                node.isSink &&
                !node.isStream &&
                !node.name.includes("monitor") &&
                !node.name.includes("virtual") &&
                node.properties &&
                (node.properties["media.class"] === "Audio/Sink" ||
                    node.properties["node.name"]?.includes("alsa_output"));
        }).sort((a, b) => (a.description || a.name || "").localeCompare(b.description || b.name || ""));

        console.log("cycleOutput - sinks:", sinks.map(s => s.description || s.name));

        if (sinks.length < 2) {
            console.log("Not enough devices to cycle");
            return;
        }

        const current = Pipewire.defaultAudioSink;
        if (!current) {
            console.log("No current default sink");
            return;
        }

        // More robust index finding
        let currentIndex = -1;
        for (let i = 0; i < sinks.length; i++) {
            const s = sinks[i];
            if (s === current || s.id === current.id || s.name === current.name) {
                currentIndex = i;
                break;
            }
        }

        if (currentIndex === -1) {
            console.log("Current sink not found in list, starting from 0");
            currentIndex = 0;
        }

        const nextIndex = (currentIndex + delta + sinks.length) % sinks.length;
        const nextSink = sinks[nextIndex];

        console.log(`Cycling ${delta > 0 ? 'right' : 'left'}: ${currentIndex} → ${nextIndex} (${current.description || current.name} → ${nextSink.description || nextSink.name})`);

        if (nextSink && nextSink !== current) {
            Pipewire.preferredDefaultAudioSink = nextSink;
        }
    }

    // ── Decorative inverse corner ──────────────────────────────
    InverseCorner {
        anchors.right: rect.left
        anchors.top: rect.top
        corner: "topRight"
        color: rect.color
        radius: 12
    }

    // ── Main panel ─────────────────────────────────────────────
    Rectangle {
        id: rect
        // implicitHeight sums mainCol children — grows when AppsCard expands
        // NOTE: no anchors.top — PopupAnimation drives `y`, and a vertical
        // anchor would silently pin it back to 0 (so the slide never showed).
        height: mainCol.implicitHeight + 20
        clip: true
        opacity: 0
        anchors {
            left: parent.left
            right: parent.right
            leftMargin: 10
            rightMargin: 10
        }
        bottomLeftRadius: 12
        bottomRightRadius: 12
        color: '#45000000'

        ColumnLayout {
            id: mainCol
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 10
            }
            spacing: 8

            // ── Output device + master volume ──────────────────
            OutputCard {
                Layout.fillWidth: true
                onCycleOutputRequested: (delta) => root.cycleOutput(delta)
            }

            // ── App mixer (collapsible) ────────────────────────
            // implicitHeight animates open/closed, pushing everything below downward
            AppsCard {
                Layout.fillWidth: true
                appStreams: root.appStreams
            }

            // ── Notifications ──────────────────────────────────
            NotificationsSection {
                id: notifSection
                Layout.fillWidth: true
            }
        }

        HoverHandler {
            id: rectHover
            onHoveredChanged: {
                if (hovered) {
                    hasBeenHovered = true
                    autoCloseTimer.stop()
                } else if (hasBeenHovered) {
                    autoCloseTimer.start()
                }
            }
        }
    }
}
