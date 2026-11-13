pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import qs.services.lib

// The Servers app (modules/servers): the homelab servers managed by
// manage-svs.sh (scripts/servers in this config). Everything here is local to this device
// and never goes into settings.json (the dotfiles repo is public):
//   <dataDir>/servers.json           servers, groups, waves, saved commands (the
//                                      script reads it too: lib/servers.sh)
//   <dataDir>/state/last-scan.json   latest scan / check of every server (written
//   <dataDir>/state/last-check.json  by the script, also by cron / terminal runs)
//   ~/.local/state/quickshell/servers-app.json   this app's own preferences (view,
//                                      collapsed groups, script folder, last used)
//
//   servers / groups / active / archived     from servers.json
//   info[name]   { online, reachable, lastScan, stale, pm, proxmox, reboot, packages,
//                  security, containers, critical, checks, checksFailed, containersBad }
//   put(server, oldName) · remove(name) · archive(name, on) · setGroups(name, ids)
//   addGroup(name, icon) · renameGroup · setGroupIcon · moveGroup · deleteGroup
//   ssh(name) · sftp(name) · copyKey(name) · openUrl(url) · probe()
//   connections  the servers as SSH entries for the launcher (RemoteConnections)
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/quickshell"

    // ── This app's preferences (local) ──────────────────────────────────────
    property var prefs: ({})
    // The program is part of this config (scripts/servers). Everything of yours — the
    // servers, their settings, logs and reports — is in the data folder, outside
    // ~/.config: the config is synced to a public repo, this never is.
    readonly property string dataDir: prefs.dataDir || (Quickshell.env("XDG_DATA_HOME") || home + "/.local/share") + "/quickshell/servers"
    readonly property string script: Quickshell.shellDir + "/scripts/servers/manage-svs.sh"
    // the program's command line, pointed at the data folder: engine(["scan", "--json"])
    function engine(args) { return ["env", "SVS_DATA=" + dataDir, script].concat(args ?? []) }
    // Proxmox snapshots before updates: "off" | "keep" (deleted after SNAPSHOT_KEEP_DAYS) |
    // "drop" (deleted again once the update passed); older prefs had true / false
    readonly property string snapshotMode: prefs.snapshots === false || prefs.snapshots === "off" ? "off"
                                         : prefs.snapshots === "drop" ? "drop" : "keep"
    // a snapshot that can't be taken: "skip" the server (svs.conf SNAPSHOT_REQUIRED) or "update" anyway
    readonly property string snapshotFail: prefs.snapshotFail === "update" ? "update" : "skip"
    function setPref(key, value) {
        const p = Object.assign({}, prefs)
        p[key] = value
        prefs = p
        prefsFile.setText(JSON.stringify(p, null, 2) + "\n")
    }

    // ── What an update does, per server (Update → Choose…) ──────────────────
    // a choice: "skip" | "security" | "os" (packages, no containers) | "containers" | "all";
    // "pending" = everything when the last scan found something, else skip
    readonly property var updateChoices: [
        { value: "skip", label: "Skip", icon: "󰜺" },
        { value: "security", label: "Security", icon: "󰒃" },
        { value: "os", label: "Packages", icon: "󰏗" },
        { value: "containers", label: "Containers", icon: "󰡨" },
        { value: "all", label: "Everything", icon: "󰚰" }
    ]
    function choiceLabel(c) { return c === "pending" ? "What's pending" : updateChoices.find(x => x.value === c)?.label ?? c }
    // the general default (Settings → Servers → Update defaults)
    readonly property string updateDefault: ["pending", "skip", "security", "os", "containers", "all"].includes(prefs.updateDefault) ? prefs.updateDefault : "pending"
    // the Update button: "menu" (quick choices) or "choose" (straight to the per-server dialog)
    readonly property string updateButton: prefs.updateButton === "choose" ? "choose" : "menu"
    function updatePerOf(name) { return (prefs.updatePer ?? {})[name] ?? "" }          // "" = the general default
    function setUpdatePer(name, choice) {
        const m = Object.assign({}, prefs.updatePer ?? {})
        if (!choice) delete m[name]; else m[name] = choice
        setPref("updatePer", m)
    }
    function pendingChoice(name) {
        const i = info[name]
        if (!i || i.reachable === false || !i.scanOk) return "skip"
        return (i.packages ?? 0) + (i.containers ?? 0) > 0 || i.reboot ? "all" : "skip"
    }
    // what the dialog preselects for a server
    function updateChoiceFor(name) {
        const c = updatePerOf(name) || updateDefault
        if (c === "pending") return pendingChoice(name)
        // a fixed choice still skips a server that can't be reached
        return info[name]?.reachable === false ? "skip" : c
    }

    // ── Selecting servers in the window (Select / Ctrl+A) ───────────────────
    property bool selecting: false
    property var selection: []
    onSelectingChanged: if (!selecting) selection = []
    function isSelected(name) { return selection.includes(name) }
    function toggleSelected(name) { selection = selection.includes(name) ? selection.filter(n => n !== name) : selection.concat([name]) }
    function selectOnly(names) { selection = names.slice() }

    // ── servers.json ────────────────────────────────────────────────────────
    property var data: ({ version: 1, groups: [], servers: [], waves: [], commands: [] })
    property bool exists: false
    property bool loaded: false
    property string error: ""

    readonly property var servers: (data.servers ?? []).map(normalize)
    readonly property var groups: data.groups ?? []
    readonly property var active: servers.filter(s => !s.archived)
    readonly property var archived: servers.filter(s => s.archived)
    readonly property var groupMap: { const m = {}; for (const g of groups) m[g.id] = g; return m }
    function get(name) { return servers.find(s => s.name === name) ?? null }

    readonly property var groupIcons: ["󰡨", "󰒋", "󰛳", "󰒍", "󰕧", "󰊴", "󰅟", "󰆼", "󰌘", "󰒃", "󰋜", "󰠖", "󰟀", "󰇄", "󰚩", "󰀄"]

    function normalize(s) {
        return {
            name: String(s.name ?? ""), host: String(s.host ?? ""), port: Number(s.port) || 22, user: String(s.user ?? ""),
            groups: Array.isArray(s.groups) ? s.groups.map(String) : [], tags: Array.isArray(s.tags) ? s.tags.map(String) : [],
            notes: String(s.notes ?? ""), archived: s.archived === true, sftp: s.sftp !== false, noReboot: s.noReboot === true,
            noSnapshot: s.noSnapshot === true,
            icon: String(s.icon ?? ""),
            guest: s.guest && s.guest.vmid !== undefined && s.guest.vmid !== null ? { node: String(s.guest.node ?? ""), type: s.guest.type === "lxc" ? "lxc" : "qemu", vmid: Number(s.guest.vmid) } : null,
            checks: Array.isArray(s.checks) ? s.checks.filter(c => c && c.type && c.name && c.target)
                        .map(c => ({ type: String(c.type), name: String(c.name), target: String(c.target), expect: String(c.expect ?? "") })) : [],
            excludeContainers: Array.isArray(s.excludeContainers) ? s.excludeContainers.map(String) : [],
            wol: String(s.wol ?? ""),
            links: Array.isArray(s.links) ? s.links.filter(l => l && l.url).map(l => ({ name: String(l.name ?? l.url), url: String(l.url) })) : [],
            tunnels: Array.isArray(s.tunnels) ? s.tunnels : []
        }
    }

    // ssh destination parts: host defaults to the name (an ~/.ssh/config alias or DNS name)
    function hostOf(s) { return s.host || s.name }
    function destOf(s) { return (s.user ? s.user + "@" : "") + hostOf(s) }

    function nameError(name, oldName) {
        if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$/.test(name)) return "letters, digits, . _ - (starts with a letter or digit)"
        if (name !== oldName && servers.some(s => s.name === name)) return "a server with this name exists"
        return ""
    }

    function save(d) {
        d.version = 1
        data = d
        serversFile.setText(JSON.stringify(d, null, 2) + "\n")
        exists = true
    }
    function copy() { return JSON.parse(JSON.stringify(data)) }

    // add or replace; oldName = the name it had (a rename also fixes waves and guest nodes)
    // returns "" or an error
    function put(s, oldName) {
        const e = nameError(s.name, oldName ?? "")
        if (e) return e
        const d = copy()
        d.servers = d.servers ?? []
        const n = normalize(s)
        const i = oldName ? d.servers.findIndex(x => x.name === oldName) : -1
        if (i >= 0) d.servers[i] = Object.assign({}, d.servers[i], n)
        else d.servers.push(n)
        if (oldName && oldName !== n.name) {
            d.waves = (d.waves ?? []).map(w => w.map(x => x === oldName ? n.name : x))
            for (const x of d.servers) if (x.guest && x.guest.node === oldName) x.guest.node = n.name
            const lu = Object.assign({}, prefs.lastUsed ?? {})
            if (lu[oldName]) { lu[n.name] = lu[oldName]; delete lu[oldName]; setPref("lastUsed", lu) }
            const up = updatePerOf(oldName)
            if (up) { setUpdatePer(oldName, ""); setUpdatePer(n.name, up) }
        }
        save(d)
        if (oldName && oldName !== n.name) tidyState(oldName, n.name)
        return ""
    }

    // the script's last-scan / last-check are keyed by name: a renamed server keeps its
    // entry under the new name, and entries of servers that are gone are dropped
    // (under the script's own lock, state/.lock)
    function tidyState(from, to) {
        const names = (data.servers ?? []).map(x => String(x.name))
        Jobs.run(["sh", "-c", 'd=$1; from=$2; to=$3; shift 3; [ -d "$d" ] || exit 0\n'
                + 'exec 8> "$d/.lock"; flock 8\n'
                + 'for f in "$d/last-scan.json" "$d/last-check.json"; do [ -s "$f" ] || continue\n'
                + '  jq --arg from "$from" --arg to "$to" --args \'\n'
                + '    (if $from != "" and .servers[$from] != null and .servers[$to] == null then .servers[$to] = (.servers[$from] | .server = $to) else . end)\n'
                + '    | .servers |= with_entries(select(.key | IN($ARGS.positional[])))\' "$@" < "$f" > "$f.tmp" && mv "$f.tmp" "$f"\n'
                + 'done', "sh", dataDir + "/state", from ?? "", to ?? ""].concat(names))
    }
    function remove(name) {
        const d = copy()
        d.servers = (d.servers ?? []).filter(x => x.name !== name)
        d.waves = (d.waves ?? []).map(w => w.filter(x => x !== name)).filter(w => w.length > 0)
        save(d)
        tidyState("", "")
        if (updatePerOf(name)) setUpdatePer(name, "")
    }
    function patch(name, fields) {
        const d = copy()
        const x = (d.servers ?? []).find(x => x.name === name)
        if (!x) return
        Object.assign(x, fields)
        save(d)
    }
    function archive(name, on) { patch(name, { archived: on }) }
    // the card shrinks away first (ServerCard `leaving`), then the list changes and it
    // glides in where it lands (the group's add transition)
    property var leaving: ({})
    function animateOut(name, fn) {
        const l = Object.assign({}, leaving); l[name] = true; leaving = l
        Jobs.later(Anim.medium + 40, () => {
            fn()
            const m = Object.assign({}, leaving); delete m[name]; leaving = m
        })
    }
    function archiveAnimated(name, on) { animateOut(name, () => archive(name, on)) }
    function removeAnimated(name) { animateOut(name, () => remove(name)) }
    // a card dropped on a group (drag): moves it from the group it came from
    //   to: group id | "__ungrouped" (leave `from`) | "__archived"
    function dropOn(name, from, to) {
        const s = get(name)
        if (!s || to === from) return
        if (to === "__archived") return archiveAnimated(name, true)
        const keep = s.groups.filter(g => g !== from)
        if (s.archived) patch(name, { archived: false, groups: to.startsWith("__") ? s.groups : keep.concat(keep.includes(to) ? [] : [to]) })
        else setGroups(name, to.startsWith("__") ? keep : keep.concat(keep.includes(to) ? [] : [to]))
    }
    function setGroups(name, ids) { patch(name, { groups: ids }) }
    function toggleGroup(name, id) {
        const s = get(name)
        if (s) setGroups(name, s.groups.includes(id) ? s.groups.filter(g => g !== id) : s.groups.concat([id]))
    }

    // ── Groups ──────────────────────────────────────────────────────────────
    function addGroup(name, icon) {
        name = String(name).trim()
        if (name === "") return ""
        let base = name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "group"
        let id = base, n = 2
        while (groups.some(g => g.id === id)) id = base + "-" + n++
        const d = copy()
        d.groups = (d.groups ?? []).concat([{ id: id, name: name, icon: icon || "󰒍" }])
        save(d)
        return id
    }
    function updateGroup(id, fields) {
        const d = copy()
        const g = (d.groups ?? []).find(g => g.id === id)
        if (!g) return
        Object.assign(g, fields)
        save(d)
    }
    function moveGroup(id, dir) {
        const d = copy()
        const i = d.groups.findIndex(g => g.id === id), j = i + dir
        if (i < 0 || j < 0 || j >= d.groups.length) return
        const t = d.groups[i]; d.groups[i] = d.groups[j]; d.groups[j] = t
        save(d)
    }
    // the servers stay, they just leave the group
    function deleteGroup(id) {
        const d = copy()
        d.groups = (d.groups ?? []).filter(g => g.id !== id)
        for (const x of d.servers ?? []) x.groups = (x.groups ?? []).filter(g => g !== id)
        save(d)
    }

    // ── Collapsed groups / view (local) ─────────────────────────────────────
    readonly property var collapsed: prefs.collapsed ?? ["__archived"]
    function isCollapsed(id) { return collapsed.includes(id) }
    function setCollapsed(id, on) {
        const c = collapsed.filter(x => x !== id)
        if (on) c.push(id)
        setPref("collapsed", c)
    }
    readonly property string view: prefs.view === "list" ? "list" : "cards"

    // ── Last scan / check (written by the script) ───────────────────────────
    property var scans: ({})
    property var checks: ({})
    readonly property real lastScan: Math.max(0, ...Object.values(scans).map(s => Date.parse(s.time) || 0))
    readonly property real lastCheck: Math.max(0, ...Object.values(checks).map(s => Date.parse(s.time) || 0))

    // ── Live reachability (while the window is open) ────────────────────────
    property var reach: ({})           // name → "up" | "down" | "checking"
    property bool probing: false
    function probe() {
        Jobs.which(["nc"], have => {
            if (!have.nc) return
            const list = active
            let left = list.length
            probing = left > 0
            for (const s of list) {
                const name = s.name
                const done = code => {
                    const r = Object.assign({}, reach); r[name] = code === 0 ? "up" : "down"; reach = r
                    if (--left === 0) probing = false
                }
                // ask ssh where the alias really goes (HostName / Port from ~/.ssh/config)
                Jobs.run(["ssh", "-G"].concat(s.port !== 22 ? ["-p", String(s.port)] : []).concat(["--", hostOf(s)]), (c, out) => {
                    const h = /^hostname (.+)$/m.exec(out), p = /^port (\d+)$/m.exec(out)
                    Jobs.run(["nc", "-z", "-w", "2", "--", h && !Valid.host(h[1]) ? h[1] : hostOf(s), p ? p[1] : String(s.port)], done)
                })
            }
        })
    }

    // what the cards show
    readonly property var info: {
        const m = {}
        for (const s of servers) {
            const sc = scans[s.name] ?? null, ck = checks[s.name] ?? null
            const pk = sc?.packages ?? [], cts = sc?.containers ?? []
            const r = reach[s.name]
            const reachable = r === "up" ? true : r === "down" ? false : (sc ? sc.reachable : ck ? ck.reachable : null)
            const security = pk.filter(p => p.security).length
            const failed = (ck?.checks ?? []).filter(c => !c.ok)
            const bad = (ck?.containers ?? []).filter(c => c.status === "restarting" || c.health === "unhealthy")
            m[s.name] = {
                reachable: reachable, live: r === "up" || r === "down", checking: r === "checking",
                scanned: !!sc, lastScan: sc ? Date.parse(sc.time) || 0 : 0, stale: sc?.stale === true,
                // the last scan got through (being online — port open — isn't enough: ssh can still fail)
                scanOk: sc?.reachable === true, scanError: sc && sc.reachable !== true ? (sc.error ?? "unreachable") : "",
                error: sc?.error ?? "", pm: sc?.pm ?? "", proxmox: sc?.proxmox === true, reboot: sc?.reboot === true,
                os: sc?.os?.id ?? "", osName: sc?.os?.name ?? "", docker: sc?.docker === true || (ck?.containers ?? []).length > 0,
                packages: pk.length, security: security, normal: pk.length - security, containers: cts.length,
                critical: security > 0 || sc?.reboot === true,
                checks: ck?.checks ?? [], checksFailed: failed.length, containersBad: bad.length,
                ctTotal: (ck?.containers ?? []).length, lastCheck: ck ? Date.parse(ck.time) || 0 : 0,
                warnings: (sc?.warnings ?? []).length
            }
        }
        return m
    }
    // ── Logos (modules/servers/icons: Simple Icons, CC0) ────────────────────
    readonly property string iconsDir: Quickshell.shellDir + "/modules/servers/icons"
    readonly property var logos: ["proxmox", "docker", "archlinux", "debian", "ubuntu", "alpinelinux", "fedora", "raspberrypi", "nixos",
        "almalinux", "rockylinux", "centos", "opensuse", "freebsd", "truenas", "unraid", "synology", "linux", "kubernetes", "portainer",
        "homeassistant", "pihole", "nginx", "traefikproxy", "wireguard", "tailscale", "jellyfin", "plex", "nextcloud", "gitlab", "gitea",
        "grafana", "vaultwarden", "opnsense", "pfsense", "mikrotik", "ubiquiti", "steam", "apple"]
    // /etc/os-release ID → logo
    readonly property var osLogos: ({ arch: "archlinux", archarm: "archlinux", endeavouros: "archlinux", manjaro: "archlinux", debian: "debian",
        ubuntu: "ubuntu", alpine: "alpinelinux", fedora: "fedora", raspbian: "raspberrypi", nixos: "nixos", almalinux: "almalinux",
        rocky: "rockylinux", centos: "centos", "opensuse-leap": "opensuse", "opensuse-tumbleweed": "opensuse", freebsd: "freebsd", truenas: "truenas" })
    function logoUrl(slug) { return slug ? "file://" + iconsDir + "/" + slug + ".svg" : "" }
    // the picture of a server: its own choice (a logo name, or "file:/path" to any image), else
    // what the scan saw: Proxmox, a Docker host, else the distro. `os`: the distro's, when
    // it isn't the main one already. "" = none (the card shows a plain server glyph)
    function logoOf(name) {
        const s = get(name), i = info[name] ?? {}
        const distro = osLogos[i.os] ?? (i.pm === "pacman" ? "archlinux" : "")
        let main = ""
        if (s?.icon) main = s.icon.startsWith("file:") || s.icon.startsWith("/") ? (s.icon.startsWith("/") ? "file://" + s.icon : s.icon) : logoUrl(logos.includes(s.icon) ? s.icon : "")
        else main = logoUrl(i.proxmox ? "proxmox" : i.docker ? "docker" : distro)
        const os = logoUrl(distro)
        return { main: main, os: os !== main ? os : "" }
    }
    function setIcon(name, icon) { patch(name, { icon: icon }) }

    // one colour per state, everywhere in the app:
    //   grey  offline / not reachable / not scanned yet / the last scan failed (e.g. ssh refused)
    //   red   critical (security updates, reboot needed) or failing health checks
    //   orange  normal updates waiting (packages, containers)
    //   green   nothing to do
    function statusColor(name) {
        const i = info[name]
        // grey: offline, or nothing known yet (never scanned: online alone isn't "up to date")
        if (!i || !i.scanOk || i.reachable === false || i.reachable === null || i.reachable === undefined) return Colors.fade(0.38)
        if (i.critical || i.checksFailed > 0 || i.containersBad > 0) return Colors.red
        if (i.packages + i.containers > 0) return Colors.orange
        return Colors.green
    }
    // worst first: offline, failing checks, critical, updates, fine
    function severity(name) {
        const i = info[name]
        if (!i) return 0
        if (i.reachable === false) return 4
        if (i.checksFailed > 0 || i.containersBad > 0) return 3
        if (i.critical) return 2
        if (i.packages + i.containers > 0) return 1
        return 0
    }

    // ── Actions ─────────────────────────────────────────────────────────────
    function touch(name) {
        const lu = Object.assign({}, prefs.lastUsed ?? {})
        lu[name] = Date.now()
        setPref("lastUsed", lu)
    }

    // SSH in the default terminal (Settings → Default apps → Terminal); the window
    // stays open when ssh fails, so you can read why
    function ssh(name) {
        const s = get(name)
        if (!s) return
        touch(name)
        DefaultApps.inTerminal(s.name, ["bash", "-c",
            'ssh "$@"; code=$?; if [ "$code" -ne 0 ]; then printf "\\nssh exited with %s. Press Enter to close." "$code"; read -r _; fi',
            "bash"].concat(s.port !== 22 ? ["-p", String(s.port)] : []).concat(["--", destOf(s)]))
    }

    function sftpUri(s) { return "sftp://" + (s.user ? s.user + "@" : "") + hostOf(s) + (s.port !== 22 ? ":" + s.port : "") + "/" }

    // SFTP in the default file manager (inode/directory): the shell's own Files app
    // directly, anything else gets the address (gvfs file managers open it)
    function sftp(name) {
        const s = get(name)
        if (!s || !s.sftp) return
        const uri = sftpUri(s)
        touch(name)
        Jobs.run(["xdg-mime", "query", "default", "inode/directory"], (code, out) => {
            const app = out.trim()
            if (app === "" || app === "quickshell-files.desktop") {
                const sh = Quickshell.shellDir + "/scripts/files/files.sh"
                Jobs.run([sh, "--start"], () =>
                    Jobs.run(["qs", "ipc", "-p", Quickshell.shellDir + "/files.qml", "call", "files", "connect", uri], (c2, o2) => {
                        const r = o2.trim().split("\n").pop()
                        if (c2 !== 0 || r !== "ok") notify(s.name + ": couldn't open SFTP", r || "the file manager didn't answer")
                    }, { LC_ALL: "C.UTF-8" }))
            } else {
                Jobs.which(["gtk-launch"], have => {
                    if (have["gtk-launch"]) Jobs.detached(["gtk-launch", app.replace(/\.desktop$/, ""), uri], null)
                    else Jobs.detached(["xdg-open", uri], null)
                })
            }
        })
    }

    // ssh-copy-id in a terminal (asks for the server's password once)
    function copyKey(name) {
        const s = get(name)
        if (!s) return
        DefaultApps.inTerminal("SSH key → " + s.name, ["bash", "-c",
            'ls ~/.ssh/id_*.pub >/dev/null 2>&1 || ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519\n'
            + 'ssh-copy-id -p "$1" -- "$2"; printf "\\nPress Enter to close."; read -r _', "bash", String(s.port), destOf(s)])
    }

    function openUrl(url) { if (/^https?:\/\//.test(url)) Qt.openUrlExternally(url) }
    // http checks double as web links
    function webLinks(s) {
        return s.links.concat(s.checks.filter(c => c.type === "http" && !s.links.some(l => l.url === c.target))
                                     .map(c => ({ name: c.name, url: c.target })))
    }

    function notify(title, body) { Jobs.run(["notify-send", "-a", "Servers", "-i", "network-server", title, body]) }

    // ── Launcher (Connections tab): the servers as SSH entries ─────────────
    // never saved into settings.json; renamed / archived / deleted servers follow by themselves
    readonly property var connections: active.map(s => ({
        id: "srv:" + s.name, name: s.name, type: "ssh", host: hostOf(s), port: s.port, user: s.user,
        password: "none", extra: [], lastUsed: (prefs.lastUsed ?? {})[s.name] ?? 0,
        managed: "servers", tags: s.groups.map(g => groupMap[g]?.name ?? g)
    }))

    // ── Saved commands (servers.json "commands") ────────────────────────────
    readonly property var commands: (data.commands ?? []).filter(c => c && c.id && c.script)
    // add or replace by id; returns the id
    function saveCommand(c) {
        const d = copy()
        d.commands = d.commands ?? []
        const id = c.id || "cmd-" + Date.now().toString(36)
        const n = { id: id, name: String(c.name || "Command").trim(), script: String(c.script) }
        const i = d.commands.findIndex(x => x.id === id)
        if (i >= 0) d.commands[i] = n; else d.commands.push(n)
        save(d)
        return id
    }
    function deleteCommand(id) {
        const d = copy()
        d.commands = (d.commands ?? []).filter(c => c.id !== id)
        save(d)
    }

    // ── Reboot (by hand: the script never reboots Proxmox hosts or "never reboot" servers) ──
    // through the command runner, so it shows in the activity panel; the reboot starts 2 s
    // later, detached, so the ssh session still ends cleanly
    readonly property string rebootScript:
        'S=""; [ "$(id -u)" -ne 0 ] && S="sudo -n"\n'
        + 'if [ -n "$S" ] && ! sudo -n true 2>/dev/null; then echo "sudo needs a password here: reboot it in a terminal"; exit 1; fi\n'
        + 'nohup sh -c "sleep 2; $S systemctl reboot" >/dev/null 2>&1 &\n'
        + 'echo "rebooting in 2 seconds"'
    function reboot(name) { ServerRuns.start("command", [name], { title: "Reboot", script: rebootScript, then: [] }) }

    // ── Ping / Wake-on-LAN ──────────────────────────────────────────────────
    // cb(avg ms or -1, text): 3 pings to the real host (HostName from ~/.ssh/config)
    function ping(name, cb) {
        const s = get(name)
        if (!s) return
        Jobs.run(["ssh", "-G", "--", hostOf(s)], (c0, cfg) => {
            const h = /^hostname (.+)$/m.exec(cfg)
            const host = h && !Valid.host(h[1]) ? h[1] : hostOf(s)
            Jobs.run(["ping", "-c", "3", "-W", "2", "-q", "--", host], (code, out) => {
                const m = /= [\d.]+\/([\d.]+)\/[\d.]+\/[\d.]+ ms/.exec(out)
                const loss = /(\d+)% packet loss/.exec(out)
                cb(m ? Number(m[1]) : -1, m ? Math.round(Number(m[1]) * 10) / 10 + " ms" + (loss && loss[1] !== "0" ? " · " + loss[1] + "% lost" : "")
                                            : "no answer" + (code === 2 ? " (unknown host)" : ""))
            })
        })
    }
    // the magic packet (UDP broadcast, port 9), sent with python3
    function wake(name, cb) {
        const s = get(name)
        if (!s || !/^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$/.test(s.wol)) return cb && cb(false, "no MAC address set")
        Jobs.run(["python3", "-c",
                  "import socket,sys\nm=bytes.fromhex(sys.argv[1].replace(':','').replace('-',''))\n"
                  + "s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)\ns.setsockopt(socket.SOL_SOCKET,socket.SO_BROADCAST,1)\n"
                  + "s.sendto(b'\\xff'*6+m*16,('255.255.255.255',9))", s.wol], code => {
            if (cb) cb(code === 0, code === 0 ? "Wake-on-LAN sent to " + s.wol : "couldn't send it")
        })
    }

    // ── Reports / snapshots (from manage-svs.sh) ────────────────────────────
    // cb({ time, mode, result, server: { status, packages, containers, problems, notes, reboot, snapshot }, file } | null)
    // the newest update / scan report that has this server
    function lastReport(name, cb) {
        Jobs.run(["sh", "-c", 'for f in $(ls -1t "$1"/reports/*.json 2>/dev/null | head -n 60); do\n'
                    + '  jq -ce --arg s "$2" --arg f "$f" \'select(.mode == "update") | {time, mode, result, file: $f, server: (.servers[] | select(.server == $s))}\' "$f" 2>/dev/null && exit 0\n'
                    + 'done; exit 1', "sh", dataDir, name], (code, out) => {
            try { cb(code === 0 ? JSON.parse(out.trim().split("\n")[0]) : null) } catch (e) { cb(null) }
        })
    }
    // cb({ snapshots: [{ id, node, tool, vmid, name, snapshot, ageDays }], pools, unreachable, error })
    property bool snapshotsLoading: false
    function loadSnapshots(cb) {
        snapshotsLoading = true
        Jobs.run(engine(["snapshots", "--json"]), (code, out) => {
            snapshotsLoading = false
            let r = null, err = ""
            for (const l of out.split("\n")) {
                try { const e = JSON.parse(l); if (e.event === "snapshots") r = e; else if (e.event === "error") err = e.error } catch (x) {}
            }
            cb(r ? Object.assign({ error: "" }, r) : { snapshots: [], pools: [], unreachable: [], error: err || "couldn't list the snapshots" })
        })
    }
    // Proxmox: the guests on a host / the host of a guest
    function guestsOf(name) { return servers.filter(s => s.guest && s.guest.node === name) }
    // the Proxmox hosts: scanned as Proxmox, or holding a guest already
    readonly property var proxmoxHosts: servers.filter(s => !s.archived && (info[s.name]?.proxmox === true || servers.some(x => x.guest?.node === s.name)))
                                               .map(s => s.name)
    function setGuest(name, guest) { patch(name, { guest: guest }) }
    function setNoSnapshot(name, on) { patch(name, { noSnapshot: on }) }

    // where does it run? asks every Proxmox host (qm list / pct list over ssh) for a guest
    // whose name is the server's name (or its host / first label of it)
    // cb({ guest: { node, type, vmid } | null, error, all: [{ node, type, vmid, name }], unreachable: [] })
    property bool finding: false
    function listGuests(cb) {
        const hosts = proxmoxHosts
        if (hosts.length === 0) return cb({ all: [], unreachable: [], error: "no Proxmox host known yet: scan one first, or set a guest by hand" })
        finding = true
        let left = hosts.length
        const all = [], down = []
        for (const h of hosts) {
            const s = get(h)
            Jobs.run(["ssh", "-n", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8"].concat(s.port !== 22 ? ["-p", String(s.port)] : []).concat(["--", destOf(s),
                      'qm list 2>/dev/null | awk \'NR>1 {print "qemu", $1, $2}\'; pct list 2>/dev/null | awk \'NR>1 {print "lxc", $1, $NF}\'']), (code, out) => {
                if (code !== 0) down.push(h)
                for (const l of out.split("\n")) {
                    const m = /^(qemu|lxc) (\d+) (\S+)$/.exec(l.trim())
                    if (m) all.push({ node: h, type: m[1], vmid: Number(m[2]), name: m[3] })
                }
                if (--left === 0) { finding = false; cb({ all: all, unreachable: down, error: "" }) }
            })
        }
    }
    function findGuest(name, cb) {
        const s = get(name)
        listGuests(r => {
            if (r.error) return cb({ guest: null, error: r.error, all: [], unreachable: [] })
            const keys = [name, hostOf(s), hostOf(s).split(".")[0]].map(k => k.toLowerCase())
            const hit = r.all.find(g => keys.includes(g.name.toLowerCase()))
            cb({ guest: hit ? { node: hit.node, type: hit.type, vmid: hit.vmid } : null, all: r.all, unreachable: r.unreachable,
                 error: hit ? "" : "no VM / container named " + name + " on " + proxmoxHosts.join(", ") + (r.unreachable.length ? " (unreachable: " + r.unreachable.join(", ") + ")" : "") })
        })
    }

    // ── Export / import ─────────────────────────────────────────────────────
    // everything about the servers (servers.json holds no secrets)
    function exportDoc() {
        const d = copy()
        return { format: "quickshell-servers", version: 1, exported: new Date().toISOString(),
                 groups: d.groups ?? [], servers: d.servers ?? [], waves: d.waves ?? [], commands: d.commands ?? [] }
    }
    // a file / svs.conf / ~/.ssh/config → candidates: { doc, list: [{ server, exists }], error }
    function candidates(doc) {
        if (!doc || !Array.isArray(doc.servers)) return { doc: null, list: [], error: "no servers in it" }
        const list = doc.servers.filter(x => x && typeof x.name === "string" && /^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$/.test(x.name))
                                .map(x => ({ server: normalize(x), exists: servers.some(s => s.name === x.name) }))
        return { doc: doc, list: list, error: list.length ? "" : "no usable servers in it" }
    }
    function readImportFile(path, cb) {
        Jobs.run(["cat", "--", path], (code, out) => {
            if (code !== 0) return cb({ doc: null, list: [], error: "can't read " + path })
            try { cb(candidates(JSON.parse(out))) } catch (e) { cb({ doc: null, list: [], error: "not a JSON file: " + e.message }) }
        })
    }
    function readConf(path, cb) {
        Jobs.run(engine(["conf-json"]), (code, out) => {
            try { cb(candidates(JSON.parse(out))) } catch (e) { cb({ doc: null, list: [], error: "couldn't read " + path }) }
        }, { SVS_CONFIG: path })
    }
    function readSshConfig(cb) {
        const hosts = RemoteConnections.parseSshConfig(Files.read(home + "/.ssh/config"))
        cb(candidates({ servers: hosts.map(h => ({ name: h.conn.name.replace(/[^A-Za-z0-9._-]/g, "-"), host: h.conn.host === h.conn.name ? "" : h.conn.host,
                                                   port: h.conn.port, groups: [], checks: [] })) }))
    }
    // names: the chosen ones; replace: the whole list becomes the file's ("replace"), else
    // they're added, and with overwrite those that exist are replaced by the imported ones
    // groups / commands / waves of the file come along (merged by id)
    function importDoc(doc, names, how) {
        const d = how === "replace" ? { version: 1, groups: [], servers: [], waves: [], commands: [] } : copy()
        d.groups = d.groups ?? []; d.servers = d.servers ?? []; d.waves = d.waves ?? []; d.commands = d.commands ?? []
        const chosen = (doc.servers ?? []).filter(x => names.includes(x.name))
        let added = 0, replaced = 0
        for (const x of chosen) {
            const n = normalize(x)
            const i = d.servers.findIndex(s => s.name === n.name)
            if (i >= 0) { if (how === "skip") continue; d.servers[i] = n; replaced++ }
            else { d.servers.push(n); added++ }
        }
        // groups the imported servers use
        const used = new Set()                                    // no Array.flatMap in Qt's JS engine
        for (const x of chosen) for (const g of x.groups ?? []) used.add(g)
        for (const g of doc.groups ?? []) if (used.has(g.id) && !d.groups.some(x => x.id === g.id)) d.groups.push(g)
        for (const c of doc.commands ?? []) if (c && c.id && !d.commands.some(x => x.id === c.id)) d.commands.push(c)
        if (how === "replace") d.waves = (doc.waves ?? []).map(w => w.filter(n => names.includes(n))).filter(w => w.length)
        save(d)
        return { added: added, replaced: replaced }
    }

    // ── Files ───────────────────────────────────────────────────────────────
    function parseServers(text) {
        try {
            const d = JSON.parse(text)
            if (!d || !Array.isArray(d.servers)) throw new Error("no \"servers\" list")
            data = d
            error = ""
            exists = true
        } catch (e) { error = "servers.json: " + e.message }
        loaded = true
    }
    function parseState(text) {
        try { return JSON.parse(text).servers ?? {} } catch (e) { return {} }
    }

    FileView {
        id: serversFile
        path: root.dataDir + "/servers.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.parseServers(text())
        onLoadFailed: { root.exists = false; root.loaded = true }
    }
    // A file that didn't exist when the shell started isn't watched (the first scan
    // ever creates these two): ServerRuns asks for a re-read when a run ends.
    function reloadState() { scanFile.reload(); checkFile.reload() }
    FileView {
        id: scanFile
        path: root.dataDir + "/state/last-scan.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.scans = root.parseState(text())
    }
    FileView {
        id: checkFile
        path: root.dataDir + "/state/last-check.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.checks = root.parseState(text())
    }
    FileView {
        id: prefsFile
        path: root.stateDir + "/servers-app.json"
        blockLoading: true
        printErrors: false
        onLoaded: { try { root.prefs = JSON.parse(text()) || {} } catch (e) { root.prefs = {} } }
    }
    // servers.json can't be written into a folder that isn't there (a fresh device, before any scan)
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.stateDir, root.dataDir])
    onDataDirChanged: Quickshell.execDetached(["mkdir", "-p", root.dataDir])
    // once the list is read: drop state entries of servers that don't exist any more
    property bool _tidied: false
    onLoadedChanged: if (loaded && exists && !_tidied && servers.length > 0) { _tidied = true; Jobs.later(4000, () => tidyState("", "")) }
}
