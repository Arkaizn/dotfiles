import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.services
import qs.components

// Notification center: output device, app mixer, notifications.
// Window/shape/animation all come from BarPopup.
BarPopup {
    id: root
    side: "right"
    ipcName: "notifCenter"
    panelWidth: 400
    panelHeight: mainCol.implicitHeight + padding * 2
    maxHeight: 900   // room for the content to grow without resizing the surface

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

    ColumnLayout {
        id: mainCol
        anchors { top: parent.top; left: parent.left; right: parent.right }
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
}
