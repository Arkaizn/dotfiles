import Quickshell
import QtQuick
import qs.services
import qs.components

BarButton {
    id: clock
    contentWidth: clockRow.implicitWidth
    onClicked: Panels.toggle("dashboard", (QsWindow.window as QsWindow)?.screen)

    Row {
        id: clockRow
        anchors.centerIn: parent
        spacing: 1

        Text {
            id: hoursText
            text: Time.format("hh")
            color: Properties.color
            font.pixelSize: 12
            font.weight: Font.Bold
            font.family: "Inter"
            font.letterSpacing: 0.3
        }

        Text {
            id: colonSeparator
            text: ":"
            color: Colors.color4
            font.pixelSize: 12
            font.weight: Font.Bold
            font.family: "Inter"

            // blinks with the seconds: one redraw a second (a smooth pulse
            // redrew the bar on every frame, ~2.5 % CPU per 60 Hz bar)
            opacity: Time.seconds % 2 === 0 ? 1.0 : 0.4
        }

        Text {
            id: minutesText
            text: Time.format("mm")
            color: Properties.color
            font.pixelSize: 12
            font.weight: Font.Bold
            font.family: "Inter"
            font.letterSpacing: 0.3
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Time.format("ddd d")
            color: Properties.color
            font.pixelSize: 10
            font.weight: Font.Medium
            font.family: "Inter"
        }
    }
}
