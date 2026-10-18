import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "../settings"

// Polkit agent: the password dialog for anything that needs admin rights
// (global DNS and hostname in the settings app, but also every other app —
// without an agent those requests just fail). Opens on the focused screen,
// dims it, and fades / scales the card in.
Scope {
    id: root

    PolkitAgent {
        id: agent
        // another agent may already run (then this one stays idle)
        onIsRegisteredChanged: {
            console.info("polkit agent registered:", isRegistered)
            Health.polkitAgent = isRegistered       // for the health check
        }
        Component.onCompleted: Health.polkitAgent = isRegistered
    }

    readonly property var flow: agent.flow
    property bool shown: false
    property bool failedOnce: false

    Connections {
        target: agent
        function onAuthenticationRequestStarted() {
            root.failedOnce = false
            Compositor.focusedOutput(name => {
                win.screen = Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0]
                root.shown = true
            })
        }
        function onIsActiveChanged() { if (!agent.isActive) root.shown = false }
    }

    Connections {
        target: root.flow
        ignoreUnknownSignals: true
        function onAuthenticationFailed() {
            root.failedOnce = true
            field.text = ""
            field.error = false
            field.error = true
        }
        function onIsResponseRequiredChanged() { if (root.flow?.isResponseRequired) field.forceActiveFocus() }
    }

    function submit() {
        if (!flow || !flow.isResponseRequired) return
        flow.submit(field.text)
        field.text = ""
    }

    function cancel() {
        if (flow) flow.cancelAuthenticationRequest()
        shown = false
    }

    PanelWindow {
        id: win
        visible: root.shown || backdrop.opacity > 0
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:polkit"
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            id: backdrop
            anchors.fill: parent
            color: "#80000000"
            opacity: root.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            MouseArea { anchors.fill: parent; onClicked: {} }   // swallow clicks
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: 420
            height: col.implicitHeight + 44
            radius: Properties.panelRadius
            color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.94)
            border.width: Properties.panelBorderWidth
            border.color: Properties.panelBorder

            opacity: root.shown ? 1 : 0
            scale: root.shown ? 1 : 0.9
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }

            ColumnLayout {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 22 }
                spacing: 12

                // lock icon in a soft circle
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 56; height: 56; radius: 28
                    color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.15)
                    border.width: 1
                    border.color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.4)
                    Text {
                        anchors.centerIn: parent
                        text: "󰌾"
                        color: Colors.color6
                        font.pixelSize: 26
                        font.family: Properties.fontFamily
                    }
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: "Authentication required"
                    color: "white"
                    font.pixelSize: 17
                    font.bold: true
                    font.family: Properties.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.flow?.message ?? ""
                    color: Qt.rgba(1, 1, 1, 0.7)
                    font.pixelSize: 12
                    font.family: Properties.fontFamily
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    visible: text !== ""
                    text: {
                        const id = root.flow?.selectedIdentity
                        const n = id?.displayName ?? id?.name ?? ""
                        return n !== "" ? "as " + n : ""
                    }
                    color: Qt.rgba(1, 1, 1, 0.45)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                }

                SearchField {
                    id: field
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    icon: "󰌋"
                    password: !(root.flow?.responseVisible ?? false)
                    placeholderText: (root.flow?.inputPrompt ?? "").replace(/:\s*$/, "") || "Password"
                    enabled: root.flow?.isResponseRequired ?? false
                    onAccepted: root.submit()
                    Keys.onEscapePressed: root.cancel()
                }

                // wrong password / PAM messages
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    readonly property string msg: root.flow?.supplementaryMessage ?? ""
                    visible: msg !== "" || root.failedOnce
                    text: msg !== "" ? msg : "Wrong password, try again"
                    color: (root.flow?.supplementaryIsError ?? false) || root.failedOnce ? "#f38ba8" : Qt.rgba(1, 1, 1, 0.6)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 8
                    ActionButton {
                        Layout.fillWidth: true
                        icon: "󰅖"
                        text: "Cancel"
                        onClicked: root.cancel()
                    }
                    ActionButton {
                        Layout.fillWidth: true
                        icon: "󰄬"
                        text: "Authenticate"
                        primary: true
                        interactive: (root.flow?.isResponseRequired ?? false) && field.text !== ""
                        onClicked: root.submit()
                    }
                }
            }
        }

        // focus the field as soon as the dialog shows
        onVisibleChanged: if (visible) Qt.callLater(() => field.forceActiveFocus())
    }
}
