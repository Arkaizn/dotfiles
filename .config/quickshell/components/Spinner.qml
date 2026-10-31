import QtQuick
import qs.services

// "Working on it": a turning glyph. Keeps turning with Reduce motion on (it
// tells you something is happening), but slower.
//
//   Spinner { running: Store.syncing; size: Tokens.font.label }
//   Spinner { running: busy; glyph: "󰑐" }      // spin an existing icon
Text {
    id: root

    property bool running: true
    property int size: Tokens.font.label
    property string glyph: "󰑓"

    text: glyph
    color: Colors.textSecondary
    font.pixelSize: size
    font.family: Properties.fontFamily
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    Accessible.role: Accessible.Animation
    Accessible.name: running ? "Working" : ""

    RotationAnimation on rotation {
        running: root.running && root.visible
        loops: Animation.Infinite
        from: 0; to: 360
        duration: Anim.ambient ? 900 : 2400
        onRunningChanged: if (!running) root.rotation = 0
    }
}
