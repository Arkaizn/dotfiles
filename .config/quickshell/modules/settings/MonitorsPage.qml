import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// Monitors page of the settings app: drag the screens into place, pick
// resolution / refresh rate / scale / rotation / VRR, then Apply. Applied
// changes are live but revert after 15s unless kept (services/Monitors.qml).
ColumnLayout {
    id: page

    spacing: 14

    // editable copy of Monitors.outputs
    property var draft: []
    property int selected: 0
    property bool edited: false
    property var frozen: null          // canvas mapping held still while dragging
    property bool identifying: false

    readonly property var sel: draft[selected] ?? null

    function copy(x) { return JSON.parse(JSON.stringify(x)) }

    function load() {
        draft = copy(Monitors.outputs)
        edited = false
        if (selected >= draft.length) selected = 0
    }

    Component.onCompleted: { Monitors.refresh(); load() }
    Connections {
        target: Monitors
        function onOutputsChanged() { if (!page.edited && page.frozen === null) page.load() }
    }

    function update(i, patch) {
        const d = draft.slice()
        d[i] = Object.assign({}, d[i], patch)
        draft = d
        edited = true
    }

    // ── Geometry ─────────────────────────────────────────────────────────────
    function rect(c) {
        const s = Monitors.logicalSize(c)
        return { x: c.x, y: c.y, w: s.w, h: s.h }
    }

    function overlaps(a, b) {
        return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y
    }

    function others(i) {
        return draft.map((c, j) => ({ c: c, j: j })).filter(o => o.j !== i && o.c.enabled).map(o => rect(o.c))
    }

    // snap edges of monitor i to the other monitors' edges
    function snap(i, x, y, threshold) {
        const me = rect(Object.assign({}, draft[i], { x: x, y: y }))
        let bx = x, by = y, dx = threshold, dy = threshold
        for (const o of others(i)) {
            for (const cx of [o.x - me.w, o.x + o.w, o.x, o.x + o.w - me.w]) {
                if (Math.abs(cx - x) < dx) { dx = Math.abs(cx - x); bx = cx }
            }
            for (const cy of [o.y - me.h, o.y + o.h, o.y, o.y + o.h - me.h, o.y + (o.h - me.h) / 2]) {
                if (Math.abs(cy - y) < dy) { dy = Math.abs(cy - y); by = cy }
            }
        }
        return [bx, by]
    }

    // after a drop: no overlaps, whole numbers, top-left monitor at 0,0
    function settle(i) {
        const d = copy(draft)
        const me = rect(d[i])
        const rest = others(i)
        const hit = rest.find(o => overlaps(me, o))
        if (d[i].enabled && hit) {
            const cands = []
            for (const o of rest) {
                cands.push({ x: o.x - me.w, y: me.y }, { x: o.x + o.w, y: me.y },
                           { x: me.x, y: o.y - me.h }, { x: me.x, y: o.y + o.h })
            }
            const free = cands.filter(p => !rest.some(o => overlaps(Object.assign({}, me, p), o)))
            free.sort((a, b) => Math.hypot(a.x - me.x, a.y - me.y) - Math.hypot(b.x - me.x, b.y - me.y))
            if (free.length > 0) { d[i].x = free[0].x; d[i].y = free[0].y }
        }
        const on = d.filter(c => c.enabled)
        if (on.length > 0) {
            const mx = Math.min(...on.map(c => c.x)), my = Math.min(...on.map(c => c.y))
            for (const c of d) { c.x = Math.round(c.x - mx); c.y = Math.round(c.y - my) }
        }
        draft = d
        edited = true
    }

    // size of monitor i changes: keep monitors that touched its right/bottom edge touching
    function resize(i, patch) {
        const old = rect(draft[i])
        const d = copy(draft)
        Object.assign(d[i], patch)
        const now = rect(d[i])
        for (let j = 0; j < d.length; j++) {
            if (j === i || !d[j].enabled) continue
            if (d[j].x === old.x + old.w) d[j].x += now.w - old.w
            if (d[j].y === old.y + old.h) d[j].y += now.h - old.h
        }
        draft = d
        edited = true
        settle(i)
    }

    // ── Pending confirmation / errors ────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        visible: !Monitors.included || Monitors.error !== ""
        implicitHeight: bannerText.implicitHeight + 20
        radius: 14
        color: Qt.rgba(0.95, 0.55, 0.66, 0.12)
        border.width: Properties.panelBorderWidth
        border.color: Qt.rgba(0.95, 0.55, 0.66, 0.35)
        Text {
            id: bannerText
            anchors.fill: parent
            anchors.margins: 10
            anchors.leftMargin: 14
            text: !Monitors.included
                ? (Compositor.isHyprland
                    ? "󰀦  Hyprland doesn't load the settings file yet: " + HyprSettings.mainConfig
                      + " needs this as its last line\n" + Monitors.includeLine
                    : "󰀦  niri doesn't load the monitor file yet: " + NiriSettings.mainConfig
                      + " needs\n" + Monitors.includeLine + "\nright before the output.kdl include.")
                : "󰀦  " + Monitors.error
            color: Colors.ink
            font.pixelSize: 11
            font.family: Properties.fontFamily
            wrapMode: Text.WordWrap
        }
    }

    // ── Arrangement ──────────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 290
        radius: 14
        color: Colors.card
        border.width: Properties.panelBorderWidth
        border.color: Properties.cardBorder

        Text {
            anchors { left: parent.left; top: parent.top; margins: 14 }
            text: "Drag to arrange  ·  click to select"
            color: Colors.fade(0.4)
            font.pixelSize: 11
            font.family: Properties.fontFamily
        }

        RowLayout {
            anchors { right: parent.right; top: parent.top; margins: 10 }
            spacing: 6
            IconButton {
                implicitWidth: 30; implicitHeight: 30
                icon: "󰍺"
                tooltip: "Identify (show names on the screens)"
                onClicked: { page.identifying = true; identifyTimer.restart() }
            }
            IconButton {
                implicitWidth: 30; implicitHeight: 30
                icon: "󰑐"
                tooltip: "Rescan monitors"
                onClicked: { page.edited = false; Monitors.refresh() }
            }
        }

        Item {
            id: canvas
            anchors.fill: parent
            anchors.margins: 16
            anchors.topMargin: 44

            // logical px → canvas px, fitted around the enabled monitors
            readonly property var mapping: {
                if (page.frozen) return page.frozen
                const on = page.draft.filter(c => c.enabled).map(c => page.rect(c))
                if (on.length === 0) return { sf: 0.1, ox: 0, oy: 0 }
                const x0 = Math.min(...on.map(r => r.x)), y0 = Math.min(...on.map(r => r.y))
                const x1 = Math.max(...on.map(r => r.x + r.w)), y1 = Math.max(...on.map(r => r.y + r.h))
                // a bit of room around so monitors can be dragged past the others
                const sf = Math.min(width / ((x1 - x0) * 1.35), height / ((y1 - y0) * 1.35))
                return { sf: sf, ox: (width - (x1 - x0) * sf) / 2 - x0 * sf, oy: (height - (y1 - y0) * sf) / 2 - y0 * sf }
            }

            Repeater {
                // count only, so dragging doesn't recreate the delegates
                model: page.draft.length

                Rectangle {
                    id: mon
                    required property int index
                    readonly property var c: page.draft[index]
                    readonly property var r: page.rect(c)
                    readonly property bool isSel: page.selected === index
                    readonly property var m: canvas.mapping

                    visible: c.enabled
                    x: m.ox + r.x * m.sf
                    y: m.oy + r.y * m.sf
                    width: r.w * m.sf
                    height: r.h * m.sf
                    radius: 10
                    color: isSel ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.28) : Colors.fade(0.08)
                    border.width: isSel ? 2 : 1.5
                    border.color: isSel ? Colors.color6 : Colors.fade(drag.containsMouse ? 0.4 : 0.22)
                    z: isSel ? 1 : 0
                    Behavior on color { ColorAnimation { duration: 120 } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - 16
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: mon.c.name
                            color: Colors.ink
                            font.pixelSize: 15
                            font.bold: true
                            font.family: Properties.fontFamily
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: mon.c.model
                            color: Colors.fade(0.6)
                            font.pixelSize: 10
                            font.family: Properties.fontFamily
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: mon.c.width + "×" + mon.c.height + " @ " + Math.round(mon.c.refresh / 1000) + "Hz"
                                  + (mon.c.scale !== 1 ? "  ·  " + mon.c.scale + "x" : "")
                            color: Colors.fade(0.45)
                            font.pixelSize: 10
                            font.family: Properties.fontFamily
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: drag
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        preventStealing: true      // the page's Flickable would take the drag
                        property var start: null

                        onPressed: mouse => {
                            page.selected = mon.index
                            page.frozen = canvas.mapping
                            const p = mapToItem(canvas, mouse.x, mouse.y)
                            start = { mx: p.x, my: p.y, x: mon.c.x, y: mon.c.y }
                        }
                        onPositionChanged: mouse => {
                            if (!pressed || !start) return
                            const p = mapToItem(canvas, mouse.x, mouse.y)
                            const sf = page.frozen.sf
                            const nx = start.x + (p.x - start.mx) / sf
                            const ny = start.y + (p.y - start.my) / sf
                            if (Math.abs(nx - mon.c.x) < 0.5 && Math.abs(ny - mon.c.y) < 0.5) return
                            const s = page.snap(mon.index, nx, ny, 14 / sf)
                            page.update(mon.index, { x: s[0], y: s[1] })
                        }
                        onReleased: {
                            if (start && (mon.c.x !== start.x || mon.c.y !== start.y)) page.settle(mon.index)
                            start = null
                            page.frozen = null
                        }
                    }
                }
            }
        }

        // turned-off monitors
        Row {
            anchors { left: parent.left; bottom: parent.bottom; margins: 12 }
            spacing: 6
            Repeater {
                model: page.draft.length
                ActionButton {
                    required property int index
                    visible: !page.draft[index].enabled
                    icon: "󰶐"
                    text: page.draft[index].name + "  ·  off"
                    primary: page.selected === index
                    textColor: Colors.fade(0.7)
                    onClicked: page.selected = index
                }
            }
        }
    }

    // ── Selected monitor ─────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.sel !== null
        spacing: 8

        RowLayout {
            Layout.leftMargin: 6
            spacing: 8
            Text {
                text: page.sel ? (page.sel.make + " " + page.sel.model).trim() || page.sel.name : ""
                color: Colors.fade(0.55)
                font.pixelSize: 12
                font.bold: true
                font.family: Properties.fontFamily
            }
            Text {
                text: {
                    if (!page.sel) return ""
                    const p = page.sel.physical
                    const inch = p && p[0] > 0 ? Math.round(Math.hypot(p[0], p[1]) / 25.4 * 10) / 10 + "\"  ·  " : ""
                    return page.sel.name + "  ·  " + inch + "at " + page.sel.x + ", " + page.sel.y
                }
                color: Colors.fade(0.35)
                font.pixelSize: 11
                font.family: Properties.fontFamily
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: rows.implicitHeight
            radius: 14
            color: Colors.card
            border.width: Properties.panelBorderWidth
            border.color: Properties.cardBorder

            ColumnLayout {
                id: rows
                width: parent.width
                spacing: 0

                PlainRow {
                    Layout.fillWidth: true
                    label: "Enabled"
                    desc: page.draft.filter(c => c.enabled).length <= 1 && page.sel?.enabled ? "The last screen can't be turned off" : ""
                    ToggleSwitch {
                        checked: page.sel?.enabled ?? false
                        enabled: !(page.sel?.enabled && page.draft.filter(c => c.enabled).length <= 1)
                        opacity: enabled ? 1 : 0.4
                        onToggled: v => {
                            if (v) {
                                // place it right of everything else
                                const on = page.draft.filter(c => c.enabled).map(c => page.rect(c))
                                const right = on.length ? Math.max(...on.map(r => r.x + r.w)) : 0
                                page.update(page.selected, { enabled: true, x: right, y: 0 })
                                page.settle(page.selected)
                            } else {
                                page.update(page.selected, { enabled: false })
                                page.settle(page.selected)
                            }
                        }
                    }
                }

                Divider {}
                PlainRow {
                    Layout.fillWidth: true
                    label: "Resolution"
                    enabled: page.sel?.enabled ?? false
                    opacity: enabled ? 1 : 0.4
                    DropdownControl {
                        options: {
                            if (!page.sel) return []
                            const seen = {}
                            const out = []
                            for (const m of page.sel.modes) {
                                const k = m.width + "x" + m.height
                                if (seen[k]) { if (m.is_preferred) seen[k].hint = "native"; continue }
                                seen[k] = { label: m.width + " × " + m.height, value: k, area: m.width * m.height, hint: m.is_preferred ? "native" : "" }
                                out.push(seen[k])
                            }
                            return out.sort((a, b) => b.area - a.area)
                        }
                        value: page.sel ? page.sel.width + "x" + page.sel.height : ""
                        onEdited: v => {
                            const [w, h] = v.split("x").map(Number)
                            const best = page.sel.modes.filter(m => m.width === w && m.height === h)
                                .reduce((a, b) => b.refresh_rate > a.refresh_rate ? b : a)
                            page.resize(page.selected, { width: w, height: h, refresh: best.refresh_rate })
                        }
                    }
                }

                Divider {}
                PlainRow {
                    Layout.fillWidth: true
                    label: "Refresh rate"
                    enabled: page.sel?.enabled ?? false
                    opacity: enabled ? 1 : 0.4
                    DropdownControl {
                        options: page.sel
                            ? page.sel.modes.filter(m => m.width === page.sel.width && m.height === page.sel.height)
                                .sort((a, b) => b.refresh_rate - a.refresh_rate)
                                .map(m => ({ label: (m.refresh_rate / 1000).toFixed(2) + " Hz", value: m.refresh_rate,
                                             hint: m.is_preferred ? "native" : "" }))
                            : []
                        value: page.sel?.refresh ?? 0
                        onEdited: v => page.update(page.selected, { refresh: v })
                    }
                }

                Divider {}
                PlainRow {
                    Layout.fillWidth: true
                    label: "Scale"
                    desc: "Bigger = everything larger, less space"
                    enabled: page.sel?.enabled ?? false
                    opacity: enabled ? 1 : 0.4
                    NumberControl {
                        from: 0.5
                        to: 3
                        step: 0.05
                        value: page.sel?.scale ?? 1
                        onEdited: v => page.resize(page.selected, { scale: Math.max(0.25, v) })
                    }
                }

                Divider {}
                PlainRow {
                    Layout.fillWidth: true
                    label: "Rotation"
                    enabled: page.sel?.enabled ?? false
                    opacity: enabled ? 1 : 0.4
                    ChoiceControl {
                        options: ["normal", "90", "180", "270"]
                        value: page.sel?.transform ?? "normal"
                        onEdited: v => page.resize(page.selected, { transform: v })
                    }
                }

                Divider { visible: page.sel?.vrrSupported ?? false }
                PlainRow {
                    Layout.fillWidth: true
                    visible: page.sel?.vrrSupported ?? false
                    label: "Variable refresh rate"
                    desc: "Adaptive sync (FreeSync / G-Sync compatible)"
                    enabled: page.sel?.enabled ?? false
                    opacity: enabled ? 1 : 0.4
                    ToggleSwitch {
                        checked: page.sel?.vrr ?? false
                        onToggled: v => page.update(page.selected, { vrr: v })
                    }
                }
            }
        }
    }

    // ── Actions ──────────────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 54
        radius: 14
        color: Monitors.pending ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.12) : Colors.card
        border.width: Properties.panelBorderWidth
        border.color: Monitors.pending ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.4) : Properties.cardBorder
        Behavior on color { ColorAnimation { duration: 150 } }

        // normal: forget / undo / apply
        RowLayout {
            anchors.fill: parent
            anchors.margins: 11
            anchors.leftMargin: 14
            spacing: 8
            visible: !Monitors.pending

            ActionButton {
                visible: Object.keys(Settings.monitors).length > 0
                icon: "󰆴"
                text: "Forget saved"
                onClicked: Monitors.forget()
            }
            Text {
                Layout.fillWidth: true
                text: page.edited ? "Not applied yet" : Object.keys(Settings.monitors).length > 0 ? "Saved" : "Using output.kdl"
                color: Colors.fade(0.45)
                font.pixelSize: 11
                font.family: Properties.fontFamily
                horizontalAlignment: Text.AlignRight
            }
            ActionButton {
                visible: page.edited
                icon: "󰕌"
                text: "Undo"
                onClicked: page.load()
            }
            ActionButton {
                icon: Monitors.busy ? "󰔟" : "󰄬"
                text: "Apply"
                primary: page.edited
                interactive: page.edited && !Monitors.busy
                onClicked: { page.edited = false; Monitors.tryLive(page.draft) }
            }
        }

        // after applying: keep or revert
        RowLayout {
            anchors.fill: parent
            anchors.margins: 11
            anchors.leftMargin: 14
            spacing: 8
            visible: Monitors.pending

            Text {
                Layout.fillWidth: true
                text: "Keep this display setup?  Reverting in " + Monitors.countdown + "s"
                color: Colors.ink
                font.pixelSize: 12
                font.bold: true
                font.family: Properties.fontFamily
            }
            ActionButton {
                icon: "󰕌"
                text: "Revert"
                onClicked: Monitors.revert()
            }
            ActionButton {
                icon: "󰄬"
                text: "Keep"
                primary: true
                onClicked: Monitors.keep()
            }
        }
    }

    component Divider: Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 16
        Layout.rightMargin: 16
        implicitHeight: 1
        color: Colors.fade(0.06)
    }

    // ── Identify: big name on every screen for a moment ──────────────────────
    Timer { id: identifyTimer; interval: 2500; onTriggered: page.identifying = false }

    LazyLoader {
        active: page.identifying
        Variants {
            model: Quickshell.screens
            PanelWindow {
                required property var modelData
                screen: modelData
                color: "transparent"
                implicitWidth: 340
                implicitHeight: 150
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "quickshell"

                Rectangle {
                    anchors.fill: parent
                    radius: Properties.panelRadius
                    color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.92)
                    border.width: 2
                    border.color: Colors.color6
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.name
                            color: Colors.ink
                            font.pixelSize: 44
                            font.bold: true
                            font.family: Properties.fontFamily
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.model
                            color: Colors.fade(0.6)
                            font.pixelSize: 13
                            font.family: Properties.fontFamily
                        }
                    }
                }
            }
        }
    }
}
