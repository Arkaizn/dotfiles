.pragma library

// Pure helpers of the login screen (greeter/): sessions from
// /usr/share/wayland-sessions, users from /etc/passwd, what to launch.

// A .desktop file → { id, name, exec, desktopNames: [], tryExec } or null
// (hidden, no Exec, not an application).
function parseDesktop(id, text) {
    const o = {}
    let inEntry = false
    for (const raw of String(text ?? "").split("\n")) {
        const line = raw.trim()
        if (line.startsWith("[")) { inEntry = line === "[Desktop Entry]"; continue }
        if (!inEntry || line === "" || line.startsWith("#")) continue
        const eq = line.indexOf("=")
        if (eq < 1) continue
        const key = line.slice(0, eq).trim()
        if (!(key in o)) o[key] = line.slice(eq + 1).trim()     // first wins; Name[de] etc. are other keys
    }
    if (!o.Exec || (o.Type && o.Type !== "Application") || o.Hidden === "true" || o.NoDisplay === "true") return null
    return {
        id: id,
        name: o.Name || id,
        exec: o.Exec,
        desktopNames: (o.DesktopNames || "").split(/[;:]/).filter(s => s !== ""),
        tryExec: o.TryExec || ""
    }
}

// Exec line → argv (desktop-entry quoting; field codes like %U dropped)
function splitExec(exec) {
    const args = []
    let cur = "", quoted = false, has = false
    const s = String(exec ?? "")
    for (let i = 0; i < s.length; i++) {
        const c = s[i]
        if (quoted) {
            if (c === "\\" && i + 1 < s.length) { cur += s[++i]; continue }
            if (c === '"') { quoted = false; continue }
            cur += c
        } else if (c === '"') { quoted = true; has = true }
        else if (c === " " || c === "\t") { if (has || cur !== "") args.push(cur); cur = ""; has = false }
        else cur += c
    }
    if (has || cur !== "") args.push(cur)
    return args.filter(a => !/^%[a-zA-Z]$/.test(a)).map(a => a.replace(/%%/g, "%"))
}

// environment for greetd's start_session
function sessionEnv(session) {
    const names = session.desktopNames.length > 0 ? session.desktopNames : [session.name]
    return ["XDG_SESSION_TYPE=wayland",
            "XDG_CURRENT_DESKTOP=" + names.join(":"),
            "XDG_SESSION_DESKTOP=" + names[0].toLowerCase()]
}

// /etc/passwd → [{ name, uid, gecos }]: people (uid 1000–59999) with a login shell
function users(passwd) {
    const out = []
    for (const line of String(passwd ?? "").split("\n")) {
        const f = line.split(":")
        if (f.length < 7) continue
        const uid = Number(f[2])
        if (!(uid >= 1000 && uid < 60000)) continue
        if (/(nologin|false)$/.test(f[6]) || f[6] === "") continue
        out.push({ name: f[0], uid: uid, gecos: (f[4] || "").split(",")[0] })
    }
    return out
}

// first of `wanted` that is in `list` (by key), else the first of the list
function pick(list, key, wanted) {
    for (const w of wanted) {
        if (!w) continue
        const hit = list.find(x => x[key] === w)
        if (hit) return hit
    }
    return list[0] ?? null
}
