pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services.lib
import qs.services

// Data side of the calendar app (modules/calendar).
//
// Network / file work is done by scripts/calendar/calsync.py (CalDAV, .ics
// subscriptions, local .ics files, Microsoft 365); this keeps the accounts, the synced
// events and runs the requests one after another.
//
// Per device, outside the dotfiles (Quickshell.stateDir/calendar):
//   accounts.json  accounts + their calendars (no passwords, those are in the keyring)
//   cache.json     last synced events, so the app opens instantly / offline
Singleton {
    id: root

    readonly property string dir: Quickshell.stateDir + "/calendar"
    readonly property string script: Quickshell.shellDir + "/scripts/calendar/calsync.py"

    // [{ id, type: caldav|ics|local|graph, name, url, username, (graph: tenant, clientId)
    //    enabled (false = the whole account switched off: not synced, nothing shown),
    //    calendars: [{ id, href, name, color, readOnly, enabled, notify }] }]
    //    (notify: false = no reminders from that calendar)
    property var accounts: []
    function kindOf(a) { return a.type === "ics" ? "Subscription" : a.type === "local" ? "Local" : /icloud/i.test(a.url) ? "iCloud" : "CalDAV" }
    // the calendar settings' pages (CalendarSettingsPages): the app's settings dialog lists
    // them, the settings app shows them as sub-pages of Calendar. action: a button, not a page
    readonly property var settingsPages: [
        { id: "reminders", icon: "󰂚", label: "Reminders" },
        { id: "view", icon: "󰃭", label: "View" },
        { id: "sync", icon: "󰓦", label: "Sync" }
    ].concat(accounts.map((a, i) => ({
        id: "acc:" + a.id, label: a.name, heading: a.name === kindOf(a) ? a.name : a.name + "  ·  " + kindOf(a),
        color: a.calendars?.[0]?.color || Colors.color6, group: i === 0 ? "Accounts" : undefined
    }))).concat([
        { id: "transfer", icon: "󰑓", label: "Export / import", group: accounts.length === 0 ? "Accounts" : undefined,
          heading: "Move accounts to another device" },
        { id: "add", icon: "󰐕", label: "Add account", action: true }
    ])
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
                                                accountOn: a.enabled !== false,
                                                readOnly: c.readOnly || a.type === "ics" }))
        return out
    }
    readonly property var calendarMap: {
        const m = {}
        for (const c of calendars) m[c.id] = c
        return m
    }
    readonly property var writableCalendars: calendars.filter(c => !c.readOnly && c.accountOn)
    readonly property var visibleEvents: events.filter(e => calendarMap[e.calendar]?.enabled && calendarMap[e.calendar]?.accountOn)
    readonly property var activeAccounts: accounts.filter(a => a.enabled !== false)

    // dayKey → events touching that day (multi-day events on every day)
    readonly property var byDay: {
        const m = {}
        for (const e of visibleEvents) {
            const d = new Date(e.start); d.setHours(0, 0, 0, 0)
            let n = 0
            do {
                const k = Format.day(d)
                ;(m[k] = m[k] || []).push(e)
                d.setDate(d.getDate() + 1)
            } while (d.getTime() < e.end && ++n < 60)
        }
        return m
    }

    function eventsOn(day) {
        const d = new Date(day)
        const k = Format.day(d)
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
        // a time limit, so one server that never answers can't block the queue
        // for good (the sign-in and the import run as Jobs, not here)
        proc.command = ["timeout", "-k", "5", root.current.cmd === "sync" ? "180" : "90", "python3", root.script, root.current.cmd]
        proc.running = true
    }

    Process {
        id: proc
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: code => {
            const job = root.current
            let res
            if (code === 124 || code === 137) res = { ok: false, error: "The server took too long to answer — try again in a moment" }
            else {
                try { res = JSON.parse(out.text) }
                catch (e) { res = { ok: false, error: (err.text.trim().split("\n").pop() || "calendar helper failed (exit " + code + ")") } }
            }
            root.current = null
            if (job.done) job.done(res)
            root.next()
        }
    }

    // ── Syncing ──────────────────────────────────────────────────────────────
    property bool syncAgain: false
    property double lastListCheck: 0      // calendars added / removed on other devices, checked hourly

    // lists: also look for calendars made / deleted elsewhere (window opened, "Sync now")
    function sync(lists) {
        if (root.syncing) { root.syncAgain = true; return }
        if (root.activeAccounts.length === 0) { root.events = []; root.errors = []; return }
        if (root.rangeEnd <= root.rangeStart) setRange(new Date())
        root.syncing = true
        const checkLists = lists === true || Date.now() - root.lastListCheck > 3600000
        if (checkLists) root.lastListCheck = Date.now()
        const req = {
            start: root.rangeStart, end: root.rangeEnd,
            accounts: root.activeAccounts.map(a => Object.assign({}, a, { calendars: a.calendars.filter(c => c.enabled) })),
            discover: checkLists ? root.activeAccounts.map(a => a.id) : []
        }
        run("sync", req, res => {
            root.syncing = false
            if (res.ok) {
                root.events = withLocalMoves(res.events)
                root.errors = res.errors
                root.lastSync = Date.now()
                saveCache()
                applyServerColors(res.colors ?? {})
                applyCalendarLists(res.calendarLists ?? {})
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

    function newAccountId() { return "acc-" + Date.now().toString(36) }

    // the same login added again (e.g. to get a calendar made on the iPhone): it
    // goes into the account that's there instead of becoming a second one
    function sameAccount(form) {
        const norm = u => String(u || "").trim().toLowerCase().replace(/^webcal:/, "https:").replace(/\/+$/, "")
        return root.accounts.find(a => a.type === form.type && form.type !== "local" && form.type !== "ics"
                                       && norm(a.url) === norm(form.url)
                                       && String(a.username).toLowerCase() === String(form.username || "").trim().toLowerCase())
    }

    // form.id: given when the keyring entry already exists (Microsoft 365 sign-in)
    function addAccount(form, calendars) {
        const same = sameAccount(form)
        if (same) { mergeAccount(same, form, calendars); return }
        const id = form.id || newAccountId()
        const used = root.calendars.length
        const acc = {
            id: id, type: form.type, name: form.name || form.url, url: form.url, username: form.username || "",
            calendars: calendars.map((c, i) => ({
                id: id + "|" + c.href, href: c.href, name: c.name,
                color: c.color || root.palette[(used + i) % root.palette.length],
                readOnly: !!c.readOnly, enabled: c.enabled !== false
            }))
        }
        if (form.tenant) acc.tenant = form.tenant
        if (form.clientId) acc.clientId = form.clientId
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

    // ── Microsoft 365 sign-in ────────────────────────────────────────────────
    // Device code: calsync prints the code at once, then waits until it was
    // approved in the browser (up to 15 min), so it runs beside the queue.
    // form: { id, tenant, clientId }; onCode({ userCode, url, expiresIn });
    // done({ ok, calendars, username | error }). The tokens land in the keyring
    // under form.id: forgetSecret(id) if the account doesn't get added after all.
    property int loginRun: 0

    function graphLogin(form, onCode, done) {
        const run = ++root.loginRun
        let answered = false
        Jobs.start("calendar-graph-login", ["python3", root.script, "graph-login"], {
            env: { CAL_REQUEST: JSON.stringify(form) }, store: false, timeout: 16 * 60000,
            onLine: (line, isErr) => {
                if (isErr || run !== root.loginRun) return
                let msg
                try { msg = JSON.parse(line) } catch (e) { return }
                if (msg.step === "code") onCode(msg)
                else { answered = true; done(msg) }
            },
            onExit: code => {
                if (answered || run !== root.loginRun) return
                const st = Jobs.state("calendar-graph-login")
                done({ ok: false, error: st.timedOut ? "The code expired — start again"
                                      : "calendar helper failed (exit " + code + ")" })
            }
        })
    }

    function cancelGraphLogin() {
        root.loginRun++
        Jobs.cancel("calendar-graph-login")
    }

    function forgetSecret(id) { run("forget-secret", { id: id }, () => {}) }

    function mergeAccount(acc, form, calendars) {
        const chosen = {}
        for (const c of calendars) chosen[c.href] = c
        let used = root.calendars.length
        const cals = acc.calendars.map(c => chosen[c.href] ? Object.assign({}, c, { enabled: true }) : c)
        for (const c of calendars)
            if (!acc.calendars.some(x => x.href === c.href))
                cals.push({ id: acc.id + "|" + c.href, href: c.href, name: c.name,
                            color: c.color || root.palette[used++ % root.palette.length],
                            readOnly: !!c.readOnly, enabled: true })
        const update = () => {
            root.accounts = root.accounts.map(a => a.id === acc.id ? Object.assign({}, a, { calendars: cals, enabled: true }) : a)
            saveAccounts()
            sync()
        }
        // a new password replaces the old one; Microsoft's new tokens aren't needed
        if (form.type === "graph" && form.id) forgetSecret(form.id)
        if (form.password)
            run("store-secret", { id: acc.id, label: "Quickshell calendar: " + acc.name, password: form.password }, res => {
                if (res.ok) update()
                else root.lastError = res.error
            })
        else update()
    }

    // calendars made / deleted on another device: the new ones show up, gone ones go
    function applyCalendarLists(lists) {
        let changed = false
        let used = root.calendars.length
        const accs = root.accounts.map(a => {
            const list = lists[a.id]
            if (!list || list.length === 0) return a
            const hrefs = list.map(c => c.href)
            const kept = a.calendars.filter(c => hrefs.includes(c.href)).map(c => {
                const s = list.find(x => x.href === c.href)
                if (s.name === c.name && !!s.readOnly === !!c.readOnly) return c
                changed = true
                return Object.assign({}, c, { name: s.name, readOnly: !!s.readOnly })
            })
            const added = list.filter(s => !a.calendars.some(c => c.href === s.href)).map(s => ({
                id: a.id + "|" + s.href, href: s.href, name: s.name,
                color: s.color || root.palette[used++ % root.palette.length],
                readOnly: !!s.readOnly, enabled: a.autoAdd !== false
            }))
            if (added.length === 0 && kept.length === a.calendars.length) return a
            changed = true
            return Object.assign({}, a, { calendars: kept.concat(added) })
        })
        if (!changed) return
        root.accounts = accs
        root.events = root.events.filter(e => root.calendarMap[e.calendar])
        saveAccounts()
        saveCache()
        sync()
    }

    // look for new calendars on that account right now (sidebar menu)
    function refreshCalendars(id, done) {
        const acc = root.accounts.find(a => a.id === id)
        if (!acc) return
        run("rediscover", { account: acc }, res => {
            if (res.ok) { const l = {}; l[id] = res.calendars; applyCalendarLists(l) }
            else root.lastError = acc.name + ": " + res.error
            if (done) done(res)
        })
    }

    // the whole account on / off; its setup (and keyring login) stays
    function setAccount(id, patch) {
        root.accounts = root.accounts.map(a => a.id === id ? Object.assign({}, a, patch) : a)
        saveAccounts()
        if (patch.enabled === true) sync(true)
        else if (patch.enabled === false) root.errors = root.errors.filter(e => !e.calendar.startsWith(id + "|"))
    }

    function removeAccount(id) {
        run("forget-secret", { id: id }, () => {})
        root.accounts = root.accounts.filter(a => a.id !== id)
        root.events = root.events.filter(e => !e.calendar.startsWith(id + "|"))
        saveAccounts()
        saveCache()
    }

    // ── Moving accounts to another device (calsync export-accounts / import-accounts) ──
    function exportAccounts(ids, withPasswords, passphrase, path, done) {
        const list = root.accounts.filter(a => ids.includes(a.id))
        run("export-accounts", { accounts: list, withPasswords: withPasswords, passphrase: passphrase, path: path }, done)
    }
    function importRead(path, passphrase, done) { run("import-accounts-read", { path: path, passphrase: passphrase }, done) }
    // the account in the file that's already here (same login / same url): updated, keeps its id
    function existingFor(a) {
        const norm = u => String(u || "").trim().toLowerCase().replace(/^webcal:/, "https:").replace(/\/+$/, "")
        return a.type === "local" || a.type === "ics" ? root.accounts.find(x => x.type === a.type && norm(x.url) === norm(a.url))
                                                      : sameAccount(a)
    }
    // indexes: the accounts of the file to take (their "index" from importRead)
    function importAccounts(path, passphrase, found, indexes, done) {
        const pick = {}
        indexes.forEach((i, n) => {
            const a = found.find(x => x.index === i)
            pick[String(i)] = existingFor(a)?.id ?? newAccountId() + "-" + n
        })
        run("import-accounts", { path: path, passphrase: passphrase, pick: pick }, res => {
            if (res.ok) {
                let accs = root.accounts
                for (const a of res.accounts) {
                    const used = accs.reduce((n, x) => n + x.calendars.length, 0)
                    const acc = { id: a.id, type: a.type, name: a.name, url: a.url, username: a.username,
                                  calendars: a.calendars.map((c, i) => ({ id: a.id + "|" + c.href, href: c.href, name: c.name,
                                      color: c.color || root.palette[(used + i) % root.palette.length],
                                      readOnly: c.readOnly, enabled: c.enabled, notify: c.notify })) }
                    if (a.tenant) acc.tenant = a.tenant
                    if (a.clientId) acc.clientId = a.clientId
                    accs = accs.some(x => x.id === a.id) ? accs.map(x => x.id === a.id ? acc : x) : accs.concat([acc])
                }
                root.accounts = accs
                saveAccounts()
                sync(true)
            }
            done(res)
        })
    }

    function renameAccount(id, name) {
        root.accounts = root.accounts.map(a => a.id === id ? Object.assign({}, a, { name: name }) : a)
        saveAccounts()
    }

    // colors changed on another device (CalDAV: the server's calendar-color)
    function applyServerColors(colors) {
        let changed = false
        const accs = root.accounts.map(a => Object.assign({}, a, {
            calendars: a.calendars.map(c => {
                const sc = colors[c.id]
                if (!sc || sc.toLowerCase() === String(c.color).toLowerCase()) return c
                changed = true
                return Object.assign({}, c, { color: sc })
            })
        }))
        if (changed) { root.accounts = accs; saveAccounts() }
    }

    function setCalendar(calId, patch) {
        // a new color also goes to the server (CalDAV), so other devices get it
        if (patch.color !== undefined) {
            const acc = accountOf(calId)
            if (acc && acc.type === "caldav")
                run("set-color", { account: acc, calendar: calendarOf(calId), color: patch.color }, res => {
                    if (!res.ok) root.lastError = "Color not saved on the server: " + res.error
                })
        }
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
        running: root.activeAccounts.length > 0
        onTriggered: { root.ensureRange(new Date()); root.sync() }
    }
    // first sync a little after startup
    Timer {
        interval: 8000
        running: root.activeAccounts.length > 0
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
    readonly property bool startReminder: Settings.calendar.startReminder ?? false
    // played with the popup (not with do-not-disturb on, the popup isn't shown then)
    readonly property var sounds: ({ message: "message-new-instant", bell: "bell", alarm: "alarm-clock-elapsed", complete: "complete" })
    readonly property string reminderSound: Settings.calendar.reminderSound ?? "message"

    property double lastCheck: Date.now()    // nothing from before the shell started
    property var fired: ({})                 // "eventId|time" → true

    function reminderTimes(e) {
        if (e.allDay) {
            if (e.alarms && e.alarms.length > 0) return e.alarms
            if (!root.allDayReminder) return []
            const d = new Date(e.start); d.setHours(9, 0, 0, 0)
            return [d.getTime()]
        }
        const out = e.alarms && e.alarms.length > 0 ? e.alarms.slice()
                  : root.defaultReminder >= 0 ? [e.start - root.defaultReminder * 60000] : []
        // and one when it starts
        if (root.startReminder && !out.includes(e.start)) out.push(e.start)
        return out
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
        interval: 10000
        repeat: true
        running: root.activeAccounts.length > 0
        onTriggered: root.checkReminders()
    }


    function notify(e) {
        const mins = Math.round((e.start - Date.now()) / 60000)
        let when
        if (e.allDay) when = "Today, all day"
        else if (mins > 1) when = mins >= 60 && mins % 60 === 0 ? "In " + (mins / 60) + " h" : "In " + mins + " min"
        else if (mins >= -1) when = "Now"
        else when = "Started " + (-mins) + " min ago"
        const parts = [when]
        if (!e.allDay) parts.push(Format.hm(e.start) + " – " + Format.hm(e.end))
        if (e.location) parts.push(e.location)
        const cal = root.calendarMap[e.calendar]
        const day = new Date(e.start)
        const iso = Format.day(day)
        // --wait: the click (default action) opens the calendar on that day.
        // UTF-8 forced: without a UTF-8 locale notify-send drops titles with umlauts etc.
        Jobs.run(["notify-send", "--app-name=" + "Calendar" + (cal ? " · " + cal.name : ""), "--icon=x-office-calendar",
                  "--expire-time=20000", "--action=default=Open", e.title, parts.join("  ·  "), "--wait"],
                 (code, out) => { if (code === 0 && out.trim() === "default") Panels.call("calendar", "openDate", iso) },
                 { LC_ALL: "C.UTF-8" })
        playSound()
    }

    function playSound(name) {
        const file = root.sounds[name ?? root.reminderSound]
        if (!file || (name === undefined && Notifs.dnd)) return
        Jobs.run(["pw-play", "/usr/share/sounds/freedesktop/stereo/" + file + ".oga"], () => {})
    }

    // ── Zoom of the day / week view (hour height in %) ──────────────────────
    readonly property var zoomSteps: [60, 80, 100, 125, 150, 200, 250, 300]
    readonly property int zoom: parseInt(Settings.calendar.zoom ?? "100") || 100
    function zoomBy(dir) {
        const i = root.zoomSteps.findIndex(z => z >= root.zoom)
        const next = root.zoomSteps[Math.max(0, Math.min(root.zoomSteps.length - 1, (i < 0 ? root.zoomSteps.length - 1 : i) + dir))]
        if (next !== root.zoom) Settings.set("calendar", "zoom", String(next))
    }
    function zoomReset() { Settings.set("calendar", "zoom", "100") }

    // ── Events ───────────────────────────────────────────────────────────────
    function accountOf(calId) { return root.accounts.find(a => calId.startsWith(a.id + "|")) }
    function calendarOf(calId) { return accountOf(calId)?.calendars.find(c => c.id === calId) }

    // ev: { title, start, end, allDay, location, description, + uid/href/etag/... when editing }
    function saveEvent(ev, calId, done) {
        if (ev.id) dropPendingMove(ev.id)
        root.working = true
        run("save", { account: accountOf(calId), calendar: calendarOf(calId), event: ev }, res => {
            root.working = false
            root.lastError = res.ok ? "" : res.error
            if (done) done(res)
            if (res.ok) sync()
        })
    }

    // dragged in the week / day view: show it at the new place right away and
    // save a few seconds after the last move (Settings.calendar.moveDelay), all
    // moves at once, then one sync. Until then a sync (background, another move's
    // save) keeps the moved events where they were put instead of snapping back.
    // A failed save puts that one back. scope ("this" | "all"): repeating events only
    readonly property int moveDelay: parseInt(Settings.calendar.moveDelay ?? "10") || 0
    property var pendingMoves: ({})       // id → moved event, not saved yet
    property var savingMoves: ({})        // id → moved event, being saved

    function moveEvent(ev, start, end, scope) {
        if (start === ev.start && end === ev.end) return
        const moved = Object.assign({}, ev, { start: start, end: end, scope: scope || "all" })
        root.events = root.events.map(e => e.id === ev.id ? moved : e)
        const p = Object.assign({}, root.pendingMoves)
        p[ev.id] = moved
        root.pendingMoves = p
        if (root.moveDelay > 0) moveTimer.restart()
        else Qt.callLater(flushMoves)
    }

    Timer {
        id: moveTimer
        interval: root.moveDelay * 1000
        onTriggered: root.flushMoves()
    }

    function withLocalMoves(list) {
        const local = Object.assign({}, root.savingMoves, root.pendingMoves)
        if (Object.keys(local).length === 0) return list
        return list.map(e => local[e.id] ?? e)
    }

    // save the waiting moves now (timer, calendar window closed)
    function flushMoves() {
        moveTimer.stop()
        const list = Object.values(root.pendingMoves)
        if (list.length === 0) return
        root.pendingMoves = {}
        root.savingMoves = Object.assign({}, root.savingMoves, ...list.map(m => ({ [m.id]: m })))
        let left = list.length
        const failed = []
        for (const m of list)
            run("save", { account: accountOf(m.calendar), calendar: calendarOf(m.calendar), event: m }, res => {
                const s = Object.assign({}, root.savingMoves)
                if (s[m.id] === m) delete s[m.id]
                root.savingMoves = s
                if (!res.ok) failed.push(m.title + ": " + res.error)
                else {
                    inviteUpdate(m)
                    // a series moved again before the next sync: the server has the new time already
                    if (m.recurring && m.scope !== "this")
                        root.events = root.events.map(e => e.id === m.id ? Object.assign({}, e, { occurrence: m.start }) : e)
                }
                if (--left > 0) return
                root.lastError = failed.join("\n")
                sync()
            })
    }

    // a moved event I invited people to: they get the new time (iMIP update)
    function inviteUpdate(m) {
        const org = (m.organizer?.email ?? "").toLowerCase()
        const acc = org ? MailStore.activeAccounts.find(a => a.email.toLowerCase() === org) : null
        if (!acc || !(m.attendees ?? []).length || calendarMap[m.calendar]?.accountType === "graph") return
        // one occurrence of a series would need a RECURRENCE-ID update: not sent (the series stays right)
        if (m.recurring && m.scope === "this") return
        MailStore.sendInvite(acc.id, { uid: m.uid, title: m.title, start: m.start, end: m.end, allDay: m.allDay,
                                       location: m.location, description: m.description, sequence: (m.sequence ?? 0) + 1,
                                       attendees: m.attendees, rrule: m.scope === "this" ? "" : (m.rrule ?? "") }, "REQUEST", res => {
            if (!res.ok) root.lastError = m.title + ": the guests weren't told about the new time (" + res.error + ")"
        })
    }

    function dropPendingMove(id) {
        if (!(id in root.pendingMoves)) return
        const p = Object.assign({}, root.pendingMoves)
        delete p[id]
        root.pendingMoves = p
    }

    // ── Importing .ics files ─────────────────────────────────────────────────
    // readImport(paths, done) → done({ ok, sources, total, upcoming, recurring, first, last, preview, errors })
    function readImport(paths, done) {
        root.working = true
        run("import-read", { paths: paths }, res => { root.working = false; done(res) })
    }

    // opts: { paths, calendar (id) | newCalendars: true, names, duplicates, upcomingOnly, alarms }
    // onProgress(done, total); done({ ok, imported, replaced, skipped, failed, created, newCalendars })
    // Beside the queue (big imports take a while), like the Microsoft sign-in.
    function importFiles(opts, onProgress, done) {
        const target = opts.newCalendars ? { new: true, names: opts.names ?? {} }
                                         : { account: accountOf(opts.calendar), calendar: calendarOf(opts.calendar) }
        let answered = false
        Jobs.start("calendar-import", ["python3", root.script, "import"], {
            env: { CAL_REQUEST: JSON.stringify({ paths: opts.paths, target: target, duplicates: opts.duplicates,
                                                 upcomingOnly: opts.upcomingOnly, alarms: opts.alarms }) },
            store: false, timeout: 30 * 60000,
            onLine: (line, isErr) => {
                if (isErr) return
                let msg
                try { msg = JSON.parse(line) } catch (e) { return }
                if (msg.step === "progress") { onProgress(msg.done, msg.total); return }
                answered = true
                if (msg.ok) {
                    // new local calendars: one account each, like a local calendar added by hand
                    for (const c of msg.newCalendars ?? [])
                        addAccount({ type: "local", name: c.name, url: c.href }, [c])
                    if (!(msg.newCalendars ?? []).length) sync()
                }
                done(msg)
            },
            onExit: code => {
                if (!answered) done({ ok: false, error: Jobs.state("calendar-import").cancelled ? "Stopped"
                                                       : "calendar helper failed (exit " + code + ")" })
            }
        })
    }

    function cancelImport() { Jobs.cancel("calendar-import") }

    // takes the imported events out again (only ones that were new, not replaced)
    function undoImport(calId, created, done) {
        root.working = true
        run("import-undo", { account: accountOf(calId), calendar: calendarOf(calId), created: created }, res => {
            root.working = false
            if (res.ok) sync()
            done(res)
        })
    }

    function deleteEvent(ev, onlyThis, done) {
        dropPendingMove(ev.id)
        root.working = true
        run("delete", { account: accountOf(ev.calendar), calendar: calendarOf(ev.calendar), event: ev, occurrence: onlyThis }, res => {
            root.working = false
            root.lastError = res.ok ? "" : res.error
            if (done) done(res)
            if (res.ok) sync()
        })
    }

    // ── Several events at once (Ctrl / Shift + click in the views) ───────────
    property var selected: ({})          // event id → event
    readonly property int selectedCount: Object.keys(selected).length
    readonly property var selectedEvents: Object.values(selected)
    function isSelected(id) { return root.selected[id] !== undefined }
    function toggleSelect(ev) {
        const s = Object.assign({}, root.selected)
        if (s[ev.id]) delete s[ev.id]
        else s[ev.id] = ev
        root.selected = s
    }
    function clearSelection() { if (root.selectedCount > 0) root.selected = {} }
    // the events are replaced after each sync: keep the selection pointing at the
    // current ones. An id is "calendar|uid|start", so a moved event comes back
    // with another one: found again by its calendar, uid and (new) start
    onEventsChanged: {
        if (root.selectedCount === 0) return
        const byId = {}, byPlace = {}
        for (const e of root.events) { byId[e.id] = e; byPlace[e.calendar + "|" + e.uid + "|" + e.start] = e }
        const s = {}
        for (const id in root.selected) {
            const old = root.selected[id]
            const e = byId[id] ?? byPlace[old.calendar + "|" + old.uid + "|" + old.start]
            if (e) s[e.id] = e
        }
        root.selected = s
    }

    // one request after the other, then a single sync; done({ ok, failed, error })
    function bulk(jobs, done) {
        let left = jobs.length, failed = 0, lastErr = ""
        if (left === 0) { if (done) done({ ok: true, failed: 0 }); return }
        root.working = true
        for (const j of jobs)
            run(j.cmd, j.request, res => {
                if (!res.ok) { failed++; lastErr = res.error }
                if (--left > 0) return
                root.working = false
                root.lastError = failed ? (failed === jobs.length ? lastErr : failed + " of " + jobs.length + " didn't work: " + lastErr) : ""
                sync()
                if (done) done({ ok: failed === 0, failed: failed, error: lastErr })
            })
    }
    // onlyThis: repeating ones lose only that occurrence (else the whole series, once)
    function deleteMany(list, onlyThis, done) {
        const seen = {}
        const jobs = []
        for (const ev of list) {
            if (ev.recurring && !onlyThis) { if (seen[ev.calendar + "|" + ev.uid]) continue; seen[ev.calendar + "|" + ev.uid] = true }
            dropPendingMove(ev.id)
            jobs.push({ cmd: "delete", request: { account: accountOf(ev.calendar), calendar: calendarOf(ev.calendar), event: ev, occurrence: onlyThis && !!ev.recurring } })
        }
        bulk(jobs, done)
    }
    function moveManyTo(list, calId, done) {
        bulk(list.filter(ev => ev.calendar !== calId).map(ev => {
            dropPendingMove(ev.id)
            return { cmd: "save", request: { account: accountOf(calId), calendar: calendarOf(calId), event: Object.assign({}, ev, { scope: "all" }) } }
        }), done)
    }
    // copies (a new event each, no guests): days later, or the same time when 0
    function duplicateMany(list, days, done) {
        bulk(list.filter(ev => !(calendarMap[ev.calendar]?.readOnly ?? true)).map(ev => {
            const s = new Date(ev.start); s.setDate(s.getDate() + days)
            const e = new Date(ev.end); e.setDate(e.getDate() + days)
            const copy = { title: ev.title, start: s.getTime(), end: e.getTime(), allDay: ev.allDay, location: ev.location ?? "",
                           description: ev.description ?? "", scope: "all" }
            return { cmd: "save", request: { account: accountOf(ev.calendar), calendar: calendarOf(ev.calendar), event: copy } }
        }), done)
    }
}
