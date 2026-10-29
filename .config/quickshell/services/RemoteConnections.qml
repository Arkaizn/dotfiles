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
//   ignoreCert, smartcard: "off" | "redirect" | "logon", extra: ["/arg", …], lastUsed }]
// Settings.connections.smartcard: smartcards on at all (settings → Connections)
//
// Passwords never go into the settings file or a command line:
//   - "keyring": stored with secret-tool (service quickshell-connections, id <id>)
//   - "ask": the shell's own prompt (SecretPrompt) on every connect
// Smartcards (RDP, xfreerdp3 + pcscd):
//   - "redirect": /smartcard, the card works inside the session (Windows asks for the PIN there)
//   - "logon": /smartcard-logon /sec:nla, log in with the card: its PIN is asked
//     here and handed over like a password (/p: is the PIN then); the user name
//     comes from the certificate when none is set. Several certificates on the
//     card: you pick one, its number goes to xfreerdp3's question on stdin.
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

    readonly property var smartcardModes: ["off", "redirect", "logon"]
    readonly property bool smartcardOn: Settings.connections.smartcard ?? false
    function cardMode(c) { return smartcardOn && c.type === "rdp" ? c.smartcard : "off" }

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
            smartcard: c.type === "rdp" && smartcardModes.includes(c.smartcard) ? c.smartcard : "off",
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
        if (c.smartcard !== undefined && !smartcardModes.includes(c.smartcard)) e.smartcard = "off, redirect or logon"
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
        Jobs.which([t.bin, "kitty"], have => {
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
            } else if (cardMode(c) === "logon") {
                cardLogon(c)
            } else if (c.password === "keyring") {
                Jobs.run(["secret-tool", "lookup", "service", secretService, "id", c.id], (code, out) => {
                    if (code !== 0 || out === "") return fail(c, "no password in the keyring: set it in Settings → Connections")
                    rdp(c, out.replace(/\n$/, ""))
                })
            } else if (c.password === "ask") {
                SecretPrompt.ask({ title: c.name, message: "Password" + (c.user ? " for " + c.user : "") + " on " + c.host,
                                   action: "Connect" }, pw => { if (pw !== null) rdp(c, pw) })
            } else rdp(c, "")
        })
    }

    // ── Smartcards ──────────────────────────────────────────────────────────
    // the certificates xfreerdp3 can log in with (needs pcscd, the card reader
    // driver and a PKCS#11 module, OpenSC by default)
    // cb({ ok, certs: [{ subject, upn, reader }], error })
    function listCards(user, cb) {
        Jobs.run(["xfreerdp3"].concat(user ? ["/u:" + user] : []).concat(["/list:smartcard"]), (code, out, err) => {
            const certs = []
            for (const line of out.split("\n")) {
                let m
                if ((m = /^(\d+): (.*)$/.exec(line))) certs.push({ subject: m[2].trim(), upn: "", reader: "" })
                else if (certs.length && (m = /^\s+\* UPN: (.*)$/.exec(line))) certs[certs.length - 1].upn = m[1].trim()
                else if (certs.length && (m = /^\s+\* reader: (.*)$/.exec(line))) certs[certs.length - 1].reader = m[1].trim()
            }
            const reader = /smartcard reader detected/.test(out)
            cb({ ok: certs.length > 0, certs: certs,
                 error: certs.length > 0 ? "" : reader ? "no certificate on the card (or OpenSC missing)"
                      : "no smartcard found: is it in the reader, is pcscd running?" })
        })
    }

    // pcscd (socket activated), the CCID reader driver, OpenSC
    // cb({ pcscd: "active" | "inactive", ccid: bool, opensc: bool })
    function cardSetup(cb) {
        Jobs.run(["sh", "-c", 'systemctl is-active pcscd.socket pcscd.service | paste -sd " "; '
                            + 'test -e /usr/lib/pcsc/drivers/ifd-ccid.bundle && echo ccid; '
                            + 'test -e /usr/lib/opensc-pkcs11.so -o -e /usr/lib/pkcs11/opensc-pkcs11.so && echo opensc'],
                 (code, out) => {
            const l = out.split("\n")
            cb({ pcscd: /(^| )active( |$)/.test(l[0]) ? "active" : "inactive",
                 ccid: l.includes("ccid"), opensc: l.includes("opensc") })
        })
    }

    function cardLogon(c) {
        listCards(c.user, res => {
            if (!res.ok) return fail(c, res.error)
            const cert = res.certs[0]
            SecretPrompt.ask({
                title: c.name,
                message: "Smartcard PIN" + (res.certs.length === 1 ? " for " + (cert.upn || cert.subject) : ""),
                placeholder: "PIN",
                minLength: 4,
                action: "Connect",
                hint: "The card locks after a few wrong PINs",
                choices: res.certs.map(x => ({ label: x.upn || x.subject, desc: (x.upn ? x.subject + "  ·  " : "") + x.reader }))
            }, (pin, choice) => { if (pin !== null) rdp(c, pin, res.certs.length > 1 ? choice : -1) })
        })
    }

    function rdpArgs(c, password) {
        const a = ["/v:" + c.host + ":" + c.port]
        if (c.user) a.push("/u:" + c.user)
        if (password) a.push("/p:" + password)          // the PIN with a smartcard logon
        const card = cardMode(c)
        if (card === "logon") a.push("/smartcard-logon", "/sec:nla")
        if (card !== "off") a.push("/smartcard")
        if (c.ignoreCert) a.push("/cert:ignore")
        if (c.dynres) a.push("+dynamic-resolution")
        if (c.clipboard) a.push("+clipboard")
        if (c.shareHome) a.push("/drive:home," + home)
        return a.concat(c.extra)
    }

    // card: which certificate (several on the smartcard), -1 / none = no question
    function rdp(c, password, card) {
        if (/[\n\r]/.test(password)) return fail(c, "the password contains a line break")
        // one argument per line in QS_RDP_ARGS; a notification if it can't connect
        // (exit ≥ 128 = connection / auth / DNS error, 6-10 = denied)
        detached(["bash", "-c",
                  'out=$(printf "%s\\n" "$QS_RDP_CARD" | xfreerdp3 /args-from:env:QS_RDP_ARGS 2>&1 | tail -n 30; exit "${PIPESTATUS[1]}"); code=$?\n'
                + 'if [ "$code" -ge 128 ] || { [ "$code" -ge 6 ] && [ "$code" -le 10 ]; }; then\n'
                + '  notify-send -a Connections -i network-error "$1: could not connect" "$(printf "%s\\n" "$out" | grep ERROR | tail -n 2 | sed "s/^.*\\] - //") (exit $code)"\n'
                + 'fi', "bash", c.name],
                 { QS_RDP_ARGS: rdpArgs(c, password).join("\n"), QS_RDP_CARD: card >= 0 ? String(card) : "" })
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
                    clipboard: false, dynres: false, shareHome: false, ignoreCert: false, smartcard: "off", extra: [] }
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
            else if (t === "/smartcard-logon") c.smartcard = "logon"
            else if (t === "/smartcard") { if (c.smartcard !== "logon") c.smartcard = "redirect" }
            else if (t === "/sec:nla" && c.smartcard === "logon") continue
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

    // add the chosen import candidates; passwords found in scripts (or in an
    // export file) go to the keyring. replace: a candidate that's already saved
    // (same name and type) takes that entry's place instead of being added next to it
    function importAll(cands, cb, replace) {
        const l = list.slice()
        let pending = 0, problems = []
        for (const r of cands) {
            if (Object.keys(validate(r.conn)).length > 0) continue
            const at = replace ? l.findIndex(c => c.name === r.conn.name && c.type === r.conn.type) : -1
            if (at >= 0) { r.conn.id = l[at].id; l[at] = normalize(r.conn) }
            else l.push(normalize(r.conn))
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

    // ── Export / import files ───────────────────────────────────────────────
    // { quickshellConnections: 1, exported, connections: [{ name, type, host, port,
    //   user, password, clipboard, dynres, shareHome, ignoreCert, extra, secret? }] }
    // `secret` (the keyring password, plain text) only with withPasswords. The
    // file is written through stdin with umask 077: passwords never show up in
    // a command line, and only you can read the file.
    readonly property var fileFields: ["name", "type", "host", "port", "user", "password", "clipboard", "dynres", "shareHome", "ignoreCert", "smartcard", "extra"]

    function exportTo(path, ids, withPasswords, cb) {
        const conns = list.filter(c => ids.includes(c.id))
        const out = conns.map(c => { const o = {}; for (const f of fileFields) o[f] = c[f]; return o })
        const write = () => Jobs.runInput(["sh", "-c", 'umask 077; cat > "$1"', "sh", path],
            JSON.stringify({ quickshellConnections: 1, exported: new Date().toISOString(), connections: out }, null, 2) + "\n",
            (code, o, err) => cb(code === 0, code === 0 ? "" : (err.trim() || "couldn't write " + path)))
        const secret = withPasswords ? conns.map((c, i) => [c, i]).filter(([c]) => c.password === "keyring") : []
        let pending = secret.length
        if (pending === 0) return write()
        for (const [c, i] of secret)
            Jobs.run(["secret-tool", "lookup", "service", secretService, "id", c.id], (code, pw) => {
                if (code === 0 && pw !== "") out[i].secret = pw.replace(/\n$/, "")
                if (--pending === 0) write()
            })
    }

    // an export file → { error, cands } (cands like scanImports: { source, password, conn, exists, errors })
    function parseFile(text, name) {
        let v
        try { v = JsonCheck.parse(text).value }
        catch (e) {
            if (e.line === undefined) throw e
            return { error: name + " isn't valid JSON (line " + e.line + ": " + e.message + ")", cands: [] }
        }
        if (!v || typeof v !== "object" || !Array.isArray(v.connections))
            return { error: name + " isn't a connections export (no \"connections\" list)", cands: [] }
        const cands = []
        for (const e of v.connections) {
            if (!e || typeof e !== "object") continue
            const c = { id: newId() }
            for (const f of fileFields) if (e[f] !== undefined) c[f] = e[f]
            const pw = typeof e.secret === "string" && c.password === "keyring" ? e.secret : ""
            cands.push({ source: name, password: pw, conn: c, noSecret: c.password === "keyring" && pw === "",
                         exists: list.some(x => x.name === String(c.name ?? "").trim() && x.type === c.type),
                         errors: validate(c) })
        }
        return { error: cands.length === 0 ? name + " has no connections in it" : "", cands: cands }
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
