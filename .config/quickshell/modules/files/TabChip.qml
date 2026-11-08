import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "lib/FmIcons.js" as FmIcons

// One tab in the tab strip: the folder's name, a close button; middle click
// closes it, dragging it sideways moves it (`dragged(steps)` on release: how
// many places, by the tabs' width). Files dragged over it: TabStrip's drop area.
Pressable {
    id: c
    property var tab: null               // its FolderTab (grows in only the first time it shows)
    property string label: ""
    property string path: ""
    property bool current: false
    signal closeRequested()
    signal dragged(int steps)
    property bool dropHover: false       // files are dragged over it (TabStrip's drop area)

    implicitHeight: Tokens.size.controlSmall + Tokens.space.s4
    focusRadius: Tokens.radius.lg
    accessibleName: label + (current ? " (current tab)" : "")
    accessibleRole: Accessible.PageTab
    tooltip: path

    // dragged: drawn where the pointer has it, above its neighbours
    property real shift: 0
    transform: Translate { x: c.shift }
    z: drag.active ? 2 : 0
    DragHandler {
        id: drag
        target: null
        yAxis.enabled: false
        onActiveChanged: {
            if (active) return
            const steps = Math.round(c.shift / Math.max(1, c.width))
            c.shift = 0
            if (steps !== 0) c.dragged(steps)
        }
        onTranslationChanged: if (active) c.shift = translation.x
    }
    // a new tab grows in
    Component.onCompleted: {
        if (!tab || tab.introduced) return
        tab.introduced = true
        opacity = 0
        appear.start()
    }
    // closing: it fades, shrinks a little and folds its width away (`keep` 1 → 0, the
    // strip sizes it by that), so the tabs after it slide over; then `done` removes it
    property bool leaving: false
    property real keep: 1
    function leave(done) {
        if (leaving) return
        leaving = true
        appear.stop()
        leaveAnim.done = done
        leaveAnim.start()
    }
    SequentialAnimation {
        id: leaveAnim
        property var done: null
        ParallelAnimation {
            NumberAnimation { target: c; property: "opacity"; to: 0; duration: Anim.fast; easing.type: Anim.exit }
            NumberAnimation { target: c; property: "scale"; to: 0.9; duration: Anim.normal; easing.type: Anim.exit }
            NumberAnimation { target: c; property: "keep"; to: 0; duration: Anim.normal; easing.type: Anim.standard }
        }
        ScriptAction { script: if (leaveAnim.done) leaveAnim.done() }
    }
    ParallelAnimation {
        id: appear
        NumberAnimation { target: c; property: "opacity"; to: 1; duration: Anim.normal; easing.type: Anim.standard }
        NumberAnimation { target: c; property: "scale"; from: 0.9; to: 1; duration: Anim.normal; easing.type: Anim.pop }
    }
    TapHandler {
        acceptedButtons: Qt.MiddleButton
        onTapped: if (!c.leaving) c.closeRequested()
    }

    Rectangle {
        anchors.fill: parent
        radius: Tokens.radius.lg
        // the current one's card is the strip's sliding highlight
        color: c.dropHover ? Colors.alpha(Colors.accent, 0.18) : c.current ? "transparent"
             : c.pressed ? Colors.fillPressed : c.hovered ? Colors.fillHover : "transparent"
        Behavior on color { ColorAnimation { duration: Anim.fast } }
    }
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.space.s10
        anchors.rightMargin: Tokens.space.s2
        spacing: Tokens.space.gap
        Text {
            text: FmIcons.g.folder
            color: c.current ? Colors.accent : Colors.fade(0.45)
            font.pixelSize: Tokens.font.small
            font.family: Properties.fontFamily
        }
        Text {
            Layout.fillWidth: true
            text: c.label
            color: c.current ? Colors.ink : Colors.fade(0.6)
            font.pixelSize: Tokens.font.small
            font.bold: c.current
            font.family: Properties.fontFamily
            elide: Text.ElideMiddle
            textFormat: Text.PlainText
        }
        IconButton {
            implicitWidth: Tokens.size.controlSmall - Tokens.space.s4
            implicitHeight: Tokens.size.controlSmall - Tokens.space.s4
            iconSize: Tokens.icon.sm
            icon: "󰅖"
            tooltip: "Close tab  (Ctrl+W)"
            opacity: c.current || c.hovered || hovered ? 1 : 0.5
            // a narrow tab keeps its room for the name: the cross only on the current / hovered one
            visible: c.width >= Tokens.size.row * 4 || c.current || c.hovered || hovered
            onClicked: if (!c.leaving) c.closeRequested()
        }
    }
}
