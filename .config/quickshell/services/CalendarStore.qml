pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services

// Data side of the calendar app (modules/calendar).
//
// Network / file work is done by scripts/calendar/calsync.py (CalDAV, .ics
// subscriptions, local .ics files); this keeps the accounts, the synced
// events and runs the requests one after another.
//
// Per device, outside the dotfiles (Quickshell.stateDir/calendar):
//   accounts.json  accounts + their calendars (no passwords, those are in the keyring)
//   cache.json     last synced events, so the app opens instantly / offline
Singleton {
    id: root

    readonly property string dir: Quickshell.stateDir + "/calendar"
    readonly property string script: Quickshell.shellDir + "/scripts/calendar/calsync.py"

    // [{ id, type: caldav|ics|local, name, url, username,
    //    calendars: [{ id, href, name, color, readOnly, enabled, notify }] }]
    //    (notify: false = no reminders from that calendar)
    property var accounts: []
    property var events: []
    property var errors: []            // [{ calendar, account, message }] from the last sync
    property bool syncing: false
    property double lastSync: 0
    property double rangeStart: 0
    property double rangeEnd: 0
    property bool working: false        // save / delete / discover running
    property string lastError: ""

    // calendars of all accounts, flat
    readonly property var calendars: {
        const out = []
        for (const a of accounts)
            for (const c of a.calendars)
                out.push(Object.assign({}, c, { accountId: a.id, accountName: a.name, accountType: a.type,
                                                readOnly: c.readOnly || a.type === "ics" }))
        return out
    }
    readonly property var calendarMap: {
        const m = {}
        for (const c of calendars) m[c.id] = c
        return m
    }
    readonly property var writableCalendars: calendars.filter(c => !c.readOnly)
    readonly property var visibleEvents: events.filter(e => calendarMap[e.calendar]?.enabled)

    // dayKey → events touching that day (multi-day events on every day)
    readonly property var byDay: {
        const m = {}
        for (const e of visibleEvents) {
            const d = new Date(e.start); d.setHours(0, 0, 0, 0)
            let n = 0
            do {
                const k = d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0")
                ;(m[k] = m[k] || []).push(e)
                d.setDate(d.getDate() + 1)
            } while (d.getTime() < e.end && ++n < 60)
        }
        return m
    }

    function eventsOn(day) {
        const d = new Date(day)
        const k = d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0")
        return byDay[k] ?? []
    }

    // ── Persistence ──────────────────────────────────────────────────────────
    FileView {
        id: accountsFile
        path: root.dir + "/accounts.json"
        blockLoading: true
        printErrors: false
    }
    FileView {
        id: cacheFile
        path: root.dir + "/cache.json"
        blockLoading: true
        printErrors: false
    }

    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", root.dir])
        try { root.accounts = JSON.parse(accountsFile.text() || "[]") } catch (e) { root.accounts = [] }
        try {
            const c = JSON.parse(cacheFile.text() || "{}")
            root.events = c.events ?? []
            root.lastSync = c.lastSync ?? 0
            root.rangeStart = c.rangeStart ?? 0
            root.rangeEnd = c.rangeEnd ?? 0
        } catch (e) {}
    }

    function saveAccounts() { accountsFile.setText(JSON.stringify(root.accounts, null, 2) + "\n") }
    function saveCache() {
        cacheFile.setText(JSON.stringify({ events: root.events, lastSync: root.lastSync,
                                           rangeStart: root.rangeStart, rangeEnd: root.rangeEnd }))
    }

    // ── Running calsync.py, one request at a time ───────────────────────────
    property var queue: []
    property var current: null

    function run(cmd, request, done) {
        root.queue = root.queue.concat([{ cmd: cmd, request: request, done: done }])
        next()
    }

    function next() {
        if (root.current || root.queue.length === 0) return
        root.current = root.queue[0]
        root.queue = root.queue.slice(1)
        proc.environment = { CAL_REQUEST: JSON.stringify(root.current.request) }
        proc.command = ["python3", root.script, root.current.cmd]
        proc.running = true
    }

    Process {
        id: proc
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: code => {
            const job = root.current
            let res
            try { res = JSON.parse(out.text) }
            catch (e) { res = { ok: false, error: (err.text.trim().split("\n").pop() || "calendar helper failed (exit " + code + ")") } }
            root.current = null
            if (job.done) job.done(res)
            root.next()
        }
    }

    // ── Syncing ──────────────────────────────────────────────────────────────
    property bool syncAgain: false

    function sync() {
        if (root.syncing) { root.syncAgain = true; return }
        if (root.accounts.length === 0) { root.events = []; root.errors = []; return }
        if (root.rangeEnd <= root.rangeStart) setRange(new Date())
        root.syncing = true
        const req = {
            start: root.rangeStart, end: root.rangeEnd,
            accounts: root.accounts.map(a => Object.assign({}, a, { calendars: a.calendars.filter(c => c.enabled) }))
        }
        run("sync", req, res => {
            root.syncing = false
            if (res.ok) {
                root.events = res.events
                root.errors = res.errors
                root.lastSync = Date.now()
                saveCache()
            } else {
                root.errors = [{ calendar: "", account: "", message: res.error }]
            }
            if (root.syncAgain) { root.syncAgain = false; sync() }
        })
    }

    function setRange(center) {
        const s = new Date(center); s.setDate(1); s.setHours(0, 0, 0, 0); s.setMonth(s.getMonth() - 3)
        const e = new Date(center); e.setDate(1); e.setHours(0, 0, 0, 0); e.setMonth(e.getMonth() + 9)
        root.rangeStart = s.getTime()
        root.rangeEnd = e.getTime()
    }

    // called when the view moves: sync a wider window once it gets close to the edge
    function ensureRange(day) {
        const t = new Date(day).getTime()
        const margin = 35 * 86400000
        if (t - margin < root.rangeStart || t + margin > root.rangeEnd) {
            setRange(day)
            sync()
        }
    }

    // ── Accounts ─────────────────────────────────────────────────────────────
    readonly property var palette: ["#7aa2f7", "#9ece6a", "#e0af68", "#f7768e", "#bb9af7", "#7dcfff", "#ff9e64", "#73daca"]

    // form: { type, name, url, username, password } → done({ ok, calendars | error })
    function discover(form, done) {
        root.working = true
        run("discover", form, res => { root.working = false; done(res) })
    }

    function addAccount(form, calendars) {
        const id = "acc-" + Date.now().toString(36)
        const used = root.calendars.length
        const acc = {
            id: id, type: form.type, name: form.name || form.url, url: form.url, username: form.username || "",
            calendars: calendars.map((c, i) => ({
                id: id + "|" + c.href, href: c.href, name: c.name,
                color: c.color || root.palette[(used + i) % root.palette.length],
                readOnly: !!c.readOnly, enabled: c.enabled !== false
            }))
        }
        const add = () => {
            root.accounts = root.accounts.concat([acc])
            saveAccounts()
            sync()
        }
        if (form.password) {
            run("store-secret", { id: id, label: "Quickshell calendar: " + acc.name, password: form.password }, res => {
                if (res.ok) add()
                else root.lastError = res.error
            })
        } else {
            add()
        }
    }

    function removeAccount(id) {
        run("forget-secret", { id: id }, () => {})
        root.accounts = root.accounts.filter(a => a.id !== id)
        root.events = root.events.filter(e => !e.calendar.startsWith(id + "|"))
        saveAccounts()
        saveCache()
    }

    function renameAccount(id, name) {
        root.accounts = root.accounts.map(a => a.id === id ? Object.assign({}, a, { name: name }) : a)
        saveAccounts()
    }

    function setCalendar(calId, patch) {
        let resync = false
        root.accounts = root.accounts.map(a => Object.assign({}, a, {
            calendars: a.calendars.map(c => {
                if (c.id !== calId) return c
                if (patch.enabled === true && !c.enabled) resync = true
                return Object.assign({}, c, patch)
            })
        }))
        saveAccounts()
        if (resync) sync()
    }

    // ── Background sync ──────────────────────────────────────────────────────
    // keeps the dashboard and reminders current with the app closed
    readonly property int syncMinutes: parseInt(Settings.calendar.syncMinutes ?? "15") || 15
    Timer {
        interval: root.syncMinutes * 60000
        repeat: true
        running: root.accounts.length > 0
        onTriggered: { root.ensureRange(new Date()); root.sync() }
    }
    // first sync a little after startup
    Timer {
        interval: 8000
        running: root.accounts.length > 0
        onTriggered: { root.ensureRange(new Date()); root.sync() }
    }

    // ── Reminders ────────────────────────────────────────────────────────────
    // An event's own alarms (VALARM) or, without any, the default from the
    // settings app (Calendar page). Shown as normal notifications; clicking
    // opens the calendar on that day.
    readonly property bool remindersOn: Settings.calendar.reminders ?? true
    readonly property int defaultReminder: {
        const v = Settings.calendar.defaultReminder ?? "10"
        return v === "off" ? -1 : parseInt(v)
    }
    readonly property bool allDayReminder: Settings.calendar.allDayReminder ?? false

    property double lastCheck: Date.now()    // nothing from before the shell started
    property var fired: ({})                 // "eventId|time" → true

    function reminderTimes(e) {
        if (e.alarms && e.alarms.length > 0) return e.alarms
        if (e.allDay) {
            if (!root.allDayReminder) return []
            const d = new Date(e.start); d.setHours(9, 0, 0, 0)
            return [d.getTime()]
        }
        return root.defaultReminder >= 0 ? [e.start - root.defaultReminder * 60000] : []
    }

    function checkReminders() {
        const now = Date.now()
        const from = root.lastCheck
        root.lastCheck = now
        if (!root.remindersOn) return
        const f = Object.assign({}, root.fired)
        for (const e of root.visibleEvents) {
            if (e.end < from || root.calendarMap[e.calendar]?.notify === false) continue
            for (const t of reminderTimes(e)) {
                const key = e.id + "|" + t
                if (t > from && t <= now && !f[key]) {
                    f[key] = true
                    // after a long suspend only remind about what hasn't started yet
                    if (now - t > 10 * 60000 && e.start < now) continue
                    notify(e)
                }
            }
        }
        root.fired = f
    }

    Timer {
        interval: 20000
        repeat: true
        running: root.accounts.length > 0
        onTriggered: root.checkReminders()
    }

    function pad(n) { return String(n).padStart(2, "0") }
    function hm(t) { const d = new Date(t); return pad(d.getHours()) + ":" + pad(d.getMinutes()) }

    function notify(e) {
        const mins = Math.round((e.start - Date.now()) / 60000)
        let when
        if (e.allDay) when = "Today, all day"
        else if (mins > 1) when = mins >= 60 && mins % 60 === 0 ? "In " + (mins / 60) + " h" : "In " + mins + " min"
        else if (mins >= -1) when = "Now"
        else when = "Started " + (-mins) + " min ago"
        const parts = [when]
        if (!e.allDay) parts.push(hm(e.start) + " – " + hm(e.end))
        if (e.location) parts.push(e.location)
        const cal = root.calendarMap[e.calendar]
        const day = new Date(e.start)
        const iso = day.getFullYear() + "-" + pad(day.getMonth() + 1) + "-" + pad(day.getDate())
        // --wait: the click (default action) opens the calendar on that day
        Quickshell.execDetached(["sh", "-c",
            // UTF-8 forced: without a UTF-8 locale notify-send drops titles with umlauts etc.
            'r=$(LC_ALL=C.UTF-8 notify-send --app-name="$1" --icon=x-office-calendar --expire-time=20000 '
            + '--action=default=Open "$2" "$3" --wait) && [ "$r" = default ] && qs ipc call calendar openDate "$4"',
            "sh", "Calendar" + (cal ? " · " + cal.name : ""), e.title, parts.join("  ·  "), iso])
    }

    // ── Events ───────────────────────────────────────────────────────────────
    function accountOf(calId) { return root.accounts.find(a => calId.startsWith(a.id + "|")) }
    function calendarOf(calId) { return accountOf(calId)?.calendars.find(c => c.id === calId) }

    // ev: { title, start, end, allDay, location, description, + uid/href/etag/... when editing }
    function saveEvent(ev, calId, done) {
        root.working = true
        run("save", { account: accountOf(calId), calendar: calendarOf(calId), event: ev }, res => {
            root.working = false
            root.lastError = res.ok ? "" : res.error
            if (done) done(res)
            if (res.ok) sync()
        })
    }

    // dragged in the week / day view: show it at the new place right away,
    // save in the background, and put it back if the server says no
    // scope ("this" | "all") matters for repeating events only
    function moveEvent(ev, start, end, scope) {
        if (start === ev.start && end === ev.end) return
        const moved = Object.assign({}, ev, { start: start, end: end, scope: scope || "all" })
        root.events = root.events.map(e => e.id === ev.id ? moved : e)
        saveEvent(moved, ev.calendar, res => { if (!res.ok) sync() })
    }

    function deleteEvent(ev, onlyThis, done) {
        root.working = true
        run("delete", { account: accountOf(ev.calendar), calendar: calendarOf(ev.calendar), event: ev, occurrence: onlyThis }, res => {
            root.working = false
            root.lastError = res.ok ? "" : res.error
            if (done) done(res)
            if (res.ok) sync()
        })
    }
}
