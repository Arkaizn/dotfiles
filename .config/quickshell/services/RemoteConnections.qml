pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services.lib

// Saved SSH / RDP / VNC connections (launcher tab + settings app → Apps →
// Connections).
//
// Settings.connections.list: [{ id, name, type: "ssh" | "rdp" | "vnc", host, port,
//   user, password: "none" | "ask" | "keyring", clipboard, dynres, shareHome,
//   ignoreCert, extra: ["/arg", …], lastUsed }]
//
// Passwords never go into the settings file or a command line:
//   - "keyring": stored with secret-tool (service quickshell-connections, id <id>)
//   - "ask": a zenity password prompt on every connect
//   RDP gets its arguments (incl. /p:) from an environment variable
//   (xfreerdp3 /args-from:env:…), which only you can read, unlike argv.
// SSH uses your keys / agent / ssh's own prompt; VNC uses vncviewer's prompt.
//
//   qs ipc call connections list
//   qs ipc call connections connect "<name>"
Singleton {
    id: root

    readonly property string secretService: "quickshell-connections"
    readonly property string home: Quickshell.env("HOME")
    readonly property string scriptsDir: home + "/.config/custom/scripts"

    readonly property var types: ({
        ssh: { name: "SSH", icon: "󰣀", port: 22, bin: "ssh" },
        rdp: { name: "RDP", icon: "󰢹", port: 3389, bin: "xfreerdp3" },
        vnc: { name: "VNC", icon: "󰍹", port: 5900, bin: "vncviewer" }
    })

    // the saved list, cleaned (anything invalid is left out)
    readonly property var list: {
        const l = Settings.connections.list
        if (!Array.isArray(l)) return []
        return l.filter(c => c && typeof c === "object" && Object.keys(validate(c)).length === 0)
                .map(c => normalize(c))
    }

    function get(id) { return list.find(c => c.id === id) ?? null }
    function newId() { return "c" + Date.now().toString(36) + Math.floor(Math.random() * 1e4).toString(36) }

    function normalize(c) {
        return {
            id: String(c.id), name: String(c.name).trim(), type: c.type,
            host: String(c.host).trim(), port: Number(c.port) || types[c.type].port,
            user: String(c.user ?? "").trim(),
            password: c.type === "rdp" && ["none", "ask", "keyring"].includes(c.password) ? c.password : "none",
            clipboard: c.clipboard ?? true, dynres: c.dynres ?? true,
            shareHome: c.shareHome ?? false, ignoreCert: c.ignoreCert ?? false,
            extra: Array.isArray(c.extra) ? c.extra.map(String) : [],
            lastUsed: Number(c.lastUsed) || 0
        }
    }

    // field → what's wrong (empty object = fine)
    function validate(c) {
        const e = {}
        if (typeof c.id !== "string" || !/^[A-Za-z0-9_-]{1,40}$/.test(c.id)) e.id = "bad id"
        if (typeof c.name !== "string" || c.name.trim() === "") e.name = "enter a name"
        else if (/[\n\r]/.test(c.name) || c.name.length > 80) e.name = "one line, at most 80 characters"
        if (!types[c.type]) e.type = "ssh, rdp or vnc"
        const h = Valid.host(c.host); if (h) e.host = h
        if (c.port !== undefined && c.port !== "") { const p = Valid.port(String(c.port)); if (p) e.port = p }
        const u = String(c.user ?? "")
        if (u.startsWith("-")) e.user = "can't start with \"-\""
        else if (!/^[A-Za-z0-9._@\\-]*$/.test(u)) e.user = "letters, digits, . _ - @ \\ only"
        if (c.extra !== undefined) {
            if (!Array.isArray(c.extra)) e.extra = "must be a list"
            else for (const a of c.extra)
                if (typeof a !== "string" || !/^[/+-]/.test(a) || /[\n\r]/.test(a)) { e.extra = "each argument starts with /, + or - (one line)"; break }
            // the password only ever comes from the keyring / prompt
            if (Array.isArray(c.extra) && c.extra.some(a => /^\/(p|password|pth):/i.test(a))) e.extra = "no /p: here: set Password to keyring or ask"
        }
        return e
    }

    function save(l) { Settings.set("connections", "list", l) }

    // add or replace (by id); returns the errors (empty = saved)
    function put(c) {
        const e = validate(c)
        if (Object.keys(e).length > 0) return e
        const n = normalize(c)
        const l = list.slice()
        const i = l.findIndex(x => x.id === n.id)
        if (i >= 0) l[i] = n; else l.push(n)
        save(l)
        return {}
    }

    function remove(id) {
        save(list.filter(c => c.id !== id))
        clearPassword(id, () => {})
    }

    // ── Keyring ─────────────────────────────────────────────────────────────
    function setPassword(id, name, password, cb) {
        Jobs.runInput(["secret-tool", "store", "--label=Quickshell connection: " + name, "service", secretService, "id", id],
                      password, (code, out, err) => cb(code === 0, err.trim()))
    }
    function clearPassword(id, cb) {
        Jobs.run(["secret-tool", "clear", "service", secretService, "id", id], code => cb(code === 0))
    }
    function hasPassword(id, cb) {
        Jobs.run(["secret-tool", "lookup", "service", secretService, "id", id], (code, out) => cb(code === 0 && out !== ""))
    }

    // ── Connecting ──────────────────────────────────────────────────────────
    signal failed(string id, string message)

    function connect(id) {
        const c = get(id)
        if (!c) return
        const t = types[c.type]
        Jobs.which([t.bin, "kitty", "zenity"], have => {
            if (!have[t.bin]) return fail(c, t.bin + " isn't installed: " + Jobs.installHint(t.bin))
            touch(c.id)
            if (c.type === "ssh") {
                if (!have.kitty) return fail(c, "kitty isn't installed: " + Jobs.installHint("kitty"))
                // -p only when set: 22 would override a Port from ~/.ssh/config
                const args = (c.port !== 22 ? ["-p", String(c.port)] : []).concat(c.user ? ["-l", c.user] : []).concat(["--", c.host])
                // keeps the window open when ssh fails, so you can read why
                detached(["kitty", "--title", c.name, "bash", "-c",
                          'ssh "$@"; code=$?; if [ "$code" -ne 0 ]; then printf "\\nssh exited with %s. Press Enter to close." "$code"; read -r _; fi',
                          "bash"].concat(args), null)
            } else if (c.type === "vnc") {
                detached(["vncviewer", c.host + "::" + c.port], null)
            } else if (c.password === "keyring") {
                Jobs.run(["secret-tool", "lookup", "service", secretService, "id", c.id], (code, out) => {
                    if (code !== 0 || out === "") return fail(c, "no password in the keyring: set it in Settings → Connections")
                    rdp(c, out.replace(/\n$/, ""))
                })
            } else if (c.password === "ask") {
                if (!have.zenity) return fail(c, "zenity isn't installed: " + Jobs.installHint("zenity"))
                Jobs.run(["zenity", "--password", "--title=" + c.name], (code, out) => {
                    if (code === 0) rdp(c, out.replace(/\n$/, ""))
                })
            } else rdp(c, "")
        })
    }

    function rdpArgs(c, password) {
        const a = ["/v:" + c.host + ":" + c.port]
        if (c.user) a.push("/u:" + c.user)
        if (password) a.push("/p:" + password)
        if (c.ignoreCert) a.push("/cert:ignore")
        if (c.dynres) a.push("+dynamic-resolution")
        if (c.clipboard) a.push("+clipboard")
        if (c.shareHome) a.push("/drive:home," + home)
        return a.concat(c.extra)
    }

    function rdp(c, password) {
        if (/[\n\r]/.test(password)) return fail(c, "the password contains a line break")
        // one argument per line in QS_RDP_ARGS; a notification if it can't connect
        // (exit ≥ 128 = connection / auth / DNS error, 6-10 = denied)
        detached(["bash", "-c",
                  'out=$(xfreerdp3 /args-from:env:QS_RDP_ARGS 2>&1 | tail -n 30; exit "${PIPESTATUS[0]}"); code=$?\n'
                + 'if [ "$code" -ge 128 ] || { [ "$code" -ge 6 ] && [ "$code" -le 10 ]; }; then\n'
                + '  notify-send -a Connections -i network-error "$1: could not connect" "$(printf "%s\\n" "$out" | grep ERROR | tail -n 2 | sed "s/^.*\\] - //") (exit $code)"\n'
                + 'fi', "bash", c.name],
                 { QS_RDP_ARGS: rdpArgs(c, password).join("\n") })
    }

    function fail(c, message) {
        failed(c.id, message)
        Jobs.run(["notify-send", "-a", "Connections", "-i", "network-error", c.name + ": can't connect", message])
    }

    function touch(id) {
        save(list.map(c => c.id === id ? Object.assign({}, c, { lastUsed: Date.now() }) : c))
    }

    function detached(argv, env) { Jobs.detached(argv, env) }

    // ── Reachability (only while someone looks: launcher tab / page) ────────
    // id → "up" | "down" | "checking"
    property var reach: ({})
    function probe() {
        Jobs.which(["nc"], have => {
            if (!have.nc) return
            for (const c of list) {
                const id = c.id
                const check = (host, port) => Jobs.run(["nc", "-z", "-w", "2", "--", host, String(port)],
                                                       code => setReach(id, code === 0 ? "up" : "down"))
                setReach(id, "checking")
                if (c.type !== "ssh") { check(c.host, c.port); continue }
                // an ssh alias: ask ssh where it really goes (HostName / Port from ~/.ssh/config)
                Jobs.run(["ssh", "-G"].concat(c.port !== 22 ? ["-p", String(c.port)] : []).concat(["--", c.host]), (code, out) => {
                    const h = /^hostname (.+)$/m.exec(out), p = /^port (\d+)$/m.exec(out)
                    check(h && !Valid.host(h[1]) ? h[1] : c.host, p ? p[1] : c.port)
                })
            }
        })
    }
    function setReach(id, v) { const r = Object.assign({}, reach); r[id] = v; reach = r }

    // ── Import: ~/.config/custom/scripts/*.sh and ~/.ssh/config ─────────────
    // cb([{ conn, password (from a script, to move to the keyring), source, exists }])
    function scanImports(cb) {
        Jobs.run(["sh", "-c", 'for f in "$1"/*.sh; do [ -f "$f" ] && printf "\\n@@FILE %s\\n" "$f" && cat -- "$f"; done', "sh", scriptsDir],
                 (code, out) => {
            const found = []
            let file = ""
            for (const line of out.split("\n")) {
                const m = /^@@FILE (.*)$/.exec(line)
                if (m) { file = m[1]; continue }
                const r = parseScriptLine(line, file)
                if (r) found.push(r)
            }
            for (const r of parseSshConfig(Files.read(home + "/.ssh/config"))) found.push(r)
            for (const r of found) {
                r.exists = list.some(c => c.type === r.conn.type && c.host === r.conn.host
                                          && Number(c.port) === Number(r.conn.port) && c.user === r.conn.user)
                r.errors = validate(r.conn)
            }
            cb(found)
        })
    }

    function parseScriptLine(line, file) {
        const toks = line.trim().split(/\s+/)
        const i = toks.findIndex(t => /^(xfreerdp3?|wlfreerdp3?|sdl-freerdp3?|vncviewer)$/.test(t))
        if (i < 0) return null
        const base = file.replace(/.*\//, "").replace(/\.sh$/, "")
        const src = file.replace(home, "~")
        if (toks[i] === "vncviewer") {
            const t = toks.slice(i + 1).find(x => !x.startsWith("-"))
            if (!t) return null
            const m = /^(.+?)(::(\d+)|:(\d+))?$/.exec(t)
            let port = 5900
            if (m[3]) port = Number(m[3])
            else if (m[4]) port = Number(m[4]) < 100 ? 5900 + Number(m[4]) : Number(m[4])
            return { source: src, password: "", conn: { id: newId(), name: base, type: "vnc", host: m[1], port: port, user: "", extra: [] } }
        }
        const c = { id: newId(), name: base, type: "rdp", host: "", port: 3389, user: "", password: "none",
                    clipboard: false, dynres: false, shareHome: false, ignoreCert: false, extra: [] }
        let password = ""
        for (const t of toks.slice(i + 1)) {
            let m
            if ((m = /^\/v:(.+)$/.exec(t))) {
                const hp = /^(.+?)(?::(\d+))?$/.exec(m[1]); c.host = hp[1]; if (hp[2]) c.port = Number(hp[2])
            } else if ((m = /^\/u:(.+)$/.exec(t))) c.user = m[1].replace(/^["']|["']$/g, "")
            else if ((m = /^\/p:(.+)$/.exec(t))) {
                const v = m[1].replace(/^["']|["']$/g, "")
                if (v.startsWith("$")) c.password = "ask"            // e.g. /p:"$pw" from a zenity prompt
                else { password = v; c.password = "keyring" }
            }
            else if (t === "+clipboard") c.clipboard = true
            else if (t === "+dynamic-resolution") c.dynres = true
            else if (t === "/cert:ignore") c.ignoreCert = true
            else if (/^\/drive:[^,]+,/.test(t) && t.replace(/^\/drive:[^,]+,/, "") === home) c.shareHome = true
            else if (/^[/+-]/.test(t)) c.extra.push(t)
        }
        if (c.host === "") return null
        return { source: src, password: password, conn: c }
    }

    // concrete Host entries (no wildcards); connecting by the alias keeps your
    // ssh config (HostName, User, keys, ProxyJump, …) in charge
    function parseSshConfig(text) {
        const out = []
        let cur = []                        // entries of the current Host line
        for (const raw of text.split("\n")) {
            const line = raw.trim()
            const m = /^(\w+)\s*(?:=\s*|\s+)(.+)$/.exec(line)
            if (!m) continue
            const key = m[1].toLowerCase(), val = m[2].trim()
            if (key === "host" || key === "match") {
                cur = []
                if (key === "match") continue
                for (const alias of val.split(/\s+/)) {
                    if (/[*?!]/.test(alias)) continue
                    cur.push({ source: "~/.ssh/config", password: "",
                               conn: { id: newId(), name: alias, type: "ssh", host: alias, port: 22, user: "", extra: [] } })
                }
                for (const e of cur) out.push(e)
            } else if (key === "port" && /^\d+$/.test(val)) for (const e of cur) e.conn.port = Number(val)
        }
        return out
    }

    // add the chosen import candidates; passwords found in scripts go to the keyring
    function importAll(cands, cb) {
        const l = list.slice()
        let pending = 0, problems = []
        for (const r of cands) {
            if (Object.keys(validate(r.conn)).length > 0) continue
            l.push(normalize(r.conn))
            if (r.password) {
                pending++
                setPassword(r.conn.id, r.conn.name, r.password, (ok, err) => {
                    if (!ok) problems.push(r.conn.name + ": " + (err || "keyring refused"))
                    if (--pending === 0) cb(problems)
                })
            }
        }
        save(l)
        if (pending === 0) cb(problems)
    }

    IpcHandler {
        target: "connections"
        function list(): string {
            return root.list.map(c => c.name + "\t" + c.type + "\t" + (c.user ? c.user + "@" : "") + c.host + ":" + c.port).join("\n")
        }
        function connect(name: string): string {
            const c = root.list.find(x => x.name === name || x.id === name)
            if (!c) return "no connection named " + name
            root.connect(c.id)
            return "connecting to " + c.name
        }
    }
}
