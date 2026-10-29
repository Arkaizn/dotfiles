import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "../settings"

// The shell's own password / PIN prompt (services/SecretPrompt.qml): looks
// like the polkit dialog. RDP connections ask here for their password or
// smartcard PIN; with several certificates on the card you pick one too.
Scope {
    id: root

    readonly property var req: SecretPrompt.request
    property bool shown: false
    property int choice: 0
    // kept while the card fades out (the request is gone by then)
    property var last: null

    Connections {
        target: SecretPrompt
        function onRequestChanged() {
            if (!SecretPrompt.request) { root.shown = false; return }
            root.last = SecretPrompt.request
            root.choice = 0
            field.text = ""
            Compositor.focusedOutput(name => {
                win.screen = Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0]
                root.shown = true
                Qt.callLater(() => field.forceActiveFocus())
            })
        }
    }

    readonly property var view: last ?? ({ choices: [] })
    readonly property bool ready: field.text.length >= (view.minLength ?? 1)

    function submit() {
        if (!root.req || !root.ready) return
        const t = field.text
        field.text = ""
        SecretPrompt.answer(t, root.choice)
    }

    PanelWindow {
        id: win
        visible: root.shown || backdrop.opacity > 0
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:secret"
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            id: backdrop
            anchors.fill: parent
            color: Colors.shade(0.5)
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

                // icon in a soft circle
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 56; height: 56; radius: 28
                    color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.15)
                    border.width: 1
                    border.color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.4)
                    Text {
                        anchors.centerIn: parent
                        text: root.view.icon ?? "󰌋"
                        color: Colors.color6
                        font.pixelSize: 26
                        font.family: Properties.fontFamily
                    }
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.view.title ?? ""
                    color: Colors.ink
                    font.pixelSize: 17
                    font.bold: true
                    font.family: Properties.fontFamily
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    visible: text !== ""
                    text: root.view.message ?? ""
                    color: Colors.fade(0.7)
                    font.pixelSize: 12
                    font.family: Properties.fontFamily
                    wrapMode: Text.WordWrap
                }

                // several certificates on the card: which one
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: (root.view.choices ?? []).length > 1
                    spacing: 4
                    Repeater {
                        model: root.view.choices ?? []
                        Rectangle {
                            id: opt
                            required property var modelData
                            required property int index
                            readonly property bool picked: root.choice === index
                            Layout.fillWidth: true
                            implicitHeight: optCol.implicitHeight + 14
                            radius: 9
                            color: picked ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.15)
                                 : optMouse.containsMouse ? Colors.fade(0.06) : Colors.fade(0.03)
                            border.width: 1
                            border.color: picked ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.5) : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }
                            ColumnLayout {
                                id: optCol
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
                                spacing: 1
                                Text {
                                    Layout.fillWidth: true
                                    text: opt.modelData.label
                                    color: Colors.ink
                                    font.pixelSize: 12
                                    font.bold: opt.picked
                                    font.family: Properties.fontFamily
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    text: opt.modelData.desc ?? ""
                                    color: Colors.fade(0.5)
                                    font.pixelSize: 10
                                    font.family: Properties.fontFamily
                                    elide: Text.ElideRight
                                }
                            }
                            MouseArea {
                                id: optMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { root.choice = opt.index; field.forceActiveFocus() }
                            }
                        }
                    }
                }

                SearchField {
                    id: field
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    icon: "󰌋"
                    password: true
                    placeholderText: root.view.placeholder ?? "Password"
                    enabled: root.req !== null
                    onAccepted: root.submit()
                    Keys.onEscapePressed: SecretPrompt.cancel()
                    Keys.onUpPressed: root.choice = Math.max(0, root.choice - 1)
                    Keys.onDownPressed: root.choice = Math.min((root.view.choices ?? []).length - 1, root.choice + 1)
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    visible: text !== ""
                    text: root.view.hint ?? ""
                    color: Colors.fade(0.45)
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
                        onClicked: SecretPrompt.cancel()
                    }
                    ActionButton {
                        Layout.fillWidth: true
                        icon: "󰄬"
                        text: root.view.action ?? "OK"
                        primary: true
                        interactive: root.req !== null && root.ready
                        onClicked: root.submit()
                    }
                }
            }
        }

        onVisibleChanged: if (visible) Qt.callLater(() => field.forceActiveFocus())
    }
}
