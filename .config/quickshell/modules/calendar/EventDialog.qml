import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import "../settings"
import "CalUtil.js" as U

// Event details, and the editor for new / existing events.
//   showEvent(ev)            details (edit / delete from there)
//   create(start, allDay)    editor for a new event
Modal {
    id: root

    cardWidth: 500

    property var ev: null           // event being shown / edited (null = new)
    property bool editing: false
    property string error: ""
    property bool confirmDelete: false

    // editor fields
    property string fTitle: ""
    property string fCalendar: ""
    property bool fAllDay: false
    property date fStartDay: new Date()
    property int fStartMin: 540
    property date fEndDay: new Date()
    property int fEndMin: 600
    property string fLocation: ""
    property string fNotes: ""

    // repeat: none | daily | weekly | monthly | yearly | custom (a rule the
    // editor can't show — kept as it is unless another option is picked)
    property string rFreq: "none"
    property int rInterval: 1
    property var rDays: []                 // weekly: ["MO", "WE", …]
    property string rEnd: "never"          // never | after | until
    property int rCount: 10
    property date rUntil: new Date()
    property string rOriginal: ""          // the event's rule when the editor opened

    readonly property var dayCodes: ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

    function parseRule(rule) {
        rOriginal = rule || ""
        rFreq = "none"; rInterval = 1; rDays = []; rEnd = "never"; rCount = 10
        rUntil = U.addMonths(fStartDay, 3)
        if (!rule) return
        const m = {}
        for (const part of rule.split(";")) { const [k, v] = part.split("="); if (k) m[k.toUpperCase()] = v ?? "" }
        const simple = ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"].includes(m.FREQ)
            && Object.keys(m).every(k => ["FREQ", "INTERVAL", "BYDAY", "COUNT", "UNTIL", "WKST"].includes(k))
            && (!m.BYDAY || (m.FREQ === "WEEKLY" && /^(MO|TU|WE|TH|FR|SA|SU)(,(MO|TU|WE|TH|FR|SA|SU))*$/.test(m.BYDAY)))
        if (!simple) { rFreq = "custom"; return }
        rFreq = m.FREQ.toLowerCase()
        rInterval = parseInt(m.INTERVAL || "1") || 1
        rDays = m.BYDAY ? m.BYDAY.split(",") : []
        if (m.COUNT) { rEnd = "after"; rCount = parseInt(m.COUNT) || 1 }
        else if (m.UNTIL) {
            rEnd = "until"
            const u = m.UNTIL
            rUntil = new Date(+u.slice(0, 4), +u.slice(4, 6) - 1, +u.slice(6, 8))
        }
    }

    function buildRule() {
        if (rFreq === "custom") return rOriginal
        if (rFreq === "none") return ""
        const parts = ["FREQ=" + rFreq.toUpperCase()]
        if (rInterval > 1) parts.push("INTERVAL=" + rInterval)
        if (rFreq === "weekly" && rDays.length > 0)
            parts.push("BYDAY=" + dayCodes.filter(d => rDays.includes(d)).join(","))
        if (rEnd === "after") parts.push("COUNT=" + rCount)
        else if (rEnd === "until") {
            const u = new Date(rUntil)
            if (fAllDay) parts.push("UNTIL=" + u.getFullYear() + U.pad(u.getMonth() + 1) + U.pad(u.getDate()))
            else {
                u.setHours(23, 59, 59, 0)     // through the end of that day, written in UTC
                parts.push("UNTIL=" + u.getUTCFullYear() + U.pad(u.getUTCMonth() + 1) + U.pad(u.getUTCDate())
                           + "T" + U.pad(u.getUTCHours()) + U.pad(u.getUTCMinutes()) + U.pad(u.getUTCSeconds()) + "Z")
            }
        }
        return parts.join(";")
    }

    function setFreq(f) {
        rFreq = f
        if (f === "weekly" && rDays.length === 0) rDays = [dayCodes[U.weekday(fStartDay)]]
    }

    function toggleDay(code) {
        const has = rDays.includes(code)
        if (has && rDays.length === 1) return      // keep at least one day
        rDays = has ? rDays.filter(d => d !== code) : rDays.concat([code])
    }

    readonly property string unit: ({ daily: "day", weekly: "week", monthly: "month", yearly: "year" })[rFreq] ?? ""

    // what the editor started with, to know if there's anything to lose
    property string formAtStart: ""
    function formState() {
        return JSON.stringify([fTitle, fCalendar, fAllDay, fStartDay, fStartMin, fEndDay, fEndMin, fLocation, fNotes,
                               rFreq, rInterval, rDays, rEnd, rCount, rUntil])
    }
    readonly property bool dirty: editing && formState() !== formAtStart
    keepOpen: dirty

    // details ↔ editor: cross-fade
    onEditingChanged: if (shown) swap.restart()

    readonly property var cal: ev ? CalendarStore.calendarMap[ev.calendar] : null
    readonly property bool writable: cal !== null && cal !== undefined && !cal.readOnly
    readonly property color calColor: (editing ? CalendarStore.calendarMap[fCalendar]?.color : cal?.color) ?? Colors.color6

    function showEvent(e) {
        ev = e
        editing = false
        error = ""
        confirmDelete = false
        open()
    }

    function create(start, allDay, end) {
        ev = null
        askScope = false
        scope = ""
        const e = end ? end.getTime() : start.getTime() + (allDay ? 86400000 : 3600000)
        fillForm({ title: "", start: start.getTime(), end: e, allDay: allDay,
                   location: "", description: "", calendar: "" })
        editing = true
        error = ""
        open()
        titleField.forceActiveFocus()
    }

    // which = "this" (only this occurrence) | "all" (the series) | "" (not a series)
    property string editScope: ""
    function edit(which) {
        fillForm(ev)
        editing = true
        error = ""
        askScope = false
        scope = ""
        editScope = ev && ev.recurring ? (which || "") : ""
    }

    function fillForm(e) {
        const s = new Date(e.start), en = new Date(e.end)
        fTitle = e.title === "(No title)" ? "" : e.title
        fCalendar = e.calendar || (CalendarStore.writableCalendars.find(c => c.enabled) ?? CalendarStore.writableCalendars[0])?.id || ""
        fAllDay = e.allDay
        fStartDay = U.dayStart(s)
        fStartMin = s.getHours() * 60 + s.getMinutes()
        // all-day ends are exclusive; the editor shows the last day
        fEndDay = e.allDay ? U.addDays(U.dayStart(en), en.getTime() > s.getTime() ? -1 : 0) : U.dayStart(en)
        fEndMin = en.getHours() * 60 + en.getMinutes()
        fLocation = e.location ?? ""
        fNotes = e.description ?? ""
        parseRule(e.rrule ?? "")
        formAtStart = formState()
    }

    function at(day, mins) { const d = new Date(day); d.setHours(0, mins, 0, 0); return d.getTime() }

    property bool askScope: false        // the "only this / all" question is showing
    property string scope: ""            // answer for the save in progress
    function saveAs(sc) { scope = sc; save() }

    function save() {
        let start, end
        if (fAllDay) {
            start = U.dayStart(fStartDay).getTime()
            end = U.addDays(U.dayStart(fEndDay), 1).getTime()
        } else {
            start = at(fStartDay, fStartMin)
            end = at(fEndDay, fEndMin)
        }
        if (end <= start) { error = "The end has to be after the start"; return }
        if (!fCalendar) { error = "Pick a calendar"; return }
        const payload = Object.assign({}, ev ?? {}, {
            title: fTitle.trim() || "(No title)", start: start, end: end, allDay: fAllDay,
            location: fLocation.trim(), description: fNotes
        })
        // only touch the repeat rule when it was changed here
        const rule = buildRule()
        if (rule !== rOriginal) payload.setRrule = rule
        // a series: this occurrence or all of them? (a new repeat rule is always for all)
        if (editScope !== "") scope = editScope === "this" && rule === rOriginal ? "this" : "all"
        if (ev && ev.recurring && scope === "" && rule === rOriginal && fCalendar === ev.calendar) {
            askScope = true
            return
        }
        payload.scope = scope || "all"
        askScope = false
        scope = ""
        error = ""
        CalendarStore.saveEvent(payload, fCalendar, res => {
            if (res.ok) root.close()
            else root.error = res.error
        })
    }

    // "In 3 days", "Tomorrow", "Today · in 2 h", "Now · ends in 20 min", "2 days ago"
    function countdownText(e) {
        const now = Date.now()
        const today = U.dayStart(new Date())
        const day = U.dayStart(new Date(e.start))
        const days = Math.round((day - today) / 86400000)
        const span = ms => { const m = Math.round(Math.abs(ms) / 60000); return m < 60 ? m + " min" : Math.round(m / 60) + " h" }
        if (e.start <= now && e.end > now) return e.allDay ? "Today" : "Now · ends in " + span(e.end - now)
        if (days === 0) return e.allDay ? "Today" : e.start > now ? "Today · in " + span(e.start - now) : "Today · " + span(now - e.end) + " ago"
        if (days === 1) return "Tomorrow"
        if (days === -1) return "Yesterday"
        if (days > 1) return days < 14 ? "In " + days + " days" : days < 60 ? "In " + Math.round(days / 7) + " weeks" : "In " + Math.round(days / 30) + " months"
        return -days < 14 ? -days + " days ago" : -days < 60 ? Math.round(-days / 7) + " weeks ago" : Math.round(-days / 30) + " months ago"
    }

    function durationText(e) {
        if (e.allDay) {
            const d = Math.max(1, Math.round((e.end - e.start) / 86400000))
            return d === 1 ? "1 day" : d + " days"
        }
        const m = Math.round((e.end - e.start) / 60000)
        if (m >= 24 * 60) return Math.round(m / 1440 * 10) / 10 + " days"
        const h = Math.floor(m / 60), mi = m % 60
        return h === 0 ? mi + " min" : mi === 0 ? h + " h" : h + " h " + mi + " min"
    }

    function reminderText(e) {
        if (!CalendarStore.remindersOn) return "Reminders off"
        if (CalendarStore.calendarMap[e.calendar]?.notify === false) return "Off for this calendar"
        const times = CalendarStore.reminderTimes(e)
        if (times.length === 0) return "None"
        return times.map(t => {
            const m = Math.round((e.start - t) / 60000)
            if (e.allDay && !(e.alarms && e.alarms.length)) return "09:00 on the day"
            return m === 0 ? "At start" : m < 0 ? (-m) + " min after start" : m % 60 === 0 && m >= 60 ? (m / 60) + " h before" : m + " min before"
        }).join(", ")
    }

    // "Every 2 weeks on Mon, Wed · 10 times"
    function ruleText(rule) {
        if (!rule) return "Repeats"
        const m = {}
        for (const part of rule.split(";")) { const [k, v] = part.split("="); if (k) m[k.toUpperCase()] = v ?? "" }
        const unitName = ({ DAILY: "day", WEEKLY: "week", MONTHLY: "month", YEARLY: "year" })[m.FREQ]
        if (!unitName) return "Repeats"
        const n = parseInt(m.INTERVAL || "1")
        let t = n > 1 ? "Every " + n + " " + unitName + "s" : "Every " + unitName
        if (m.BYDAY && m.FREQ === "WEEKLY")
            t += " on " + m.BYDAY.split(",").map(d => U.dayShort[dayCodes.indexOf(d)] ?? d).join(", ")
        if (m.COUNT) t += "  ·  " + m.COUNT + " times"
        else if (m.UNTIL) t += "  ·  until " + parseInt(m.UNTIL.slice(6, 8)) + "." + parseInt(m.UNTIL.slice(4, 6)) + "." + m.UNTIL.slice(0, 4)
        return t
    }

    function remove(onlyThis) {
        CalendarStore.deleteEvent(ev, onlyThis, res => {
            if (res.ok) root.close()
            else root.error = res.error
        })
    }

    // start moves → keep the duration
    function moveStart(day, mins) {
        const dur = at(fEndDay, fEndMin) - at(fStartDay, fStartMin)
        fStartDay = day
        fStartMin = mins
        const e = new Date(at(day, mins) + Math.max(dur, fAllDay ? 0 : 900000))
        fEndDay = U.dayStart(e)
        fEndMin = e.getHours() * 60 + e.getMinutes()
    }

    readonly property var timeOptions: {
        const out = []
        for (let m = 0; m < 1440; m += 15) out.push({ label: U.pad(Math.floor(m / 60)) + ":" + U.pad(m % 60), value: m })
        return out
    }
    function timesWith(m) {
        return timeOptions.some(o => o.value === m) ? timeOptions
             : timeOptions.concat([{ label: U.pad(Math.floor(m / 60)) + ":" + U.pad(m % 60), value: m }]).sort((a, b) => a.value - b.value)
    }

    ColumnLayout {
        id: body
        width: parent.width
        spacing: 14

        SequentialAnimation {
            id: swap
            NumberAnimation { target: body; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
        }

        // ── Details ──────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            visible: !root.editing && root.ev !== null
            spacing: 12

            // title + when + countdown
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Rectangle {
                    Layout.preferredWidth: 5
                    Layout.fillHeight: true
                    Layout.minimumHeight: 46
                    radius: 3
                    color: root.calColor
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text {
                        Layout.fillWidth: true
                        text: root.ev?.title ?? ""
                        color: Colors.ink
                        font.pixelSize: 20
                        font.bold: true
                        font.family: Properties.fontFamily
                        wrapMode: Text.WordWrap
                    }
                    RowLayout {
                        spacing: 8
                        Rectangle {
                            implicitWidth: countdown.implicitWidth + 18
                            implicitHeight: 22
                            radius: 11
                            color: Qt.rgba(root.calColor.r, root.calColor.g, root.calColor.b, 0.22)
                            border.width: 1
                            border.color: Qt.rgba(root.calColor.r, root.calColor.g, root.calColor.b, 0.5)
                            Text {
                                id: countdown
                                anchors.centerIn: parent
                                text: root.ev ? root.countdownText(root.ev) : ""
                                color: Colors.ink
                                font.pixelSize: 11
                                font.bold: true
                                font.family: Properties.fontFamily
                            }
                        }
                        Text {
                            text: root.ev ? U.fmtDate(new Date(root.ev.start)) : ""
                            color: Colors.fade(0.55)
                            font.pixelSize: 12
                            font.family: Properties.fontFamily
                        }
                    }
                }
                IconButton {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: 30; implicitHeight: 30
                    icon: "󰅖"
                    onClicked: root.close()
                }
            }

            // info cards
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 8
                rowSpacing: 8

                EventInfoCard {
                    icon: "󰥔"
                    label: "When"
                    value: {
                        const e = root.ev
                        if (!e) return ""
                        const s = new Date(e.start), en = new Date(e.end)
                        if (e.allDay) {
                            const last = U.addDays(en, -1)
                            return U.sameDay(s, last) || en <= s ? "All day" : U.fmtShortDate(s) + " – " + U.fmtShortDate(last)
                        }
                        return U.sameDay(s, en) ? U.fmtTime(e.start) + " – " + U.fmtTime(e.end)
                                                : U.fmtShortDate(s) + " " + U.fmtTime(e.start) + " – " + U.fmtShortDate(en) + " " + U.fmtTime(e.end)
                    }
                    sub: root.ev ? root.durationText(root.ev) : ""
                }
                EventInfoCard {
                    icon: "󰃭"
                    label: "Calendar"
                    dot: root.calColor
                    value: root.cal?.name ?? ""
                    sub: (root.cal?.accountName ?? "") + (root.writable ? "" : "  ·  read-only")
                }
                EventInfoCard {
                    visible: root.ev?.recurring ?? false
                    icon: "󰑖"
                    label: "Repeats"
                    value: root.ruleText(root.ev?.rrule ?? "")
                    sub: "Changes can apply to one or all"
                }
                EventInfoCard {
                    icon: "󰂚"
                    label: "Reminder"
                    value: root.ev ? root.reminderText(root.ev) : ""
                    sub: root.ev && root.ev.alarms && root.ev.alarms.length ? "set on the event" : "default from settings"
                }
            }

            // location
            Rectangle {
                Layout.fillWidth: true
                visible: (root.ev?.location ?? "") !== ""
                implicitHeight: 48
                radius: 12
                color: Colors.card
                border.width: Properties.panelBorderWidth
                border.color: Properties.cardBorder
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 8
                    spacing: 10
                    Text {
                        text: "󰍎"
                        color: root.calColor
                        font.pixelSize: 16
                        font.family: Properties.fontFamily
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.ev?.location ?? ""
                        color: Colors.ink
                        font.pixelSize: 12
                        font.family: Properties.fontFamily
                        elide: Text.ElideRight
                    }
                    IconButton {
                        implicitWidth: 30; implicitHeight: 30
                        iconSize: 13
                        icon: "󰆌"
                        tooltip: "Show on a map"
                        onClicked: Qt.openUrlExternally("https://www.openstreetmap.org/search?query=" + encodeURIComponent(root.ev.location))
                    }
                }
            }

            DetailLine {
                icon: "󰌹"
                text: root.ev?.url ?? ""
                visible: text !== ""
                link: true
            }

            // notes
            Rectangle {
                Layout.fillWidth: true
                visible: (root.ev?.description ?? "") !== ""
                implicitHeight: Math.min(notesText.implicitHeight + 20, 220)
                radius: 12
                color: Colors.card
                border.width: Properties.panelBorderWidth
                border.color: Properties.cardBorder
                Flickable {
                    id: notesFlick
                    anchors.fill: parent
                    anchors.margins: 10
                    contentHeight: notesText.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: CalScrollBar {}
                    TextEdit {
                        id: notesText
                        width: parent.width - 8
                        readOnly: true
                        selectByMouse: true
                        text: root.ev?.description ?? ""
                        color: Colors.fade(0.8)
                        selectionColor: Colors.fade(0.28)
                        font.pixelSize: 12
                        font.family: Properties.fontFamily
                        wrapMode: TextEdit.Wrap
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

            RowLayout {
                Layout.fillWidth: true
                visible: root.writable
                spacing: 8
                ActionButton {
                    visible: !root.confirmDelete
                    icon: "󰆴"
                    text: "Delete"
                    textColor: Colors.red
                    onClicked: root.confirmDelete = true
                }
                ActionButton {
                    visible: root.confirmDelete && (root.ev?.recurring ?? false)
                    icon: "󰆴"
                    text: "Only this one"
                    textColor: Colors.red
                    interactive: !CalendarStore.working
                    onClicked: root.remove(true)
                }
                ActionButton {
                    visible: root.confirmDelete
                    icon: "󰆴"
                    text: (root.ev?.recurring ?? false) ? "All repeats" : "Really delete"
                    textColor: Colors.red
                    primary: true
                    interactive: !CalendarStore.working
                    onClicked: root.remove(false)
                }
                ActionButton {
                    visible: root.confirmDelete
                    text: "Cancel"
                    onClicked: root.confirmDelete = false
                }
                Item { Layout.fillWidth: true }
                // a series: edit this occurrence or all of them
                ActionButton {
                    visible: !root.confirmDelete && (root.ev?.recurring ?? false)
                    icon: "󰏫"
                    text: "Edit this event"
                    onClicked: root.edit("this")
                }
                ActionButton {
                    visible: !root.confirmDelete
                    icon: (root.ev?.recurring ?? false) ? "󰑖" : "󰏫"
                    text: (root.ev?.recurring ?? false) ? "Edit series" : "Edit"
                    primary: true
                    onClicked: root.edit("all")
                }
            }
        }

        // ── Editor ───────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.editing
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: !root.ev ? "New event" : root.editScope === "this" ? "Edit this event"
                        : root.editScope === "all" ? "Edit series" : "Edit event"
                    color: Colors.ink
                    font.pixelSize: 17
                    font.bold: true
                    font.family: Properties.fontFamily
                }
                IconButton {
                    implicitWidth: 30; implicitHeight: 30
                    icon: "󰅖"
                    onClicked: root.close()
                }
            }

            SearchField {
                id: titleField
                Layout.fillWidth: true
                icon: "󰏫"
                placeholderText: "Title"
                text: root.fTitle
                onTextEdited: root.fTitle = text
                onAccepted: root.save()
            }

            Text {
                Layout.fillWidth: true
                visible: root.ev?.recurring ?? false
                text: root.editScope === "this" ? "󰑖  Only this occurrence changes — the rest of the series stays as it is."
                    : "󰑖  Changes apply to every event of the series."
                color: Colors.fade(0.55)
                font.pixelSize: 11
                font.family: Properties.fontFamily
                wrapMode: Text.WordWrap
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: form.implicitHeight
                radius: 14
                color: Colors.card
                border.width: Properties.panelBorderWidth
                border.color: Properties.cardBorder

                ColumnLayout {
                    id: form
                    width: parent.width
                    spacing: 0

                    FormRow {
                        label: "Calendar"
                        DropdownControl {
                            implicitWidth: 240
                            options: CalendarStore.writableCalendars.map(c => ({ label: c.name, value: c.id, hint: c.accountName, color: c.color }))
                            value: root.fCalendar
                            onEdited: v => root.fCalendar = v
                        }
                    }
                    FormRow {
                        label: "All day"
                        ToggleSwitch {
                            checked: root.fAllDay
                            onToggled: v => root.fAllDay = v
                        }
                    }
                    FormRow {
                        label: "Starts"
                        DateField {
                            day: root.fStartDay
                            onPicked: d => root.moveStart(d, root.fStartMin)
                        }
                        TimeField {
                            visible: !root.fAllDay
                            minutes: root.fStartMin
                            onEdited: v => root.moveStart(root.fStartDay, v)
                        }
                    }
                    FormRow {
                        label: "Ends"
                        DateField {
                            day: root.fEndDay
                            onPicked: d => root.fEndDay = d
                        }
                        TimeField {
                            visible: !root.fAllDay
                            minutes: root.fEndMin
                            onEdited: v => root.fEndMin = v
                        }
                    }
                    Rectangle {
                        visible: root.editScope !== "this"
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        implicitHeight: 1
                        color: Colors.fade(0.06)
                    }
                    FormRow {
                        visible: root.editScope !== "this"      // this occurrence only: no repeat options
                        label: "Repeat"
                        DropdownControl {
                            implicitWidth: 200
                            options: [{ label: "Never", value: "none" }, { label: "Every day", value: "daily" },
                                      { label: "Every week", value: "weekly" }, { label: "Every month", value: "monthly" },
                                      { label: "Every year", value: "yearly" }]
                                     .concat(root.rFreq === "custom" ? [{ label: "Custom (kept as it is)", value: "custom" }] : [])
                            value: root.rFreq
                            onEdited: v => root.setFreq(v)
                        }
                    }
                    FormRow {
                        visible: root.rFreq !== "none" && root.rFreq !== "custom" && root.editScope !== "this"
                        label: "Every"
                        Stepper {
                            value: root.rInterval
                            from: 1; to: 99
                            onEdited: v => root.rInterval = v
                        }
                        Text {
                            Layout.preferredWidth: 56
                            text: root.unit + (root.rInterval > 1 ? "s" : "")
                            color: Colors.fade(0.7)
                            font.pixelSize: 12
                            font.family: Properties.fontFamily
                        }
                    }
                    FormRow {
                        visible: root.rFreq === "weekly" && root.editScope !== "this"
                        label: "On"
                        Repeater {
                            model: root.dayCodes
                            Rectangle {
                                id: dchip
                                required property string modelData
                                required property int index
                                readonly property bool on: root.rDays.includes(modelData)
                                implicitWidth: 30
                                implicitHeight: 30
                                radius: 15
                                color: on ? Colors.color6 : dMouse.containsMouse ? Colors.fade(0.1) : Colors.fade(0.04)
                                border.width: 1
                                border.color: on ? Colors.color6 : Colors.fade(0.15)
                                Behavior on color { ColorAnimation { duration: 100 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: U.dayShort[dchip.index].slice(0, 2)
                                    color: dchip.on ? U.onColor(Colors.color6) : Colors.ink
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.family: Properties.fontFamily
                                }
                                MouseArea {
                                    id: dMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleDay(dchip.modelData)
                                }
                            }
                        }
                    }
                    FormRow {
                        visible: root.rFreq !== "none" && root.rFreq !== "custom" && root.editScope !== "this"
                        label: "Until"
                        ChoiceControl {
                            options: ["never", "after", "until"]
                            value: root.rEnd
                            onEdited: v => root.rEnd = v
                        }
                        Stepper {
                            visible: root.rEnd === "after"
                            value: root.rCount
                            from: 1; to: 999
                            onEdited: v => root.rCount = v
                        }
                        Text {
                            visible: root.rEnd === "after"
                            text: root.rCount === 1 ? "time" : "times"
                            color: Colors.fade(0.7)
                            font.pixelSize: 12
                            font.family: Properties.fontFamily
                        }
                        DateField {
                            visible: root.rEnd === "until"
                            day: root.rUntil
                            onPicked: d => root.rUntil = d
                        }
                    }
                }
            }

            SearchField {
                Layout.fillWidth: true
                icon: "󰍎"
                placeholderText: "Location"
                text: root.fLocation
                onTextEdited: root.fLocation = text
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 110
                TextArea {
                    id: notes
                    placeholderText: "Notes"
                    text: root.fNotes
                    onTextChanged: if (text !== root.fNotes) root.fNotes = text
                    wrapMode: TextEdit.Wrap
                    color: Properties.color
                    placeholderTextColor: Colors.fade(0.35)
                    selectionColor: Colors.fade(0.28)
                    font.pixelSize: 12
                    font.family: Properties.fontFamily
                    leftPadding: 14
                    rightPadding: 14
                    topPadding: 10
                    background: Rectangle {
                        radius: Properties.radius + 2
                        color: notes.activeFocus ? Colors.shade(0.23) : Colors.shade(0.27)
                        border.width: Properties.panelBorderWidth
                        border.color: notes.activeFocus ? Colors.fade(0.16) : Properties.cardBorder
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

            // repeating event: save for this one or all of them
            Rectangle {
                Layout.fillWidth: true
                visible: root.askScope
                implicitHeight: scopeRow.implicitHeight + 20
                radius: 12
                color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.1)
                border.width: 1
                border.color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.35)
                RowLayout {
                    id: scopeRow
                    anchors.fill: parent
                    anchors.margins: 10
                    anchors.leftMargin: 14
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        text: "󰑖  This event repeats. Save the changes for…"
                        color: Colors.ink
                        font.pixelSize: 12
                        font.family: Properties.fontFamily
                        wrapMode: Text.WordWrap
                    }
                    ActionButton { text: "Only this event"; onClicked: root.saveAs("this") }
                    ActionButton { text: "All events"; primary: true; onClicked: root.saveAs("all") }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: !root.askScope
                spacing: 8
                Item { Layout.fillWidth: true }
                ActionButton {
                    text: "Cancel"
                    onClicked: root.ev ? (root.editing = false) : root.close()
                }
                ActionButton {
                    icon: CalendarStore.working ? "󰔟" : "󰄬"
                    text: "Save"
                    primary: true
                    interactive: !CalendarStore.working && CalendarStore.writableCalendars.length > 0
                    onClicked: root.save()
                }
            }
        }
    }

    component DetailLine: RowLayout {
        property string icon: ""
        property string text: ""
        property bool link: false
        property color dot: "transparent"
        Layout.fillWidth: true
        spacing: 10
        Text {
            Layout.preferredWidth: 18
            horizontalAlignment: Text.AlignHCenter
            text: parent.icon
            color: Colors.fade(0.5)
            font.pixelSize: 14
            font.family: Properties.fontFamily
        }
        Text {
            Layout.fillWidth: true
            text: parent.link ? "<a href=\"" + parent.text + "\" style=\"color: white\">" + parent.text + "</a>" : parent.text
            textFormat: parent.link ? Text.RichText : Text.PlainText
            color: Colors.fade(0.8)
            font.pixelSize: 12
            font.family: Properties.fontFamily
            wrapMode: Text.WrapAnywhere
            onLinkActivated: link => Qt.openUrlExternally(link)
            HoverHandler { cursorShape: parent.link ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }
    }

    component FormRow: Item {
        property string label: ""
        default property alias content: slot.data
        Layout.fillWidth: true
        implicitHeight: 50
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: Colors.ink
            font.pixelSize: 13
            font.bold: true
            font.family: Properties.fontFamily
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
