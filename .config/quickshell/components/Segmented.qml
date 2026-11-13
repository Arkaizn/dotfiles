import QtQuick
import QtQuick.Layouts
import qs.services

// Pick one of a few options: a segmented control whose highlight slides to the
// selected option, or (variant "tabs") plain words with a sliding underline
// (the calendar's view switcher).
//
//   Segmented { options: [{ label: "Day", value: "day", icon: "…" }, …]; value: v; onEdited: x => v = x }
//   Segmented { options: ["off", "5", "10"]; value: v; onEdited: x => v = x }   // strings: label = value
//   Segmented { variant: "tabs"; options: ["day", "week", "month"]; … }
//
// Keyboard: Tab focuses it, ←/→ (Home/End) pick the neighbour. It doesn't
// change itself — the owner sets `value` from `edited`.
// (Was settings/network/Segmented + settings/Segmented; `navStyle: true`
// still means variant "tabs".)
Item {
    id: root
    property var options: []
    property var value
    property bool small: false
    property bool navStyle: false
    property string variant: navStyle ? "tabs" : "segmented"
    property string accessibleName: ""
    signal edited(var value)

    readonly property bool tabs: variant === "tabs"
    // strings and objects alike: [{ label, value, icon }]
    readonly property var opts: (options ?? []).map(o => typeof o === "object" && o !== null ? o : { label: String(o), value: o })
    readonly property int current: opts.findIndex(o => o.value === value)

    implicitWidth: row.implicitWidth + (tabs ? 0 : 6)
    implicitHeight: small ? Tokens.size.control - 4 : Tokens.size.control

    activeFocusOnTab: true
    Accessible.role: Accessible.PageTabList
    Accessible.name: accessibleName
    function pick(i) {
        if (i < 0 || i >= opts.length || i === current) return
        edited(opts[i].value)
    }
    Keys.onLeftPressed: pick(Math.max(0, current - 1))
    Keys.onRightPressed: pick(Math.min(opts.length - 1, current + 1))
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Home) { pick(0); e.accepted = true }
        else if (e.key === Qt.Key_End) { pick(opts.length - 1); e.accepted = true }
    }
    FocusRing { controlRadius: Tokens.radius.lg; shown: root.activeFocus }

    // the track (segmented)
    Rectangle {
        visible: !root.tabs
        anchors.fill: parent
        radius: Tokens.radius.lg
        color: Colors.dim(Colors.light ? 0.06 : 0.25)
        border.width: Tokens.border.thin
        border.color: Colors.line(0.08)
    }

    // the sliding highlight (segmented)
    Rectangle {
        readonly property Item target: root.current >= 0 && rep.count > root.current ? rep.itemAt(root.current) : null
        visible: !root.tabs && target !== null
        x: (target?.x ?? 0) + 3
        y: 3
        width: target?.width ?? 0
        height: parent.height - 6
        radius: Tokens.radius.md
        color: Colors.alpha(Colors.accent, 0.22)
        border.width: Tokens.border.thin
        border.color: Colors.alpha(Colors.accent, 0.55)
        Behavior on x { NumberAnimation { duration: Anim.medium; easing.type: Anim.standard } }
        Behavior on width { NumberAnimation { duration: Anim.medium; easing.type: Anim.standard } }
    }

    RowLayout {
        id: row
        x: root.tabs ? 0 : 3
        y: root.tabs ? 0 : 3
        height: parent.height - (root.tabs ? 0 : 6)
        spacing: root.tabs ? 2 : 0
        Repeater {
            id: rep
            model: root.opts
            Item {
                id: opt
                required property var modelData
                required property int index
                readonly property bool selected: index === root.current
                implicitWidth: optRow.implicitWidth + (root.tabs ? 18 : root.small ? 16 : 22)
                Layout.fillHeight: true
                Accessible.role: Accessible.PageTab
                Accessible.name: modelData.label
                Accessible.selected: selected

                // tabs: a soft hover tint instead of a highlight
                Rectangle {
                    visible: root.tabs
                    anchors.fill: parent
                    radius: Tokens.radius.md
                    color: Colors.fillSubtle
                    opacity: mouse.containsMouse && !opt.selected ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Anim.fast } }
                }

                RowLayout {
                    id: optRow
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: root.tabs ? -1 : 0
                    spacing: 5
                    Text {
                        visible: (opt.modelData.icon ?? "") !== ""
                        text: opt.modelData.icon ?? ""
                        color: opt.selected ? Colors.accent : Colors.fade(0.6)
                        font.pixelSize: Tokens.font.body
                        font.family: Properties.fontFamily
                        Behavior on color { ColorAnimation { duration: Anim.normal } }
                    }
                    Text {
                        text: opt.modelData.label
                        color: opt.selected ? Colors.ink : Colors.fade(mouse.containsMouse ? 0.85 : 0.6)
                        font.pixelSize: root.tabs ? Tokens.font.body : root.small ? Tokens.font.caption : Tokens.font.small
                        font.bold: opt.selected
                        font.family: Properties.fontFamily
                        Behavior on color { ColorAnimation { duration: Anim.normal } }
                    }
                }
                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: opt.selected ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: root.pick(opt.index)
                }
            }
        }
    }

    // the line under the current option (tabs), sliding between them
    Rectangle {
        id: line
        readonly property Item target: root.current >= 0 && rep.count > root.current ? rep.itemAt(root.current) : null
        readonly property real lineW: target ? Math.max(12, target.implicitWidth - 18) : 0
        visible: root.tabs && target !== null
        x: target ? row.x + target.x + (target.width - lineW) / 2 : 0
        width: lineW
        y: root.height - 4
        height: 2
        radius: 1
        color: Colors.accent
        Behavior on x { enabled: line.visible; NumberAnimation { duration: Anim.medium; easing.type: Anim.standard } }
        Behavior on width { enabled: line.visible; NumberAnimation { duration: Anim.medium; easing.type: Anim.standard } }
    }
}
