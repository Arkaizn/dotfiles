import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import "../settings"

// Process table of the performance monitor: sortable columns (click a header;
// again = other direction), a filter (all / top CPU / top memory), search by
// name, PID or command, and an options popover whose choices are kept in
// Settings.perfmon (also on the settings app's Performance monitor page).
// Data: PerfMon.procs, rescanned every few seconds while the window is open.
PerfCard {
    id: root

    // ── preferences (Settings.perfmon) ──────────────────────────────────────
    readonly property var prefs: Settings.perfmon
    readonly property string defaultSort: ["cpu", "memory", "name", "pid"].includes(prefs.procSort) ? prefs.procSort : "cpu"
    readonly property bool defaultDesc: (prefs.procOrder ?? "descending") !== "ascending"
    readonly property int limit: Math.max(5, Math.min(100, prefs.procLimit ?? 15))
    readonly property bool showMemPct: prefs.procMemPct === true
    readonly property bool showUser: prefs.procUser === true
    readonly property bool showCmd: prefs.procCommand ?? true
    readonly property bool showKernel: prefs.procKernel === true

    // ── this window's state ─────────────────────────────────────────────────
    property string sortKey: defaultSort
    property bool desc: defaultDesc
    property string filter: "all"           // all | cpu | memory
    property alias query: search.text

    function sortBy(k) {
        if (sortKey === k) desc = !desc
        else { sortKey = k; desc = k === "cpu" || k === "memory" }
    }
    function setPref(key, value, def) {
        if (value === def) Settings.reset("perfmon", key)
        else Settings.set("perfmon", key, value)
    }

    readonly property var rows: {
        let list = PerfMon.procs
        if (!showKernel) list = list.filter(p => !p.kernel)
        const q = query.trim().toLowerCase()
        if (q !== "")
            list = list.filter(p => p.name.toLowerCase().includes(q) || String(p.pid).startsWith(q)
                                 || (showCmd && p.cmd.toLowerCase().includes(q)))
        if (filter === "cpu") list = list.slice().sort((a, b) => b.cpu - a.cpu).slice(0, limit)
        else if (filter === "memory") list = list.slice().sort((a, b) => b.mem - a.mem).slice(0, limit)
        const k = sortKey, d = desc ? -1 : 1
        const cmp = k === "name" ? (a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: "base" })
                  : k === "pid" ? (a, b) => a.pid - b.pid
                  : k === "memory" ? (a, b) => a.mem - b.mem
                  : (a, b) => a.cpu - b.cpu
        return list.slice().sort((a, b) => d * cmp(a, b) || a.pid - b.pid)
    }
    // the rows go into a ListModel in place: the view keeps its delegates and
    // scroll position when a scan arrives (a new array would rebuild all of it)
    onRowsChanged: {
        const r = rows
        for (let i = 0; i < r.length; i++) {
            const e = { pid: r[i].pid, name: r[i].name, cpu: r[i].cpu, mem: r[i].mem, user: r[i].user, cmd: r[i].cmd }
            if (i < procModel.count) procModel.set(i, e); else procModel.append(e)
        }
        if (procModel.count > r.length) procModel.remove(r.length, procModel.count - r.length)
    }
    ListModel { id: procModel }

    readonly property int wPid: 64
    readonly property int wUser: 96
    readonly property int wCpu: 64
    readonly property int wMem: showMemPct ? 132 : 84

    title: "Processes"
    icon: "󰉹"
    note: PerfMon.procs.length === 0 ? "" : rows.length + " of " + PerfMon.procs.length
        + (filter !== "all" ? "  ·  top " + limit + " by " + (filter === "cpu" ? "CPU" : "memory") : "")

    actions: [
        ChoiceControl {
            options: ["All", "Top CPU", "Top memory"]
            value: ({ all: "All", cpu: "Top CPU", memory: "Top memory" })[root.filter]
            onEdited: v => root.filter = ({ "All": "all", "Top CPU": "cpu", "Top memory": "memory" })[v]
        },
        SearchField {
            id: search
            Layout.preferredWidth: 200
            implicitHeight: Properties.buttonHeight
            placeholderText: "Search  (Ctrl+F)"
            Keys.onEscapePressed: { text = ""; focus = false }
        },
        IconButton {
            id: optionsButton
            icon: "󰒓"
            tooltip: "Process table options"
            active: options.visible
            onClicked: options.visible ? options.close() : options.open()
        }
    ]
    function focusSearch() { search.forceActiveFocus(); search.selectAll() }

    // ── header ──────────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 10
        Layout.rightMargin: 10
        spacing: 12
        SortHeader { key: "name"; label: "Name"; Layout.fillWidth: !root.showCmd; Layout.preferredWidth: root.showCmd ? 190 : 1 }
        SortHeader { key: "pid"; label: "PID"; numeric: true; Layout.preferredWidth: root.wPid }
        HeaderText { visible: root.showUser; text: "User"; Layout.preferredWidth: root.wUser }
        SortHeader { key: "cpu"; label: "CPU"; numeric: true; Layout.preferredWidth: root.wCpu }
        SortHeader { key: "memory"; label: "Memory"; numeric: true; Layout.preferredWidth: root.wMem }
        HeaderText { visible: root.showCmd; text: "Command"; Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.leftMargin: 6 }
    }
    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Colors.fade(0.08); Layout.topMargin: -4 }

    // ── rows ────────────────────────────────────────────────────────────────
    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 160
        Layout.topMargin: -4
        clip: true
        model: procModel
        boundsBehavior: Flickable.StopAtBounds
        reuseItems: true
        ScrollBar.vertical: ScrollBar { policy: list.contentHeight > list.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

        delegate: Rectangle {
            id: row
            required property int index
            required property int pid
            required property string name
            required property real cpu
            required property real mem
            required property string user
            required property string cmd
            width: ListView.view.width
            height: 30
            radius: Properties.radius
            color: rowHover.hovered ? Colors.fade(0.06) : index % 2 ? Colors.fade(0.022) : "transparent"
            HoverHandler { id: rowHover }

            RowLayout {
                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                spacing: 12
                // elided cells sit in plain Items: a long text's implicit width would skew the row
                Item {
                    Layout.fillWidth: !root.showCmd
                    Layout.preferredWidth: root.showCmd ? 190 : 1
                    implicitHeight: nameCell.implicitHeight
                    Cell { id: nameCell; width: parent.width; text: row.name; color: Colors.ink }
                }
                Cell { text: row.pid; numeric: true; dim: true; Layout.preferredWidth: root.wPid }
                Cell { visible: root.showUser; text: row.user; dim: true; Layout.preferredWidth: root.wUser }
                Cell {
                    Layout.preferredWidth: root.wCpu
                    numeric: true
                    text: row.cpu < 0 ? "–" : row.cpu < 0.05 ? "0" : row.cpu.toFixed(1) + "%"
                    color: row.cpu >= 50 ? Colors.red : row.cpu >= 20 ? Colors.yellow : row.cpu < 0.05 ? Colors.fade(0.4) : Colors.ink
                }
                Item {
                    Layout.preferredWidth: root.wMem
                    implicitHeight: memText.implicitHeight
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        Text {
                            id: memText
                            text: PerfMon.ibytes(row.mem)
                            color: row.mem < 1048576 ? Colors.fade(0.4) : Colors.ink
                            font.pixelSize: 12
                            font.family: Properties.fontFamily
                        }
                        Text {
                            visible: root.showMemPct
                            width: 40
                            horizontalAlignment: Text.AlignRight
                            text: PerfMon.memTotal > 0 ? (100 * row.mem / (PerfMon.memTotal * 1024)).toFixed(1) + "%" : ""
                            color: Colors.fade(0.4)
                            font.pixelSize: 11
                            font.family: Properties.fontFamily
                        }
                    }
                }
                Item {
                    visible: root.showCmd
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.leftMargin: 6
                    implicitHeight: cmdCell.implicitHeight
                    Cell { id: cmdCell; width: parent.width; text: row.cmd; dim: true }
                }
            }
        }

        // empty states
        Column {
            anchors.centerIn: parent
            visible: list.count === 0
            spacing: 6
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: PerfMon.procs.length === 0 ? "󰉹" : "󰍉"
                color: Colors.fade(0.25)
                font.pixelSize: 26
                font.family: Properties.fontFamily
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: PerfMon.procs.length === 0 ? "Reading processes…" : "No process matches “" + root.query.trim() + "”"
                color: Colors.fade(0.45)
                font.pixelSize: 12
                font.family: Properties.fontFamily
            }
        }
    }

    // ── options popover ─────────────────────────────────────────────────────
    Popup {
        id: options
        parent: optionsButton
        x: optionsButton.width - width
        y: optionsButton.height + 6
        width: 330
        padding: 14
        closePolicy: Popup.CloseOnPressOutsideParent | Popup.CloseOnEscape   // the button itself toggles it

        background: Rectangle {
            radius: Properties.radius + 4
            color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 1)
            border.width: Properties.panelBorderWidth
            border.color: Properties.panelBorder
        }

        contentItem: ColumnLayout {
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: "Process table"; color: Colors.ink; font.pixelSize: 13; font.bold: true; font.family: Properties.fontFamily }
                IconButton {
                    implicitWidth: 26; implicitHeight: 26; iconSize: 12
                    icon: "󰦛"
                    tooltip: "Back to the defaults"
                    onClicked: { for (const k of ["procSort", "procOrder", "procLimit", "procMemPct", "procUser", "procCommand", "procKernel"]) Settings.reset("perfmon", k) }
                }
            }

            OptionLabel { text: "SORT BY DEFAULT" }
            ChoiceControl {
                options: ["CPU", "Memory", "Name", "PID"]
                value: ({ cpu: "CPU", memory: "Memory", name: "Name", pid: "PID" })[root.defaultSort]
                onEdited: v => {
                    const k = v === "PID" ? "pid" : v.toLowerCase()
                    root.setPref("procSort", k, "cpu")
                    root.sortKey = k
                }
            }
            ChoiceControl {
                options: ["Descending", "Ascending"]
                value: root.defaultDesc ? "Descending" : "Ascending"
                onEdited: v => {
                    root.setPref("procOrder", v.toLowerCase(), "descending")
                    root.desc = v === "Descending"
                }
            }

            OptionLabel { text: "TOP CPU / MEMORY SHOW" }
            RowLayout {
                spacing: 6
                IconButton { icon: "󰍴"; implicitWidth: 28; implicitHeight: 28; iconSize: 12; interactive: root.limit > 5
                             onClicked: root.setPref("procLimit", Math.max(5, root.limit - 5), 15) }
                Text {
                    Layout.preferredWidth: 90
                    horizontalAlignment: Text.AlignHCenter
                    text: root.limit + " processes"
                    color: Colors.ink
                    font.pixelSize: 12
                    font.family: Properties.fontFamily
                }
                IconButton { icon: "󰐕"; implicitWidth: 28; implicitHeight: 28; iconSize: 12; interactive: root.limit < 100
                             onClicked: root.setPref("procLimit", Math.min(100, root.limit + 5), 15) }
            }

            OptionLabel { text: "COLUMNS" }
            OptionToggle { label: "Memory as % of RAM too"; checked: root.showMemPct; onToggled: v => root.setPref("procMemPct", v, false) }
            OptionToggle { label: "User"; checked: root.showUser; onToggled: v => root.setPref("procUser", v, false) }
            OptionToggle { label: "Command line"; checked: root.showCmd; onToggled: v => root.setPref("procCommand", v, true) }
            OptionToggle { label: "Kernel threads"; checked: root.showKernel; onToggled: v => root.setPref("procKernel", v, false) }
        }
    }

    // ── pieces ──────────────────────────────────────────────────────────────
    component HeaderText: Text {
        color: Colors.fade(0.45)
        font.pixelSize: 11
        font.bold: true
        font.family: Properties.fontFamily
        elide: Text.ElideRight
    }
    component SortHeader: Item {
        id: sh
        property string key
        property string label
        property bool numeric: false
        readonly property bool current: root.sortKey === key
        implicitHeight: 22
        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: sh.numeric ? parent.right : undefined
            spacing: 4
            Text {
                text: sh.label
                color: sh.current ? Colors.color6 : shMouse.containsMouse ? Colors.fade(0.75) : Colors.fade(0.45)
                font.pixelSize: 11
                font.bold: true
                font.family: Properties.fontFamily
            }
            Text {
                text: sh.current ? (root.desc ? "󰅀" : "󰅃") : ""
                color: Colors.color6
                font.pixelSize: 12
                font.family: Properties.fontFamily
            }
        }
        MouseArea {
            id: shMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.sortBy(sh.key)
        }
    }
    component Cell: Text {
        property bool numeric: false
        property bool dim: false
        horizontalAlignment: numeric ? Text.AlignRight : Text.AlignLeft
        color: dim ? Colors.fade(0.5) : Colors.ink
        font.pixelSize: 12
        font.family: Properties.fontFamily
        elide: Text.ElideRight
        maximumLineCount: 1
    }
    component OptionLabel: Text {
        Layout.topMargin: 4
        color: Colors.fade(0.4)
        font.pixelSize: 10
        font.bold: true
        font.letterSpacing: 1.2
        font.family: Properties.fontFamily
    }
    component OptionToggle: RowLayout {
        id: ot
        property string label
        property bool checked
        signal toggled(bool value)
        Layout.fillWidth: true
        Text { Layout.fillWidth: true; text: ot.label; color: Colors.fade(0.8); font.pixelSize: 12; font.family: Properties.fontFamily }
        ToggleSwitch { checked: ot.checked; onToggled: v => ot.toggled(v) }
    }
}
