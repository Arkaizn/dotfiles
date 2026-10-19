import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services

// ── pieces ──────────────────────────────────────────────────────────────
RowLayout {
    id: cl
    property string text
    property color dot: "transparent"
    spacing: 6
    Rectangle { visible: cl.dot.a > 0; implicitWidth: 6; implicitHeight: 6; radius: 3; color: cl.dot }
    Text { text: cl.text; color: Colors.fade(0.42); font.pixelSize: 10; font.bold: true; font.letterSpacing: 1.2; font.family: Properties.fontFamily }
}
