import QtQuick
import qs.services
import qs.components

// Recording indicator (services/Capture.qml): red dot + time while
// wf-recorder runs, the countdown before a delayed screenshot. Click stops the
// recording. Hidden otherwise.
BarButton {
    id: root
    visible: Capture.recording || Capture.countdown > 0

    readonly property string time: Math.floor(Capture.elapsed / 60) + ":" + String(Capture.elapsed % 60).padStart(2, "0")

    textColor: Capture.recording ? Colors.red : Properties.color
    text: Capture.recording ? (root.hovered ? "󰓛 stop" : Icons.get("recording") + " " + root.time) : "󰔟 " + Capture.countdown
    onClicked: if (Capture.recording) Capture.stop()
}
