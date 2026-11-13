import QtQuick
import QtQuick.Layouts
import qs.services

// "Nothing here": a big dim glyph, one line, an optional hint and action.
// The same in every list, panel and app (no results, no mail, no events,
// nothing playing, an error that left the list empty).
//
//   EmptyState { icon: "󰇮"; text: "No messages"; hint: "Mail you get shows up here" }
//   EmptyState { icon: "󰀦"; text: "Couldn't load"; tone: "error"; actionText: "Retry"; onAction: retry() }
//   EmptyState { loading: true; text: "Loading…" }                 // the loading state
ColumnLayout {
    id: root
    property string icon: "󰋼"
    property string text: ""
    property string hint: ""
    property string actionText: ""
    property string tone: "normal"      // "normal" | "error"
    property bool loading: false
    property bool compact: false        // small panels / cards: smaller glyph, no hint
    signal action()

    spacing: Tokens.space.s6
    Accessible.role: Accessible.StaticText
    Accessible.name: text + (hint !== "" ? ". " + hint : "")

    Spinner {
        visible: root.loading
        Layout.alignment: Qt.AlignHCenter
        running: root.loading
        size: root.compact ? Tokens.font.title : Tokens.font.display
        color: Colors.textFaint
    }
    Text {
        visible: !root.loading && root.icon !== ""
        Layout.alignment: Qt.AlignHCenter
        text: root.icon
        color: root.tone === "error" ? Colors.alpha(Colors.danger, 0.7) : Colors.textFaint
        font.pixelSize: root.compact ? Tokens.font.title : Tokens.font.display
        font.family: Properties.fontFamily
    }
    Text {
        visible: root.text !== ""
        // as wide as the state when it has a width (wraps there), else as the text
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: root.text
        color: root.tone === "error" ? Colors.danger : Colors.textMuted
        font.pixelSize: root.compact ? Tokens.font.small : Tokens.font.body
        font.family: Properties.fontFamily
    }
    Text {
        visible: root.hint !== "" && !root.compact
        // as wide as the state when it has a width (wraps there), else as the text
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: root.hint
        color: Colors.textMuted
        font.pixelSize: Tokens.font.caption
        font.family: Properties.fontFamily
    }
    ActionButton {
        visible: root.actionText !== ""
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Tokens.space.s4
        text: root.actionText
        onClicked: root.action()
    }
}
