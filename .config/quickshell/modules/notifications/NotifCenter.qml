import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
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
    // Height driven by rect, which is driven by mainCol, which sums child implicitHeights
    implicitHeight: Math.min(mainCol.implicitHeight + 40, 600)
    color: "transparent"
    exclusiveZone: 0

    // Forwarded aliases so callers can still do root.groupCount / root.addNotification etc.
    property alias groupCount: notifSection.groupCount

    function addNotification(uid, summary, body, appName, appIcon, actionsJson) {
        notifSection.addNotification(uid, summary, body, appName, appIcon, actionsJson)
    }
    function removeGroup(appName) {
        notifSection.removeGroup(appName)
    }
    function clearAll() {
        notifSection.clearAll()
    }

    property bool hasBeenHovered: false

    BackgroundEffect.blurRegion: Region {
        item: rect
        bottomLeftRadius: 12
        bottomRightRadius: 12
    }

    PopupAnimation {
        id: anim
        target: rect
        direction: "top"
        enterDuration: 150
        exitDuration: 150
        onExitFinished: root.visible = false
    }

    function toggle() {
        if (root.visible) {
            anim.exit()
        } else {
            root.visible = true
            BarState.popupOpenRight = true
            enterTimer.start()
        }
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
        onTriggered: {
            anim.exit()
            BarState.popupOpenRight = false
            hasBeenHovered = false
        }
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
        implicitHeight: mainCol.implicitHeight + 20
        clip: true
        opacity: 0
        y: -implicitHeight
        anchors {
            top: parent.top
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
