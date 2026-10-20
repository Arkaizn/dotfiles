import QtQuick
import qs.services

// Sticky note: your text (edit it in the live editor or in Settings → Desktop widgets).
// As wide as its longest line, at most ~24 characters per text size, then it wraps.
Item {
    id: root
    property var opts: ({})
    property bool interactive: true
    property bool active: true

    implicitWidth: Math.ceil(note.width)
    implicitHeight: Math.ceil(note.implicitHeight)

    TextMetrics {
        id: longest
        font: note.font
        text: (root.opts.text ?? "").split("\n").reduce((a, l) => l.length > a.length ? l : a, "")
    }
    Text {
        id: note
        width: Math.min(Math.max(longest.advanceWidth + 2, 60), (root.opts.size ?? 16) * 24)
        text: root.opts.text ?? ""
        wrapMode: Text.Wrap
        horizontalAlignment: root.opts.align === "center" ? Text.AlignHCenter : root.opts.align === "right" ? Text.AlignRight : Text.AlignLeft
        color: Colors.ink
        font.pixelSize: root.opts.size ?? 16
        font.family: Properties.fontFamily
        lineHeight: 1.15
    }
}
