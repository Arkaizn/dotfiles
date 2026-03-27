import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Controls
import qs.services
import qs.components

Rectangle {
    id: root
    implicitWidth: text.implicitWidth + bar.buttonWidth
    implicitHeight: bar.buttonHeight
    anchors.margins: 1
    radius: bar.buttonradius
    property bool hovered: mouseArea.containsMouse

    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    gradient: ButtonGradient {
        hovered: root.hovered
    }

    Behavior on scale {
        NumberAnimation {
            duration: bar.bduration
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: 7
        color: Qt.rgba(0.12, 0.12, 0.12, hovered ? 0.30 : 0.18)

        Text {
            id: text
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: bar.pixelSize
            color: root.hovered ? Colors.color6 : Colors.foreground

            text: {
                if (root.sink?.audio?.muted) return "󰝟";
                if (!root.sink?.ready || !root.sink?.audio) return "󰓃 --%";

                let name = root.sink.name.toLowerCase();
                let isHeadset = name.includes("headset") || name.includes("phone");
                let icon = isHeadset ? "󰋋" : "󰓃";
                let v = root.sink.audio.volume;
                let pct = isNaN(v) ? "0" : Math.round(v * 100);
                return icon + " " + pct + "%";
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        onEntered: root.scale = bar.onEnteredButtonScale
        onExited: root.scale = onExitedButtonScale
        // onClicked: Quickshell.execDetached(["bash", "-lc", "pavucontrol"])

        onWheel: (wheel) => {
            if (root.sink?.ready && root.sink?.audio) {
                let delta = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
                root.sink.audio.volume = Math.max(0, Math.min(1.0, root.sink.audio.volume + delta));
            }
        }

        onPressed: (mouse) => {
        if (mouse.button === Qt.LeftButton) {
            Quickshell.execDetached(["bash", "-lc", "pavucontrol"])
        } else if (mouse.button === Qt.RightButton) {
            if (root.sink?.audio) root.sink.audio.muted = !root.sink.audio.muted;
        }
    }
    }
}