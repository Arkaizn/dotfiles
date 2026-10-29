pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services.lib
import qs.services

// Data side of the mail app (modules/mail).
//
// Network work is done by scripts/mail/mailsync.py (IMAP + SMTP); this keeps the
// accounts, the cached message list and runs the requests in four lanes (checking
// for mail, opening messages, changes, setup), so opening a message never waits for a check.
//
// Per device, outside the dotfiles (Quickshell.stateDir/mail):
//   accounts.json  accounts + their folders (no passwords, those are in the keyring)
//   cache.json     folder states + message summaries, so the app opens instantly / offline
//   book.json      collected addresses (to complete To / Cc) + senders allowed to load remote content
//   drafts.json    unsent messages, saved while typing
//   bodies/        messages (.eml, opened or fetched ahead by the check), at most 400 MB (mailsync prunes)
//
// Changes (read, star, move, delete) show at once and go to the server in the
// background; one that fails is put back. A check that ran meanwhile can't undo
// them: they're laid over its result until the server has them.
//
//   qs ipc call mail open | toggle | close | check | compose <to> | mailto <url> | unread
Singleton {
    id: root

    readonly property string dir: Quickshell.stateDir + "/mail"
    readonly property string bodyDir: dir + "/bodies"
    readonly property string composeDir: dir + "/compose"        // pictures pasted into messages being written
    readonly property string script: Quickshell.shellDir + "/scripts/mail/mailsync.py"
    readonly property int limit: 300

    // [{ id, name, email, displayName, username, provider, color, signature, enabled, notify,
    //    imap: { host, port, security }, smtp: { … }, folders: [{ path, name, role, depth, unread, total }] }]
    property var accounts: []
    property var folderState: ({})       // "acc|path" → { uidvalidity, uids, total, unread, synced }
    property var messages: []            // summaries + { id, account, folder }
    property var book: []                // [{ name, email, used, count }]
    property var remoteOk: []            // sender addresses whose remote content loads
    property var drafts: []
    property var errors: ({})            // account id → message (last check)
    property bool syncing: false
    property double lastSync: 0
    property string lastError: ""

    readonly property var activeAccounts: accounts.filter(a => a.enabled !== false)
    readonly property var accountMap: {
        const m = {}
        for (const a of accounts) m[a.id] = a
        return m
    }

    // ── Settings (settings app → Mail) ───────────────────────────────────────
    readonly property int checkMinutes: parseInt(Settings.mail.checkMinutes ?? "5") || 5
    readonly property bool notifyOn: Settings.mail.notify ?? true
    readonly property string sound: Settings.mail.sound ?? "message"
    readonly property bool preferHtml: (Settings.mail.format ?? "html") === "html"
    readonly property bool remoteDefault: Settings.mail.remoteContent ?? false
    readonly property string readDelay: Settings.mail.markRead ?? "2"
    readonly property bool threaded: Settings.mail.threads ?? true
    readonly property string saveDir: Settings.mail.saveDir ?? "~/Downloads"
    readonly property bool solid: Settings.mail.solid ?? false
    readonly property string style: Settings.mail.style ?? "original"           // original | dark
    readonly property bool inlineAttachments: Settings.mail.inlineAttachments ?? true
    readonly property int undoSeconds: parseInt(Settings.mail.undo ?? "5") || 0
    readonly property bool attachmentReminder: Settings.mail.attachmentReminder ?? true
    // the sidebar's favorites: unified views switched on in the settings (favInbox, favSent, …)
    readonly property var favDefaults: ({ inbox: true, unread: true, flagged: true, sent: false, drafts: false, archive: false, trash: false, junk: false })
    readonly property var favKeys: ({ inbox: "favInbox", unread: "favUnread", flagged: "favStarred", sent: "favSent", drafts: "favDrafts",
                                      archive: "favArchive", trash: "favTrash", junk: "favJunk" })
    readonly property var favorites: Object.keys(favDefaults).filter(r => Settings.mail[favKeys[r]] ?? favDefaults[r])
    // folders of a role shown together ("unified:sent" …)
    readonly property var roleViews: ["sent", "drafts", "archive", "trash", "junk"]
    // a unified view switched on: its folders get checked right away
    onFavoritesChanged: if (root.lastSync > 0) Qt.callLater(root.check)

    // ── Local changes laid over the server's state ───────────────────────────
    // id → { seen?, flagged?, answered?, gone?, done: ms (0 = still being sent) }
    property var local: ({})

    function key(acc, path) { return acc + "|" + path }
    function patched(m) {
        const p = root.local[m.id]
        return p ? Object.assign({}, m, p) : m
    }
    // what the views use
    readonly property var visibleMessages: {
        const out = []
        const on = {}
        for (const a of activeAccounts) on[a.id] = true
        for (const m of messages) {
            if (!on[m.account]) continue
            const p = local[m.id]
            if (p && p.gone) continue
            out.push(p ? Object.assign({}, m, p) : m)
        }
        out.sort((a, b) => b.date - a.date)
        return out
    }
    readonly property var byId: {
        const m = {}
        for (const x of visibleMessages) m[x.id] = x
        return m
    }

    function folderOf(acc, role) {
        const a = accountMap[acc]
        return a ? (a.folders ?? []).find(f => f.role === role)?.path ?? "" : ""
    }
    function inboxOf(acc) { return folderOf(acc, "inbox") || "INBOX" }

    // "unified:inbox" (all inboxes), "unified:flagged" (starred anywhere), "unified:sent" (every
    // account's sent folder; also drafts, archive, trash, junk) or "acc|path"
    function messagesIn(view) {
        if (view === "unified:inbox") return visibleMessages.filter(m => m.folder === inboxOf(m.account))
        if (view === "unified:unread") return visibleMessages.filter(m => !m.seen && m.folder === inboxOf(m.account))
        if (view === "unified:flagged") return visibleMessages.filter(m => m.flagged)
        if (view.startsWith("unified:")) {
            const role = view.slice(8)
            return visibleMessages.filter(m => m.folder === folderOf(m.account, role))
        }
        const i = view.indexOf("|")
        const acc = view.slice(0, i), path = view.slice(i + 1)
        return visibleMessages.filter(m => m.account === acc && m.folder === path)
    }

    function unreadIn(acc, path) {
        const st = folderState[key(acc, path)]
        const cached = messages.filter(m => m.account === acc && m.folder === path)
        let n = st ? st.unread : 0
        // local reads / unreads / moves not on the server yet
        for (const m of cached) {
            const p = local[m.id]
            if (!p) continue
            const now = p.gone ? false : !(p.seen ?? m.seen)
            n += (now ? 1 : 0) - (m.seen ? 0 : 1)
        }
        return Math.max(0, n)
    }
    readonly property int unread: {
        let n = 0
        for (const a of activeAccounts) n += unreadIn(a.id, inboxOf(a.id))
        return n
    }

    // ── Persistence ──────────────────────────────────────────────────────────
    FileView { id: accountsFile; path: root.dir + "/accounts.json"; blockLoading: true; printErrors: false }
    FileView { id: cacheFile; path: root.dir + "/cache.json"; blockLoading: true; printErrors: false }
    FileView { id: bookFile; path: root.dir + "/book.json"; blockLoading: true; printErrors: false }
    FileView { id: draftsFile; path: root.dir + "/drafts.json"; blockLoading: true; printErrors: false }

    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", root.bodyDir])
        Quickshell.execDetached(["chmod", "700", root.dir])
        try { root.accounts = JSON.parse(accountsFile.text() || "[]") } catch (e) { root.accounts = [] }
        try {
            const c = JSON.parse(cacheFile.text() || "{}")
            root.folderState = c.folders ?? {}
            root.messages = c.messages ?? []
            root.lastSync = c.lastSync ?? 0
        } catch (e) {}
        try {
            const b = JSON.parse(bookFile.text() || "{}")
            root.book = b.addresses ?? []
            root.remoteOk = b.remoteOk ?? []
            root.sentScanned = b.sentScanned ?? false
        } catch (e) {}
        try { root.drafts = JSON.parse(draftsFile.text() || "[]") } catch (e) { root.drafts = [] }
        // attachments opened / forwarded earlier: only needed while it happened
        Jobs.run(["sh", "-c", 'find "$1/open" "$1/forward" -mindepth 1 -mtime +1 -delete 2>/dev/null; true', "sh", root.dir], () => {})
        // pictures pasted into messages: kept a month (for drafts)
        Jobs.run(["sh", "-c", 'find "$1/compose" -mindepth 1 -mtime +30 -delete 2>/dev/null; true', "sh", root.dir], () => {})
    }

    function saveAccounts() { accountsFile.setText(JSON.stringify(root.accounts, null, 2) + "\n") }
    Timer { id: cacheTimer; interval: 1500; onTriggered: root.writeCache() }
    function saveCache() { cacheTimer.restart() }
    function writeCache() {
        cacheFile.setText(JSON.stringify({ folders: root.folderState, messages: root.messages, lastSync: root.lastSync }))
    }
    function saveBook() { bookFile.setText(JSON.stringify({ addresses: root.book, remoteOk: root.remoteOk, sentScanned: root.sentScanned })) }
    function saveDrafts() { draftsFile.setText(JSON.stringify(root.drafts)) }

    // ── Running mailsync.py: four lanes ──────────────────────────────────────
    // Every request has a time limit (coreutils `timeout`, killed after it), so
    // one stuck server can never block a lane for good. Callers get a handle
    // ({ cancel() }); a cancelled request that hasn't started never runs. The
    // same request asked twice (a message opened again while loading) runs once.
    readonly property var timeouts: ({ "sync": 240, "body": 60, "view": 150, "attachment": 120, "send": 150, "invite": 90,
                                       "search": 90, "flags": 45, "move": 60, "delete": 60, "autoconfig": 40, "test": 60,
                                       "store-secret": 40, "forget-secret": 30, "export": 90, "import-read": 60, "import": 90,
                                       "create-folder": 45 })
    component Lane: QtObject {
        id: lane
        property var queue: []
        property var current: null
        property string script
        property var limits: ({})
        function run(cmd, request, done, dedupeKey) {
            const k = dedupeKey ? cmd + "|" + dedupeKey : ""
            const same = k ? [lane.current].concat(lane.queue).find(j => j && j.key === k) : null
            const job = same ?? { cmd: cmd, request: request, key: k, dones: [] }
            const entry = { fn: done }
            job.dones.push(entry)
            if (!same) { lane.queue = lane.queue.concat([job]); lane.next() }
            return {
                cancel: () => {
                    entry.fn = null
                    if (job !== lane.current && job.dones.every(d => !d.fn)) lane.queue = lane.queue.filter(j => j !== job)
                }
            }
        }
        function next() {
            if (lane.current || lane.queue.length === 0) return
            lane.current = lane.queue[0]
            lane.queue = lane.queue.slice(1)
            const secs = lane.limits[lane.current.cmd] ?? 60
            proc.environment = { MAIL_REQUEST: JSON.stringify(lane.current.request) }
            proc.command = ["timeout", "-k", "5", String(secs), "python3", "-I", lane.script, lane.current.cmd]
            proc.running = true
        }
        property Process proc: Process {
            stdout: StdioCollector { id: laneOut }
            stderr: StdioCollector { id: laneErr }
            onExited: code => {
                const job = lane.current
                let res
                if (code === 124 || code === 137) res = { ok: false, timedOut: true, error: "The server took too long to answer — try again in a moment" }
                else {
                    try { res = JSON.parse(laneOut.text) }
                    catch (e) { res = { ok: false, error: (laneErr.text.trim().split("\n").pop() || "mail helper failed (exit " + code + ")") } }
                }
                lane.current = null
                if (job) for (const d of job.dones) if (d.fn) d.fn(res)
                lane.next()
            }
        }
    }
    Lane { id: syncLane; script: root.script; limits: root.timeouts }
    Lane { id: readLane; script: root.script; limits: root.timeouts }      // opening messages, attachments
    Lane { id: actLane; script: root.script; limits: root.timeouts }       // changes, sending
    Lane { id: toolLane; script: root.script; limits: root.timeouts }      // account setup, export / import
    readonly property bool busy: actLane.current !== null || actLane.queue.length > 0

    // ── Accounts ─────────────────────────────────────────────────────────────
    readonly property var palette: ["#7aa2f7", "#9ece6a", "#e0af68", "#f7768e", "#bb9af7", "#7dcfff", "#ff9e64", "#73daca"]
    function newAccountId() { return "mail-" + Date.now().toString(36) }

    function autoconfig(address, done) { toolLane.run("autoconfig", { email: address }, done) }

    // account (without folders) + password: test the login, store the password, add it
    function testAccount(acc, password, done) { toolLane.run("test", { account: acc, password: password }, done) }

    // also for editing one (same id); an empty password keeps the stored one
    function addAccount(acc, password, folders, done) {
        const store = password ? (cb => toolLane.run("store-secret", { id: acc.id, label: "Quickshell mail: " + acc.email, password: password }, cb))
                               : (cb => cb({ ok: true }))
        store(res => {
            if (!res.ok) { done(res); return }
            const a = Object.assign({ enabled: true, notify: true, signature: "",
                                      color: root.palette[root.accounts.length % root.palette.length] }, acc,
                                    { folders: folders.map(f => ({ path: f.path, name: f.name, role: f.role, depth: f.depth,
                                                                   unread: f.unread ?? 0, total: f.total ?? 0 })) })
            const i = root.accounts.findIndex(x => x.id === acc.id)
            root.accounts = i >= 0 ? root.accounts.map(x => x.id === acc.id ? Object.assign({}, x, a) : x) : root.accounts.concat([a])
            saveAccounts()
            done({ ok: true })
            check()
        })
    }

    // folders pinned to the sidebar's favorites (per account: folder paths)
    function isPinned(acc, path) { return (root.accountMap[acc]?.pinned ?? []).includes(path) }
    function togglePin(acc, path) {
        const now = root.accountMap[acc]?.pinned ?? []
        setAccount(acc, { pinned: now.includes(path) ? now.filter(p => p !== path) : now.concat([path]) })
    }
    readonly property var pinnedViews: {
        const out = []
        for (const a of activeAccounts)
            for (const p of a.pinned ?? []) {
                const f = (a.folders ?? []).find(f => f.path === p)
                if (f) out.push({ view: a.id + "|" + p, account: a, folder: f })
            }
        return out
    }

    function setAccount(id, patch) {
        root.accounts = root.accounts.map(a => a.id === id ? Object.assign({}, a, patch) : a)
        saveAccounts()
        if (patch.enabled === true) check()
    }

    // a new folder on the server: name (one level) inside parent ("" = top level);
    // done({ ok, path, error }) — the account's folder list is the server's one after it
    function createFolder(accId, name, parent, done) {
        const acc = root.accountMap[accId]
        if (!acc) return done({ ok: false, error: "No such account" })
        actLane.run("create-folder", { account: wire(acc), name: name, parent: parent }, res => {
            if (res.ok) setAccount(accId, { folders: res.folders })
            done(res)
        })
    }

    function removeAccount(id) {
        toolLane.run("forget-secret", { id: id }, () => {})
        root.accounts = root.accounts.filter(a => a.id !== id)
        root.messages = root.messages.filter(m => m.account !== id)
        const fs = {}
        for (const k in root.folderState) if (!k.startsWith(id + "|")) fs[k] = root.folderState[k]
        root.folderState = fs
        const e = Object.assign({}, root.errors); delete e[id]; root.errors = e
        saveAccounts()
        saveCache()
    }

    // the account as mailsync.py wants it (no folders, no UI fields)
    function wire(acc) {
        return { id: acc.id, name: acc.name, email: acc.email, displayName: acc.displayName ?? "", username: acc.username,
                 provider: acc.provider ?? "", imap: acc.imap, smtp: acc.smtp }
    }

    // ── Checking for mail ────────────────────────────────────────────────────
    // folders the window has open (synced too, besides each inbox)
    property var watched: []
    property double lastList: 0
    property double syncStarted: 0
    property bool syncAgain: false

    function watch(view) {
        if (!view || view.startsWith("unified:") || root.watched.includes(view)) return
        root.watched = root.watched.concat([view]).slice(-6)
    }

    function check(listFolders) {
        if (root.syncing) { root.syncAgain = true; return }
        if (root.activeAccounts.length === 0) return
        const list = listFolders === true || Date.now() - root.lastList > 30 * 60000
        if (list) root.lastList = Date.now()
        const entries = root.activeAccounts.map(a => {
            // the inbox and the folders open in the window: their newest bodies are fetched ahead too
            const paths = [inboxOf(a.id)]
            for (const v of root.watched)
                if (v.startsWith(a.id + "|") && !paths.includes(v.slice(a.id.length + 1))) paths.push(v.slice(a.id.length + 1))
            const ahead = paths.length
            // sent (addresses for completing To / Cc) and the folders of the favorites' unified views
            for (const r of ["sent"].concat(root.favorites.filter(f => root.roleViews.includes(f)))) {
                const p = folderOf(a.id, r)
                if (p && !paths.includes(p)) paths.push(p)
            }
            return {
                account: wire(a), listFolders: list || (a.folders ?? []).length === 0,
                folders: paths.map((p, i) => {
                    const st = root.folderState[key(a.id, p)]
                    return Object.assign(st ? { path: p, uidvalidity: st.uidvalidity, uids: st.uids } : { path: p }, { prefetch: i < ahead })
                })
            }
        })
        root.syncing = true
        root.syncStarted = Date.now()
        const started = root.syncStarted
        syncLane.run("sync", { accounts: entries, limit: root.limit, cache: root.bodyDir }, res => {
            root.syncing = false
            if (res.ok) apply(res.results, started)
            else {
                const e = {}
                for (const a of root.activeAccounts) e[a.id] = res.error
                root.errors = e
            }
            if (root.syncAgain) { root.syncAgain = false; check() }
        })
    }

    function apply(results, started) {
        let msgs = root.messages
        const fs = Object.assign({}, root.folderState)
        const errs = {}
        const fresh = []
        const sentNew = []
        let accs = root.accounts
        for (const r of results) {
            if (r.error) { errs[r.account] = r.error; continue }
            if (r.folderList) {
                accs = accs.map(a => a.id === r.account ? Object.assign({}, a, { folders: r.folderList }) : a)
                // folders that are gone: their cache goes too
                const paths = r.folderList.map(f => f.path)
                msgs = msgs.filter(m => m.account !== r.account || paths.includes(m.folder))
            }
            for (const f of r.folders) {
                if (f.error) { errs[r.account] = f.path + ": " + f.error; continue }
                const k = key(r.account, f.path)
                const old = fs[k]
                const reset = !old || old.uidvalidity !== f.uidvalidity
                const keep = {}
                for (const u of f.uids) keep[u] = true
                const maxOld = old && !reset ? Math.max(0, ...old.uids) : Infinity
                msgs = msgs.filter(m => !(m.account === r.account && m.folder === f.path) || (!reset && keep[m.uid]))
                msgs = msgs.map(m => {
                    if (m.account !== r.account || m.folder !== f.path) return m
                    const fl = f.flags[m.uid]
                    return fl ? Object.assign({}, m, fl) : m
                })
                if (f.path === folderOf(r.account, "sent")) sentNew.push(...f.new)
                for (const n of f.new) {
                    const id = r.account + "|" + f.path + "|" + n.uid
                    const m = Object.assign({}, n, { id: id, account: r.account, folder: f.path })
                    msgs.push(m)
                    if (n.uid > maxOld && !n.seen && f.path === inboxOf(r.account)) fresh.push(m)
                }
                fs[k] = { uidvalidity: f.uidvalidity, uids: f.uids, total: f.total, unread: f.unread, synced: Date.now() }
            }
        }
        if (accs !== root.accounts) { root.accounts = accs; saveAccounts() }
        root.messages = msgs
        root.folderState = fs
        root.errors = errs
        root.lastSync = Date.now()
        // local changes the server had before this check started are in its result now
        const l = {}
        for (const id in root.local) if (!root.local[id].done || root.local[id].done > started) l[id] = root.local[id]
        root.local = l
        saveCache()
        collect(fresh.map(m => m.from))
        // people written to: new sent messages; the first time, everything in the sent folders once
        if (!root.sentScanned) {
            collectSent(root.messages.filter(m => m.folder === folderOf(m.account, "sent")))
            root.sentScanned = true
            saveBook()
        } else collectSent(sentNew)
        if (fresh.length > 0) announce(fresh)
    }

    Timer {
        interval: root.checkMinutes * 60000
        repeat: true
        running: root.activeAccounts.length > 0
        onTriggered: root.check()
    }
    // first check a little after startup
    Timer {
        interval: 10000
        running: root.activeAccounts.length > 0
        onTriggered: root.check(true)
    }

    // ── New mail ─────────────────────────────────────────────────────────────
    signal openRequested(string id)

    function announce(fresh) {
        if (!root.notifyOn) return
        const list = fresh.filter(m => root.accountMap[m.account]?.notify !== false)
        if (list.length === 0) return
        playSound()
        if (list.length > 3) {
            const names = []
            for (const m of list) { const n = MailUtil.displayName(m.from); if (!names.includes(n)) names.push(n) }
            notify(list.length + " new messages", names.slice(0, 4).join(", ") + (names.length > 4 ? ", …" : ""), "")
            return
        }
        for (const m of list)
            notify(MailUtil.displayName(m.from) || "New message", (m.subject || "(no subject)") + (m.preview ? "\n" + m.preview.slice(0, 120) : ""), m.id)
    }

    // like Thunderbird 140: "Mark as read" / "Delete" right on the notification
    function notify(title, body, id) {
        // --wait: the click (default action) opens the message (or the inbox)
        const actions = ["--action=default=Open"].concat(id ? ["--action=read=Mark as read", "--action=delete=Delete"] : [])
        Jobs.run(["notify-send", "--app-name=Mail", "--icon=" + Quickshell.shellDir + "/modules/mail/mail.svg", "--expire-time=10000"].concat(actions, [title, body, "--wait"]),
                 (code, out) => {
                     const a = out.trim()
                     if (code !== 0 || !a) return
                     const m = id ? root.byId[id] : null
                     if (a === "read" && m) markRead([m], true)
                     else if (a === "delete" && m) remove([m], true)
                     else if (a === "default" && id) Panels.call("mail", "showMessage", id)
                     else if (a === "default") Panels.call("mail", "open")
                 }, { LC_ALL: "C.UTF-8" })
    }

    readonly property var sounds: ({ message: "message-new-instant", bell: "bell", complete: "complete", alarm: "alarm-clock-elapsed" })
    function playSound(name) {
        const file = root.sounds[name ?? root.sound]
        if (!file || (name === undefined && Notifs.dnd)) return
        Jobs.run(["pw-play", "/usr/share/sounds/freedesktop/stereo/" + file + ".oga"], () => {})
    }

    // ── Opening a message ────────────────────────────────────────────────────
    // done({ ok, text, html, attachments, headers, remoteBlocked }); returns a
    // handle ({ cancel() }) — cancel it when the card goes away. The .eml is kept
    // on disk (mailsync, also fetched ahead by the check) and the newest answers
    // here in memory, so going back to a message shows it at once.
    property var bodyMemo: ({})
    property var bodyOrder: []
    function bodyKey(m, remote) {
        return [m.account, m.folder, uvOf(m), m.uid, remote ? 1 : 0, root.style].join("|")
    }
    function uvOf(m) { return root.folderState[key(m.account, m.folder)]?.uidvalidity ?? 0 }
    function loadBody(m, allowRemote, done) {
        const acc = root.accountMap[m.account]
        if (!acc) { done({ ok: false, error: "The account is gone" }); return { cancel: () => {} } }
        const remote = allowRemote || root.remoteDefault || root.remoteOk.includes((m.from?.email ?? "").toLowerCase())
        const k = bodyKey(m, remote)
        if (root.bodyMemo[k]) { done(root.bodyMemo[k]); return { cancel: () => {} } }
        return readLane.run("body", { account: wire(acc), folder: m.folder, uid: m.uid, uidvalidity: uvOf(m), cache: root.bodyDir,
                                      style: root.style, allowRemote: remote }, res => {
            if (res.ok) {
                const memo = Object.assign({}, root.bodyMemo)
                memo[k] = res
                let order = root.bodyOrder.filter(x => x !== k).concat([k])
                while (order.length > 60) { delete memo[order[0]]; order = order.slice(1) }
                root.bodyMemo = memo
                root.bodyOrder = order
            }
            done(res)
        }, k)
    }

    function allowRemoteFrom(address) {
        const a = String(address || "").toLowerCase()
        if (!a || root.remoteOk.includes(a)) return
        root.remoteOk = root.remoteOk.concat([a])
        saveBook()
    }

    // dest: a folder (default the download folder); open: then open it with the default app
    function saveAttachment(m, index, open, done) {
        const acc = root.accountMap[m.account]
        const dest = open ? root.dir + "/open" : root.saveDir
        readLane.run("attachment", { account: wire(acc), folder: m.folder, uid: m.uid, uidvalidity: uvOf(m), cache: root.bodyDir,
                                     index: index, dest: dest, overwrite: open }, res => {
            if (res.ok && open) Qt.openUrlExternally("file://" + res.path)
            if (done) done(res)
        })
    }

    // a forwarded message's attachments, saved to attach them again: done(paths, errors)
    function fetchAttachments(m, list, done) {
        const acc = root.accountMap[m.account]
        const dest = root.dir + "/forward/" + Date.now().toString(36)
        let left = list.length
        const paths = [], errs = []
        if (left === 0) { done(paths, errs); return }
        for (const a of list)
            readLane.run("attachment", { account: wire(acc), folder: m.folder, uid: m.uid, uidvalidity: uvOf(m), cache: root.bodyDir,
                                         index: a.index, dest: dest }, res => {
                if (res.ok) paths.push(res.path); else errs.push(a.name + ": " + res.error)
                if (--left === 0) done(paths, errs)
            })
    }

    // ── Changes ──────────────────────────────────────────────────────────────
    function patchLocal(ids, patch) {
        const l = Object.assign({}, root.local)
        for (const id of ids) l[id] = Object.assign({}, l[id] ?? {}, patch, { done: 0 })
        root.local = l
    }
    function settle(ids, ok) {
        const l = Object.assign({}, root.local)
        for (const id of ids) {
            if (!l[id]) continue
            if (ok) l[id] = Object.assign({}, l[id], { done: Date.now() })
            else delete l[id]
        }
        root.local = l
    }

    // messages of one account + folder each get one request
    function grouped(list) {
        const g = {}
        for (const m of list) {
            const k = key(m.account, m.folder)
            ;(g[k] = g[k] || { account: m.account, folder: m.folder, msgs: [] }).msgs.push(m)
        }
        return Object.values(g)
    }

    function setFlag(list, flag, on) {
        const patch = {}
        patch[flag] = on
        const todo = list.filter(m => m[flag] !== on)
        if (todo.length === 0) return
        patchLocal(todo.map(m => m.id), patch)
        // collected for a moment: reading through ten messages is one request, not ten
        const p = Object.assign({}, root.pendingFlags)
        for (const g of grouped(todo)) {
            const base = key(g.account, g.folder) + "|" + flag + "|"
            const other = p[base + !on]
            if (other) other.msgs = other.msgs.filter(m => !g.msgs.some(x => x.id === m.id))
            const k = base + on
            p[k] = p[k] ?? { account: g.account, folder: g.folder, flag: flag, on: on, msgs: [] }
            p[k].msgs = p[k].msgs.filter(m => !g.msgs.some(x => x.id === m.id)).concat(g.msgs)
        }
        root.pendingFlags = p
        flagTimer.restart()
    }
    property var pendingFlags: ({})
    Timer { id: flagTimer; interval: 1500; onTriggered: root.flushFlags() }
    function flushFlags() {
        flagTimer.stop()
        const p = root.pendingFlags
        root.pendingFlags = {}
        for (const k in p) {
            const g = p[k]
            const acc = root.accountMap[g.account]
            if (!acc || g.msgs.length === 0) { settle(g.msgs.map(m => m.id), false); continue }
            actLane.run("flags", { account: wire(acc), folder: g.folder, uids: g.msgs.map(m => m.uid),
                                   add: g.on ? [g.flag] : [], remove: g.on ? [] : [g.flag] }, res => {
                settle(g.msgs.map(m => m.id), res.ok)
                if (!res.ok) root.lastError = res.error
            })
        }
    }
    function markRead(list, on) { setFlag(list, "seen", on) }
    function star(list, on) { setFlag(list, "flagged", on) }

    // ── Undo (archive / delete / move) ───────────────────────────────────────
    // The messages go away at once; the server only gets the change after a few
    // seconds (Settings: mail → undo), so "Undo" just puts them back.
    property var undoable: null              // { label, ids, commits: [fn], restore: fn (optional) }
    Timer { id: undoTimer; onTriggered: root.flushUndo() }
    function later(label, ids, commits) {
        patchLocal(ids, { gone: true })
        if (root.undoSeconds <= 0) { for (const c of commits) c(); return }
        flushUndo()                           // the one before can't be undone any more
        root.undoable = { label: label, ids: ids, commits: commits }
        undoTimer.interval = root.undoSeconds * 1000
        undoTimer.restart()
    }
    function flushUndo() {
        undoTimer.stop()
        const u = root.undoable
        root.undoable = null
        if (u) for (const c of u.commits) c()
    }
    function undo() {
        undoTimer.stop()
        const u = root.undoable
        root.undoable = null
        if (u) { settle(u.ids, false); if (u.restore) u.restore() }
    }

    function count(n) { return n + (n === 1 ? " message" : " messages") }

    // to: a folder path, or a role ("archive", "junk", "trash", "inbox"); now: no undo
    function moveTo(list, to, now) {
        flushFlags()
        const commits = [], ids = []
        for (const g of grouped(list)) {
            const acc = root.accountMap[g.account]
            const dest = ["archive", "junk", "trash", "inbox"].includes(to) ? (folderOf(g.account, to) || (to === "inbox" ? "INBOX" : "")) : to
            if (!dest) { root.lastError = acc.name + " has no " + to + " folder"; continue }
            if (dest === g.folder) continue
            const gids = g.msgs.map(m => m.id)
            ids.push(...gids)
            commits.push(() => actLane.run("move", { account: wire(acc), folder: g.folder, uids: g.msgs.map(m => m.uid), to: dest }, res => {
                settle(gids, res.ok)
                if (!res.ok) root.lastError = res.error
                else if (root.watched.includes(key(g.account, dest))) check()
            }))
        }
        if (commits.length === 0) return
        const label = (to === "archive" ? "Archived " : to === "junk" ? "Moved to junk: " : to === "trash" ? "Deleted " : "Moved ") + count(ids.length)
        if (now) { patchLocal(ids, { gone: true }); for (const c of commits) c() }
        else later(label, ids, commits)
    }

    // to the trash, or for good when already there
    function remove(list, now) {
        flushFlags()
        const commits = [], ids = []
        for (const g of grouped(list)) {
            const acc = root.accountMap[g.account]
            const gids = g.msgs.map(m => m.id)
            ids.push(...gids)
            commits.push(() => actLane.run("delete", { account: wire(acc), folder: g.folder, uids: g.msgs.map(m => m.uid),
                                                       trash: folderOf(g.account, "trash") }, res => {
                settle(gids, res.ok)
                if (!res.ok) root.lastError = res.error
            }))
        }
        if (commits.length === 0) return
        if (now) { patchLocal(ids, { gone: true }); for (const c of commits) c() }
        else later("Deleted " + count(ids.length), ids, commits)
    }

    function markAllRead(view) { markRead(messagesIn(view).filter(m => !m.seen), true) }

    // ── Viewing attachments ──────────────────────────────────────────────────
    // done({ ok, kind: image|pdf|text|other, path, name, type, size, pages, pageCount, text })
    function view(m, index, done) {
        const acc = root.accountMap[m.account]
        if (!acc) return
        readLane.run("view", { account: wire(acc), folder: m.folder, uid: m.uid, uidvalidity: uvOf(m), cache: root.bodyDir, index: index }, done)
    }

    // an invitation (.ics) → the calendar's import dialog
    function addToCalendar(m, index, done) {
        const acc = root.accountMap[m.account]
        readLane.run("attachment", { account: wire(acc), folder: m.folder, uid: m.uid, uidvalidity: uvOf(m), cache: root.bodyDir,
                                     index: index, dest: root.dir + "/open", overwrite: true }, res => {
            if (res.ok) Panels.call("calendar", "importFile", res.path)
            if (done) done(res)
        })
    }

    // ── Calendar invitations ─────────────────────────────────────────────────
    // event: { uid, title, start, end, allDay, location, description, sequence, attendees, rrule }
    function sendInvite(accountId, event, method, done) {
        const acc = root.accountMap[accountId]
        if (!acc) { done({ ok: false, error: "No mail account to send the invitation from" }); return }
        actLane.run("invite", { account: wire(acc), event: event, method: method, sentFolder: folderOf(acc.id, "sent") }, res => {
            if (res.ok) collect(event.attendees ?? [])
            done(res)
        })
    }

    // ── Moving accounts to another device ────────────────────────────────────
    function exportAccounts(ids, withPasswords, passphrase, path, done) {
        const list = root.accounts.filter(a => ids.includes(a.id)).map(a => Object.assign(wire(a), {
            signature: a.signature ?? "", color: a.color ?? "", notify: a.notify !== false }))
        toolLane.run("export", { accounts: list, withPasswords: withPasswords, passphrase: passphrase, path: path }, done)
    }
    function importRead(path, passphrase, done) { toolLane.run("import-read", { path: path, passphrase: passphrase }, done) }
    // emails: the ones to take; an account with the same address is updated (keeps its id and cache)
    function importAccounts(path, passphrase, emails, done) {
        const pick = {}
        for (const e of emails) pick[e] = root.accounts.find(a => a.email.toLowerCase() === e.toLowerCase())?.id ?? newAccountId() + "-" + Object.keys(pick).length
        toolLane.run("import", { path: path, passphrase: passphrase, pick: pick }, res => {
            if (res.ok) {
                let accs = root.accounts
                for (const a of res.accounts) {
                    const clean = Object.assign({}, a)
                    delete clean.passwordStored
                    const i = accs.findIndex(x => x.id === a.id)
                    if (i >= 0) accs = accs.map(x => x.id === a.id ? Object.assign({}, x, clean) : x)
                    else accs = accs.concat([Object.assign({ enabled: true, folders: [],
                                                             color: a.color || root.palette[accs.length % root.palette.length] }, clean)])
                }
                root.accounts = accs
                saveAccounts()
                check(true)
            }
            done(res)
        })
    }

    // ── Email links (mailto:) → this app, through the settings app's default apps ─
    readonly property string desktopId: "quickshell-mail.desktop"
    readonly property bool isMailtoHandler: DefaultApps.current["mail"] === root.desktopId
    function useForMailto(done) {
        DefaultApps.refresh(() => {
            if (!(DefaultApps.candidates["mail"] ?? []).includes(root.desktopId)) {
                if (done) done(false, "The Mail launcher entry isn't installed — run scripts/install-desktop-entries.sh")
                return
            }
            DefaultApps.set("mail", root.desktopId, ok => { if (done) done(ok, ok ? "" : DefaultApps.error) })
        })
    }

    // server search in one folder (the local filter covers the cached ones)
    function search(view, query, done) {
        const i = view.indexOf("|")
        if (i < 0) { done({ ok: true, uids: [] }); return }
        const acc = root.accountMap[view.slice(0, i)], path = view.slice(i + 1)
        const known = root.messages.filter(m => m.account === acc.id && m.folder === path).map(m => m.uid)
        readLane.run("search", { account: wire(acc), folder: path, query: query, known: known }, res => {
            if (res.ok && res.messages.length) {
                root.messages = root.messages.concat(res.messages.map(n =>
                    Object.assign({}, n, { id: acc.id + "|" + path + "|" + n.uid, account: acc.id, folder: path })))
                saveCache()
            }
            done(res)
        })
    }

    // ── Sending ──────────────────────────────────────────────────────────────
    // draft: { account, to, cc, bcc ([{name, email}]), subject, text, attachments, inReplyTo, references, replyTo }
    function send(draft, done) {
        const acc = root.accountMap[draft.account]
        if (!acc) { done({ ok: false, error: "Pick the account to send from" }); return }
        const message = {
            to: draft.to, cc: draft.cc, bcc: draft.bcc, subject: draft.subject, text: draft.text,
            html: draft.html ?? "", inlineDir: root.composeDir,
            attachments: draft.attachments, inReplyTo: draft.inReplyTo, references: draft.references, replyTo: draft.replyTo
        }
        actLane.run("send", { account: wire(acc), message: message, sentFolder: folderOf(acc.id, "sent") }, res => {
            if (res.ok) {
                collect((draft.to ?? []).concat(draft.cc ?? [], draft.bcc ?? []))
                if (draft.replyTo?.id) patchLocal([draft.replyTo.id], { [draft.replyTo.flag === "forwarded" ? "forwarded" : "answered"]: true })
                if (draft.id) dropDraft(draft.id)
            }
            done(res)
        })
    }

    // sent: people you wrote to (first when completing To / Cc); at: when (default now)
    function collect(addrs, sent, at) {
        const mine = root.accounts.map(a => a.email.toLowerCase())
        const list = (addrs ?? []).filter(a => a && a.email && !mine.includes(a.email.toLowerCase()))
        if (list.length === 0) return
        root.book = MailUtil.collect(root.book, list, at || Date.now(), !!sent)
        saveBook()
    }
    // recipients of sent messages (from any mail app) → the address book
    function collectSent(msgs) {
        let book = root.book
        const mine = root.accounts.map(a => a.email.toLowerCase())
        for (const m of msgs) {
            const list = (m.to ?? []).concat(m.cc ?? []).filter(a => a && a.email && !mine.includes(a.email.toLowerCase()))
            if (list.length) book = MailUtil.collect(book, list, m.date || Date.now(), true)
        }
        if (book === root.book) return
        root.book = book
        saveBook()
    }
    property bool sentScanned: false

    function putDraft(d) {
        const i = root.drafts.findIndex(x => x.id === d.id)
        root.drafts = i >= 0 ? root.drafts.map(x => x.id === d.id ? d : x) : root.drafts.concat([d])
        saveDrafts()
    }
    // several unsent drafts at once (the mail list's selection), with Undo
    function dropDrafts(ids) {
        const gone = root.drafts.filter(x => ids.includes(x.id))
        if (gone.length === 0) return
        root.drafts = root.drafts.filter(x => !ids.includes(x.id))
        saveDrafts()
        if (root.undoSeconds <= 0) return
        flushUndo()
        root.undoable = { label: "Deleted " + gone.length + (gone.length === 1 ? " draft" : " drafts"), ids: [], commits: [],
                          restore: () => { root.drafts = root.drafts.concat(gone); saveDrafts() } }
        undoTimer.interval = root.undoSeconds * 1000
        undoTimer.restart()
    }
    function dropDraft(id) {
        root.drafts = root.drafts.filter(x => x.id !== id)
        saveDrafts()
    }
}
