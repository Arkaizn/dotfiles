import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Networking
import qs.components
import qs.services

// Wi-Fi network list: scan, connect (with password prompt), disconnect, forget.
ColumnLayout {
    id: root

    property var device: null          // WifiDevice
    property bool active: false        // scan only while the list is shown
    readonly property int maxListHeight: 260

    spacing: 6

    // keep scanning while open
    Binding {
        target: root.device
        property: "scannerEnabled"
        value: root.active
        when: root.device !== null
    }

    function strength(n) {
        const s = n.signalStrength ?? 0
        return s > 1 ? s / 100 : s
    }
    function signalIcon(n) {
        const s = strength(n)
        if (s > 0.75) return "󰤨"
        if (s > 0.5) return "󰤥"
        if (s > 0.25) return "󰤢"
        return "󰤟"
    }

    // connected first, then saved, then by signal
    readonly property var networks: (device?.networks?.values ?? [])
        .filter(n => n.name && n.name.length > 0)
        .sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (strength(b) - strength(a)))

    property string passwordFor: ""    // network name currently asking for a password
    property string errorFor: ""

    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: !Networking.wifiEnabled ? "Wi-Fi is off"
                : root.networks.length === 0 ? "Scanning…"
                : root.networks.length + " networks"
            color: Colors.fade(0.55)
            font.pixelSize: 11
        }
        IconButton {
            implicitWidth: 26; implicitHeight: 26
            icon: "󰒓"
            tooltip: "Saved networks, hidden network"
            onClicked: { Panels.close("controlCenter"); Panels.call("settings", "openPage", "wifi") }
        }
    }

    Flickable {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(list.implicitHeight, root.maxListHeight)
        contentHeight: list.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: list
            width: parent.width
            spacing: 4

            Repeater {
                model: Networking.wifiEnabled ? root.networks : []

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property var net: modelData
                    readonly property bool secured: net.security !== WifiSecurityType.Open
                    readonly property bool busy: net.stateChanging
                    readonly property bool askingPassword: root.passwordFor === net.name

                    Layout.fillWidth: true
                    implicitHeight: rowCol.implicitHeight + 12
                    radius: 10
                    color: net.connected ? Colors.fade(0.12)
                         : rowMouse.containsMouse ? Colors.fade(0.07) : "transparent"
                    Behavior on color { ColorAnimation { duration: 80 } }

                    function activate() {
                        if (net.connected || busy) return
                        root.errorFor = ""
                        if (net.known || !secured) net.connect()
                        else { root.passwordFor = net.name; pw.text = ""; pw.forceActiveFocus() }
                    }

                    Connections {
                        target: row.net
                        function onConnectionFailed(reason) {
                            root.errorFor = row.net.name
                            if (reason === ConnectionFailReason.NoSecrets) {
                                root.passwordFor = row.net.name
                                pw.forceActiveFocus()
                            }
                        }
                        function onConnectedChanged() {
                            if (row.net.connected && root.passwordFor === row.net.name) root.passwordFor = ""
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: row.net.connected ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: row.activate()
                    }

                    ColumnLayout {
                        id: rowCol
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 6 }
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: root.signalIcon(row.net)
                                color: Colors.ink
                                font.pixelSize: 15
                                font.family: Properties.fontFamily
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: row.net.name
                                    color: Colors.ink
                                    font.pixelSize: 12
                                    font.bold: row.net.connected
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    text: row.busy ? (row.net.connected ? "Disconnecting…" : "Connecting…")
                                        : root.errorFor === row.net.name ? "Connection failed"
                                        : row.net.connected ? "Connected"
                                        : row.net.known ? "Saved" : ""
                                    color: root.errorFor === row.net.name && !row.busy ? Colors.red : Colors.fade(0.5)
                                    font.pixelSize: 10
                                }
                            }
                            Text {
                                visible: row.secured
                                text: "󰌾"
                                color: Colors.fade(0.45)
                                font.pixelSize: 11
                                font.family: Properties.fontFamily
                            }
                            IconButton {
                                visible: row.net.connected
                                implicitWidth: 26; implicitHeight: 26
                                icon: "󰖪"
                                tooltip: "Disconnect"
                                onClicked: row.net.disconnect()
                            }
                            IconButton {
                                visible: row.net.known
                                implicitWidth: 26; implicitHeight: 26
                                icon: "󰆴"
                                tooltip: "Forget"
                                onClicked: row.net.forget()
                            }
                        }

                        // password prompt
                        RowLayout {
                            Layout.fillWidth: true
                            visible: row.askingPassword
                            spacing: 6

                            SearchField {
                                id: pw
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                placeholderText: "Password"
                                icon: "󰌾"
                                password: !showPw.on
                                font.pixelSize: 12
                                onAccepted: connectBtn.clicked()
                                Keys.onEscapePressed: root.passwordFor = ""
                            }
                            IconButton {
                                id: showPw
                                property bool on: false
                                implicitWidth: 28; implicitHeight: 28
                                active: on
                                icon: on ? "󰈈" : "󰈉"
                                tooltip: "Show password"
                                onClicked: on = !on
                            }
                            IconButton {
                                id: connectBtn
                                implicitWidth: 28; implicitHeight: 28
                                icon: "󰄬"
                                tooltip: "Connect"
                                interactive: pw.text.length >= 8
                                onClicked: {
                                    root.errorFor = ""
                                    row.net.connectWithPsk(pw.text)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
