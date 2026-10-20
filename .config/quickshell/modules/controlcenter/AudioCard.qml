import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.components
import qs.services

// Volume: output device picker, output + mic volume, and a mixer with
// every app that is currently playing audio.
CCCard {
    id: root

    implicitHeight: col.implicitHeight + 24

    // ── Pipewire nodes ──
    // Filter on `type`, not properties: properties stay empty until a node is
    // tracked. AudioOutStream = apps playing audio (capture streams like cava
    // are AudioInStream and stay out).
    // hidden devices (Settings → Audio) stay out, unless one is the default
    readonly property var sinks: Pipewire.nodes.values
        .filter(n => n.type === PwNodeType.AudioSink && !Audio.isInternal(n) && (!Audio.isHidden(n) || n === Pipewire.defaultAudioSink))
        .sort((a, b) => root.nodeName(a).localeCompare(root.nodeName(b)))
    readonly property var sources: Pipewire.nodes.values
        .filter(n => n.type === PwNodeType.AudioSource && !Audio.isInternal(n) && (!Audio.isHidden(n) || n === Pipewire.defaultAudioSource))
        .sort((a, b) => root.nodeName(a).localeCompare(root.nodeName(b)))
    readonly property var streams: Pipewire.nodes.values
        .filter(n => n.type === PwNodeType.AudioOutStream && !n.name.startsWith("speech-dispatcher") && !Audio.isInternal(n))

    // The saved default can point at an unplugged device (Quickshell then
    // reports null); fall back like WirePlumber does: highest session priority.
    function fallback(list) {
        let best = null
        for (const n of list) {
            const p = parseInt(n.properties?.["priority.session"] ?? "0")
            if (!best || p > best.p) best = { n: n, p: p }
        }
        return best?.n ?? null
    }
    readonly property var sink: Pipewire.defaultAudioSink ?? fallback(sinks)
    readonly property var source: Pipewire.defaultAudioSource ?? fallback(sources)

    // volume/mute only update for tracked nodes
    PwObjectTracker { objects: root.sinks.concat(root.sources).concat(root.streams) }

    property string picker: ""   // "" | "output" | "input"
    property bool appsOpen: false

    // back to all-collapsed (called when the control center closes)
    function reset() {
        picker = ""
        appsOpen = false
    }

    // your alias from Settings → Audio, else the device's description
    function nodeName(n) {
        return Audio.label(n)
    }
    function appName(n) {
        const p = n.properties ?? {}
        return p["application.name"] || p["application.process.binary"] || nodeName(n)
    }
    function appIcon(n) {
        const p = n.properties ?? {}
        const candidates = [p["application.icon-name"], p["application.process.binary"],
                            (p["application.name"] ?? "").toLowerCase()]
        for (const c of candidates) {
            if (!c) continue
            const path = Quickshell.iconPath(c, true)
            if (path) return path
            const entry = DesktopEntries.heuristicLookup(c)
            if (entry?.icon) {
                const p2 = Quickshell.iconPath(entry.icon, true)
                if (p2) return p2
            }
        }
        return ""
    }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 8

        // ── Output ──
        DeviceHeader {
            label: "Output"
            current: root.nodeName(root.sink)
            open: root.picker === "output"
            onToggled: root.picker = open ? "" : "output"
        }
        Collapsible {
            open: root.picker === "output"
            DevicePicker {
                nodes: root.sinks
                current: root.sink
                nameOf: root.nodeName
                onPicked: node => { Pipewire.preferredDefaultAudioSink = node; root.picker = "" }
            }
        }
        VolumeRow {
            Layout.fillWidth: true
            node: root.sink
            icon: "󰕾"
            mutedIcon: "󰝟"
        }

        // ── Input ──
        DeviceHeader {
            label: "Input"
            current: root.nodeName(root.source)
            open: root.picker === "input"
            onToggled: root.picker = open ? "" : "input"
        }
        Collapsible {
            open: root.picker === "input"
            DevicePicker {
                nodes: root.sources
                current: root.source
                nameOf: root.nodeName
                onPicked: node => { Pipewire.preferredDefaultAudioSource = node; root.picker = "" }
            }
        }
        VolumeRow {
            Layout.fillWidth: true
            node: root.source
            icon: "󰍬"
            mutedIcon: "󰍭"
        }

        // ── Apps ──
        Rectangle { Layout.fillWidth: true; Layout.topMargin: 2; height: 1; color: Colors.fade(0.13) }

        Item {
            Layout.fillWidth: true
            implicitHeight: 26

            MouseArea {
                id: appsMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.appsOpen = !root.appsOpen
            }

            RowLayout {
                anchors.fill: parent
                spacing: 8
                Text {
                    text: "Apps"
                    color: Colors.fade(0.55)
                    font { bold: true; pixelSize: 12 }
                }
                Rectangle {
                    visible: root.streams.length > 0
                    implicitWidth: appCount.implicitWidth + 10; implicitHeight: 18; radius: 9
                    color: Colors.fade(0.25)
                    Text {
                        id: appCount
                        anchors.centerIn: parent
                        text: root.streams.length
                        color: Colors.fade(0.87)
                        font { bold: true; pixelSize: 10 }
                    }
                }
                // collapsed: which apps are playing
                Text {
                    Layout.fillWidth: true
                    text: root.streams.length === 0 ? "Nothing is playing"
                        : [...new Set(root.streams.map(n => root.appName(n)))].join(", ")
                    opacity: root.appsOpen ? 0 : 1
                    color: appsMouse.containsMouse ? Colors.ink : Colors.fade(0.5)
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }
                Chevron { open: root.appsOpen }
                IconButton {
                    implicitWidth: 26; implicitHeight: 26
                    icon: "󰒓"
                    tooltip: "Audio settings"
                    onClicked: { Panels.close("controlCenter"); Panels.call("settings", "openPage", "audio") }
                }
            }
        }

        Collapsible {
            open: root.appsOpen

            Flickable {
                visible: root.streams.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(appsCol.implicitHeight, 230)
                contentHeight: appsCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                ColumnLayout {
                    id: appsCol
                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: root.streams

                        delegate: ColumnLayout {
                            id: app
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Image {
                                    readonly property string src: root.appIcon(app.modelData)
                                    visible: src !== ""
                                    source: src
                                    sourceSize: Qt.size(18, 18)
                                    Layout.preferredWidth: 18
                                    Layout.preferredHeight: 18
                                }
                                Text {
                                    text: root.appName(app.modelData)
                                    color: Colors.ink
                                    font.pixelSize: 12
                                    font.bold: true
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: app.modelData.properties?.["media.name"] ?? ""
                                    color: Colors.fade(0.45)
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }
                            VolumeRow {
                                Layout.fillWidth: true
                                node: app.modelData
                            }
                        }
                    }
                }
            }
        }
    }

    // "Output   Device name  ⌄" — click to show the device list
    component DeviceHeader: Item {
        id: dh
        property string label: ""
        property string current: ""
        property bool open: false
        signal toggled()

        Layout.fillWidth: true
        implicitHeight: 24

        MouseArea {
            id: dhMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: dh.toggled()
        }
        RowLayout {
            anchors.fill: parent
            spacing: 8
            Text {
                text: dh.label
                color: Colors.fade(0.55)
                font { bold: true; pixelSize: 12 }
            }
            Text {
                Layout.fillWidth: true
                text: dh.current
                color: dhMouse.containsMouse ? Colors.ink : Colors.fade(0.87)
                font.pixelSize: 12
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }
            Chevron { open: dh.open }
        }
    }

    // List of devices to choose the default from
    component DevicePicker: ColumnLayout {
        id: dp
        property var nodes: []
        property var current: null
        // inline components can't see the file's ids, so the name lookup is passed in
        property var nameOf: n => n?.description || n?.name || ""
        signal picked(var node)

        Layout.fillWidth: true
        spacing: 2

        Repeater {
            model: dp.nodes
            delegate: Rectangle {
                id: opt
                required property var modelData
                readonly property bool isCurrent: modelData === dp.current
                Layout.fillWidth: true
                implicitHeight: 30
                radius: 8
                color: isCurrent ? Colors.fade(0.14)
                     : optMouse.containsMouse ? Colors.fade(0.07) : "transparent"

                MouseArea {
                    id: optMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: dp.picked(opt.modelData)
                }
                RowLayout {
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    Text {
                        Layout.fillWidth: true
                        text: dp.nameOf(opt.modelData)
                        color: Colors.ink
                        font.pixelSize: 12
                        font.bold: opt.isCurrent
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: opt.isCurrent
                        text: "󰄬"
                        color: Colors.ink
                        font.pixelSize: 13
                        font.family: Properties.fontFamily
                    }
                }
            }
        }
    }
}
