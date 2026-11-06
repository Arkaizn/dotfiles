import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.components
import qs.services
import "lib/FmSelect.js" as FmSelect
import "lib/FmIcons.js" as FmIcons

// Select by pattern (Ctrl+S, like Nautilus' "Select Items Matching"): a
// shell-style pattern — "*.png", "IMG_??.jpg", "*.{jpg,png}", several with ";" —
// ignoring case. How many it matches shows while typing; Enter selects them
// (instead of the selection there was).
//   PatternDialog { onPicked: re => … }   start(count, nameAt)
Modal {
    id: root

    cardWidth: 440
    property int count: 0
    property var nameAt: i => ""
    property string last: "*"            // the pattern of the last time, offered again
    signal picked(var re)

    readonly property var re: FmSelect.glob(field.text)
    readonly property int matches: re ? Object.keys(FmSelect.matching(count, nameAt, re)).length : 0

    function start(n, at) {
        count = n
        nameAt = at
        field.text = last
        open()
        field.forceActiveFocus()
        field.selectAll()
    }
    function apply() {
        if (!re) return
        last = field.text
        close()
        picked(re)
    }

    ColumnLayout {
        width: parent.width
        spacing: Tokens.space.s16

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s12
            Rectangle {
                implicitWidth: Tokens.size.controlLarge; implicitHeight: Tokens.size.controlLarge; radius: Tokens.radius.xl
                color: Colors.alpha(Colors.accent, 0.14)
                Text { anchors.centerIn: parent; text: FmIcons.g.search; color: Colors.accent; font.pixelSize: Tokens.font.title; font.family: Properties.fontFamily }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.space.s1
                Text { text: "Select by pattern"; color: Colors.ink; font.pixelSize: Tokens.font.subtitle; font.bold: true; font.family: Properties.fontFamily }
                Text {
                    Layout.fillWidth: true
                    text: "* any text · ? one character · {a,b} either · [abc] one of · ; between patterns"
                    color: Colors.fade(0.5)
                    font.pixelSize: Tokens.font.caption
                    font.family: Properties.fontFamily
                    wrapMode: Text.Wrap
                }
            }
        }

        SearchField {
            id: field
            Layout.fillWidth: true
            icon: ""
            placeholderText: "*.png"
            onAccepted: root.apply()
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s8
            Text {
                Layout.fillWidth: true
                text: !root.re ? "Type a pattern" : root.matches === 0 ? "Nothing matches" : root.matches + (root.matches === 1 ? " item matches" : " items match")
                color: root.re && root.matches > 0 ? Colors.fade(0.7) : Colors.fade(0.45)
                font.pixelSize: Tokens.font.small
                font.family: Properties.fontFamily
            }
            ActionButton { text: "Cancel"; variant: "ghost"; onClicked: root.close() }
            ActionButton { text: "Select"; variant: "primary"; interactive: root.re !== null && root.matches > 0; onClicked: root.apply() }
        }
    }
}
