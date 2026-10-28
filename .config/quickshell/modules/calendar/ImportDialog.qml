import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "../settings"
import "CalUtil.js" as U

// Import .ics files: exports of Apple Calendar, Google (also Takeout's .zip),
// Outlook, Thunderbird, …, or a single invite. Read → preview + options →
// importing → done (with undo). Opened from the sidebar, by dropping files on
// the window, or `qs ipc call calendar importFile <path>` (the .desktop entry
// passes .ics files opened from a file manager).
Modal {
    id: root

    cardWidth: 560
    keepOpen: step === 2

    property int step: 0              // 0 reading, 1 preview, 2 importing, 3 done
    property var paths: []
    property var info: null           // calsync import-read
    property string error: ""

    property string target: ""        // calendar id, or "new" (new local calendar(s))
    property string fName: ""
    property string duplicates: "skip"
    property bool upcomingOnly: false
    property bool alarms: true

    property int done: 0
    property int total: 0
    property var result: null
    property string resultCal: ""     // the calendar it went into (undo)
    property bool undone: false

    signal showDate(date day)

    readonly property bool busy: step === 0 || step === 2
    readonly property var sources: info?.sources ?? []
    readonly property int count: info ? (upcomingOnly ? info.upcoming : info.total) : 0
    readonly property int past: info ? info.total - info.upcoming : 0
    readonly property int otherItems: sources.reduce((n, s) => n + s.other, 0)
    readonly property bool invite: sources.some(s => s.invite)
    readonly property var targetCal: CalendarStore.calendarMap[target]

    function pick() {
        Jobs.run(["zenity", "--file-selection", "--multiple", "--separator=\n", "--title=Import calendar files",
                  "--filename=" + Quickshell.env("HOME") + "/",
                  "--file-filter=Calendars (.ics, .zip) | *.ics *.ICS *.ical *.icalendar *.ifb *.vcs *.zip",
                  "--file-filter=All files | *"], (code, out) => {
            const p = out.split("\n").filter(x => x.trim() !== "")
            if (code === 0 && p.length > 0) root.openFiles(p)
            else if (code !== 1) CalendarStore.lastError = code === 127 ? "zenity isn't installed: " + Jobs.installHint("zenity")
                                                                        : "couldn't open the file picker"
        })
    }

    function openFiles(p) {
        if (step === 2) { shake(); return }
        paths = p.map(x => String(x).replace(/^file:\/\//, "")).map(x => decodeURIComponent(x))
        step = 0; info = null; error = ""; result = null; undone = false
        open()
        CalendarStore.readImport(paths, res => {
            if (!root.shown || root.step !== 0) return
            if (!res.ok) { root.error = res.error; root.step = 1; return }
            root.info = res
            root.fName = res.sources.length === 1 ? (res.sources[0].name || res.sources[0].label.replace(/\.[^.]+$/, "")) : ""
            // most of an old export is history: start with only what's still coming
            root.upcomingOnly = res.upcoming > 0 && res.total - res.upcoming > 50
            root.duplicates = "skip"
            root.alarms = true
            // a calendar of the same name (exported from it), else the first one in use
            const w = CalendarStore.writableCalendars
            const named = res.sources.length === 1 && res.sources[0].name
                ? w.find(c => c.name.toLowerCase() === res.sources[0].name.toLowerCase()) : null
            root.target = res.sources.length > 1 ? "new"
                        : (named ?? w.find(c => c.enabled) ?? w[0])?.id ?? "new"
            root.step = 1
        })
    }

    function start() {
        const isNew = target === "new"
        const names = {}
        if (isNew && sources.length === 1 && fName.trim()) names[sources[0].label] = fName.trim()
        step = 2; done = 0; total = count; error = ""
        resultCal = isNew ? "" : target
        CalendarStore.importFiles({ paths: paths, calendar: target, newCalendars: isNew, names: names,
                                    duplicates: duplicates, upcomingOnly: upcomingOnly, alarms: alarms },
            (d, t) => { root.done = d; root.total = t },
            res => {
                if (!res.ok) { root.error = res.error; root.step = 1; return }
                root.result = res
                root.step = 3
            })
    }

    function undo() {
        CalendarStore.undoImport(resultCal, result.created, res => {
            if (res.ok) root.undone = true
            else root.error = res.error
        })
    }

    function monthYear(ms) { const d = new Date(ms); return U.monthNames[d.getMonth()].slice(0, 3) + " " + d.getFullYear() }
    function when(e) {
        return U.fmtShortDate(new Date(e.start)) + " " + new Date(e.start).getFullYear()
             + (e.allDay ? "" : "  ·  " + U.fmtTime(e.start) + " – " + U.fmtTime(e.end))
    }
    function plural(n, one, many) { return n + " " + (n === 1 ? one : many) }

    onClosed: if (step === 0) step = 1

    ColumnLayout {
        width: parent.width
        spacing: 14

        // ── Header ───────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                text: "󰋺"
                color: Colors.color6
                font.pixelSize: 20
                font.family: Properties.fontFamily
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: root.step === 3 ? (root.undone ? "Import undone" : "Imported") : "Import events"
                    color: Colors.ink
                    font.pixelSize: 17
                    font.bold: true
                    font.family: Properties.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    text: root.sources.length > 0 ? root.sources.map(s => s.name || s.label).join(", ")
                        : root.paths.map(p => p.split("/").pop()).join(", ")
                    color: Colors.fade(0.5)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                }
            }
            IconButton {
                implicitWidth: 30; implicitHeight: 30
                icon: "󰅖"
                interactive: root.step !== 2
                onClicked: root.close()
            }
        }

        // ── Reading ──────────────────────────────────────────────────────────
        Text {
            visible: root.step === 0
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            text: "󰔟  Reading the calendar…"
            color: Colors.fade(0.5)
            font.pixelSize: 12
            font.family: Properties.fontFamily
        }

        // ── Preview ──────────────────────────────────────────────────────────
        // numbers at a glance
        RowLayout {
            Layout.fillWidth: true
            visible: root.step === 1 && root.info !== null
            spacing: 8
            Stat { value: root.info?.total ?? 0; label: root.info?.total === 1 ? "event" : "events" }
            Stat { value: root.info?.recurring ?? 0; label: "repeating" }
            Stat { value: root.info?.upcoming ?? 0; label: "upcoming" }
            Stat {
                Layout.preferredWidth: 2
                text: root.info && root.info.total > 0
                    ? root.monthYear(root.info.first) + " – " + (root.info.forever ? "ongoing" : root.monthYear(root.info.last)) : "—"
                label: "span"
            }
        }

        // things worth knowing about the files
        Rectangle {
            Layout.fillWidth: true
            visible: root.step === 1 && notes.text !== ""
            implicitHeight: notes.implicitHeight + 20
            radius: 12
            color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.08)
            border.width: Properties.panelBorderWidth
            border.color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.25)
            Text {
                id: notes
                anchors.fill: parent
                anchors.margins: 10
                anchors.leftMargin: 14
                text: [
                    root.invite ? "󰇮  An invitation: this only adds it to your calendar, it doesn't answer the organizer." : "",
                    root.otherItems > 0 ? "󰄱  " + root.plural(root.otherItems, "task / note", "tasks / notes") + " left out — only events are imported." : "",
                    root.targetCal?.accountType === "graph" ? "󰴢  Microsoft 365 takes simple repeat rules only; changed or skipped single dates of a series aren't carried over." : ""
                ].filter(x => x).join("<br>")
                textFormat: Text.StyledText
                color: Colors.fade(0.75)
                font.pixelSize: 11
                font.family: Properties.fontFamily
                wrapMode: Text.WordWrap
                lineHeight: 1.15
            }
        }

        // a few of the events
        Rectangle {
            Layout.fillWidth: true
            visible: root.step === 1 && (root.info?.preview?.length ?? 0) > 0
            implicitHeight: prevCol.implicitHeight + 8
            radius: 14
            color: Colors.card
            border.width: Properties.panelBorderWidth
            border.color: Properties.cardBorder
            ColumnLayout {
                id: prevCol
                y: 4
                width: parent.width
                spacing: 0
                Repeater {
                    model: root.info?.preview ?? []
                    Item {
                        id: prevRow
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 40
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 14
                            spacing: 12
                            Rectangle {
                                Layout.preferredWidth: 4
                                Layout.preferredHeight: 22
                                radius: 2
                                color: root.targetCal?.color
                                    ?? (root.sources.find(s => s.label === prevRow.modelData.source)?.color || Colors.color6)
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: prevRow.modelData.title
                                    color: Colors.ink
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: Properties.fontFamily
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: root.when(prevRow.modelData) + (prevRow.modelData.location ? "  ·  " + prevRow.modelData.location : "")
                                    color: Colors.fade(0.5)
                                    font.pixelSize: 10
                                    font.family: Properties.fontFamily
                                    elide: Text.ElideRight
                                }
                            }
                            Text {
                                visible: prevRow.modelData.recurring
                                text: "󰑖"
                                color: Colors.fade(0.4)
                                font.pixelSize: 12
                                font.family: Properties.fontFamily
                            }
                        }
                    }
                }
                Text {
                    visible: (root.info?.total ?? 0) > (root.info?.preview?.length ?? 0)
                    Layout.leftMargin: 32
                    Layout.bottomMargin: 8
                    text: "and " + ((root.info?.total ?? 0) - (root.info?.preview?.length ?? 0)) + " more"
                    color: Colors.fade(0.4)
                    font.pixelSize: 10
                    font.family: Properties.fontFamily
                }
            }
        }

        // where to and how
        Rectangle {
            Layout.fillWidth: true
            visible: root.step === 1 && root.info !== null
            implicitHeight: opts.implicitHeight
            radius: 14
            color: Colors.card
            border.width: Properties.panelBorderWidth
            border.color: Properties.cardBorder
            ColumnLayout {
                id: opts
                width: parent.width
                spacing: 0
                FormRow {
                    label: "Into"
                    DropdownControl {
                        implicitWidth: 260
                        options: CalendarStore.writableCalendars
                            .map(c => ({ label: c.name, value: c.id, hint: c.accountName, color: c.color }))
                            .concat([{ label: root.sources.length > 1 ? "New calendars (one per file)" : "New calendar",
                                       value: "new", hint: "On this computer",
                                       color: root.sources[0]?.color || Colors.color6 }])
                        value: root.target
                        onEdited: v => root.target = v
                    }
                }
                FormRow {
                    visible: root.target === "new" && root.sources.length === 1
                    label: "Name"
                    SearchField {
                        implicitWidth: 260
                        icon: "󰑕"
                        placeholderText: "Calendar name"
                        text: root.fName
                        onTextEdited: root.fName = text
                    }
                }
                FormRow {
                    label: "Only upcoming"
                    hint: root.past > 0 ? "Leaves out " + root.plural(root.past, "past event", "past events") : "Nothing in the past"
                    ToggleSwitch {
                        checked: root.upcomingOnly
                        onToggled: v => root.upcomingOnly = v
                    }
                }
                FormRow {
                    label: "Reminders"
                    hint: "Keep the alerts set in the file"
                    ToggleSwitch {
                        checked: root.alarms
                        onToggled: v => root.alarms = v
                    }
                }
                FormRow {
                    label: "Already there"
                    hint: root.duplicates === "skip" ? "Leave the calendar's copy"
                        : root.duplicates === "replace" ? "Overwrite with the file's version" : "Add them a second time"
                    ChoiceControl {
                        options: ["skip", "replace", "copy"]
                        value: root.duplicates
                        onEdited: v => root.duplicates = v
                    }
                }
            }
        }

        // ── Importing ────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.step === 2
            spacing: 8
            Text {
                text: root.total > 0 ? "Importing " + root.done + " of " + root.total + "…" : "Importing…"
                color: Colors.fade(0.7)
                font.pixelSize: 12
                font.family: Properties.fontFamily
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 8
                radius: 4
                color: Colors.fade(0.08)
                Rectangle {
                    width: parent.width * (root.total > 0 ? root.done / root.total : 0)
                    height: parent.height
                    radius: 4
                    color: Colors.color6
                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }
            }
        }

        // ── Done ─────────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            visible: root.step === 3 && root.result !== null
            implicitHeight: doneCol.implicitHeight + 28
            radius: 14
            color: Colors.card
            border.width: Properties.panelBorderWidth
            border.color: Properties.cardBorder
            ColumnLayout {
                id: doneCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 16
                spacing: 6
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.undone ? "󰕌" : (root.result?.failed?.length ?? 0) > 0 ? "󰀦" : "󰄬"
                    color: root.undone ? Colors.fade(0.5) : (root.result?.failed?.length ?? 0) > 0 ? Colors.color3 : Colors.color6
                    font.pixelSize: 28
                    font.family: Properties.fontFamily
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.undone ? "The imported events were taken out again"
                        : root.plural(root.result?.imported ?? 0, "event", "events") + " imported"
                          + ((root.result?.newCalendars?.length ?? 0) > 0
                             ? " into " + root.plural(root.result.newCalendars.length, "new calendar", "new calendars")
                             : root.targetCal ? " into " + root.targetCal.name : "")
                    color: Colors.ink
                    font.pixelSize: 14
                    font.bold: true
                    font.family: Properties.fontFamily
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    visible: text !== "" && !root.undone
                    text: [
                        (root.result?.replaced ?? 0) > 0 ? root.result.replaced + " replaced" : "",
                        (root.result?.skipped ?? 0) > 0 ? root.result.skipped + " already there, skipped" : "",
                        (root.result?.simplified ?? 0) > 0 ? root.result.simplified + " series without their exceptions" : ""
                    ].filter(x => x).join("  ·  ")
                    color: Colors.fade(0.5)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    visible: (root.result?.failed?.length ?? 0) > 0 && !root.undone
                    readonly property var f: root.result?.failed ?? []
                    text: root.plural(f.length, "event", "events") + " couldn't be imported:\n"
                        + f.slice(0, 5).join("\n") + (f.length > 5 ? "\n…and " + (f.length - 5) + " more" : "")
                    color: Colors.red
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.error !== ""
            text: root.error
            color: Colors.red
            font.pixelSize: 11
            font.family: Properties.fontFamily
            wrapMode: Text.WordWrap
        }

        // ── Buttons ──────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            visible: root.step !== 0
            spacing: 8
            ActionButton {
                visible: root.step === 1
                icon: "󰈔"
                text: "Other files…"
                onClicked: root.pick()
            }
            ActionButton {
                visible: root.step === 3 && !root.undone && root.resultCal !== "" && (root.result?.created?.length ?? 0) > 0
                icon: "󰕌"
                text: CalendarStore.working ? "Undoing…" : "Undo"
                interactive: !CalendarStore.working
                onClicked: root.undo()
            }
            Item { Layout.fillWidth: true }
            ActionButton {
                visible: root.step === 1 || root.step === 2
                text: root.step === 2 ? "Stop" : "Cancel"
                onClicked: root.step === 2 ? CalendarStore.cancelImport() : root.close()
            }
            ActionButton {
                visible: root.step === 1
                icon: "󰋺"
                text: root.count > 0 ? "Import " + root.plural(root.count, "event", "events") : "Import"
                primary: true
                interactive: root.info !== null && root.count > 0 && root.target !== ""
                onClicked: root.start()
            }
            ActionButton {
                visible: root.step === 3 && !root.undone && (root.result?.first ?? 0) > 0
                icon: "󰃭"
                text: "Show"
                onClicked: { root.showDate(U.dayStart(new Date(root.result.first))); root.close() }
            }
            ActionButton {
                visible: root.step === 3
                icon: "󰄬"
                text: "Done"
                primary: true
                onClicked: root.close()
            }
        }
    }

    component Stat: Rectangle {
        id: stat
        property int value: 0
        property string text: String(value)
        property string label: ""
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 58
        radius: 14
        color: Colors.card
        border.width: Properties.panelBorderWidth
        border.color: Properties.cardBorder
        ColumnLayout {
            anchors.centerIn: parent
            width: parent.width - 16
            spacing: 0
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: parent.width
                text: stat.text
                color: Colors.ink
                font.pixelSize: 16
                font.bold: true
                font.family: Properties.fontFamily
                elide: Text.ElideRight
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: stat.label.toUpperCase()
                color: Colors.fade(0.4)
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 1.2
                font.family: Properties.fontFamily
            }
        }
    }

    component FormRow: Item {
        id: formRow
        property string label: ""
        property string hint: ""
        default property alias content: slot.data
        Layout.fillWidth: true
        implicitHeight: visible ? (hint ? 56 : 50) : 0
        ColumnLayout {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: slot.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
                text: formRow.label
                color: Colors.ink
                font.pixelSize: 13
                font.bold: true
                font.family: Properties.fontFamily
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: formRow.hint
                color: Colors.fade(0.45)
                font.pixelSize: 10
                font.family: Properties.fontFamily
                elide: Text.ElideRight
            }
        }
        RowLayout {
            id: slot
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
        }
    }
}
