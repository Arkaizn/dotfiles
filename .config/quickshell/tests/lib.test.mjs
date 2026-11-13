// Unit tests for services/lib/*.js (plain `.pragma library` files).
// Run: node tests/lib.test.mjs
import { readFileSync, readdirSync, statSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import vm from "node:vm"
import assert from "node:assert/strict"

const lib = join(dirname(fileURLToPath(import.meta.url)), "..", "services", "lib")
function load(name) {
    const ctx = vm.createContext({})
    vm.runInContext(readFileSync(join(lib, name), "utf8").replace(/^\.pragma library/m, ""), ctx)
    return ctx
}

let failed = 0, passed = 0
function test(name, fn) {
    try { fn(); passed++ } catch (e) { failed++; console.log("FAIL " + name + "\n  " + e.message) }
}

const Valid = load("Valid.js")
test("host accepts names and addresses", () => {
    for (const h of ["example.com", "router", "192.168.0.1", "::1", "fe80::1", "a-b.c"]) assert.equal(Valid.host(h), "", h)
})
test("host refuses options and junk", () => {
    assert.notEqual(Valid.host("-oProxyCommand=x"), "")
    assert.notEqual(Valid.host(""), "")
    assert.notEqual(Valid.host("256.1.1.1"), "")
    assert.notEqual(Valid.host("a b"), "")
})
test("port range", () => {
    assert.equal(Valid.port("22"), "")
    assert.notEqual(Valid.port("0"), "")
    assert.notEqual(Valid.port("65536"), "")
    assert.notEqual(Valid.port("2x"), "")
})
test("name (themes, profiles)", () => {
    assert.equal(Valid.name("Work 2_a-b"), "")
    assert.equal(Valid.name("  Gaming "), "")
    assert.equal(Valid.name(""), "enter a name")
    assert.notEqual(Valid.name("../x"), "")
    assert.notEqual(Valid.name("x".repeat(41)), "")
})

const JsonCheck = load("JsonCheck.js")
test("JsonCheck.parse matches JSON.parse", () => {
    const t = '{ "a": [1, 2.5, -3e2, true, null], "b": { "c": "x\\n\\u00e9" } }'
    assert.deepEqual(JSON.parse(JSON.stringify(JsonCheck.parse(t).value)), JSON.parse(t))
})
test("JsonCheck.parse reports the line of an error", () => {
    let err = null
    try { JsonCheck.parse('{\n  "a": 1,\n  "b": }') } catch (e) { err = e }
    assert.ok(err, "should throw")
    assert.equal(err.line, 3)
})

const Format = load("Format.js")
test("bytes (decimal)", () => {
    assert.equal(Format.bytes(0), "0 B")
    assert.equal(Format.bytes(999), "999 B")
    assert.equal(Format.bytes(1500), "1.5 KB")
    assert.equal(Format.bytes(250e9), "250 GB")
})
test("ibytes (binary)", () => {
    assert.equal(Format.ibytes(1024), "1.0 KiB")
    assert.equal(Format.ibytes(1536 * 1024 * 1024), "1.5 GiB")
    assert.equal(Format.ibytes(200 * 1024), "200 KiB")
})
const Devices = load("Devices.js")
test("Devices.pick skips unmanaged virtual adapters, prefers connected", () => {
    const vmnet = { name: "vmnet1", type: 1, connected: false, nmManaged: false }
    const dockEth = { name: "enp0s20f0u2", type: 1, connected: true, nmManaged: true }
    const builtin = { name: "enp2s0", type: 1, connected: false, nmManaged: true }
    const wifi = { name: "wlan0", type: 2, connected: true, nmManaged: true }
    assert.equal(Devices.pick([vmnet, wifi, dockEth], 1), dockEth)       // dock added last, still found
    assert.equal(Devices.pick([vmnet, builtin, wifi], 1), builtin)       // nothing plugged in: the real port
    assert.equal(Devices.pick([vmnet, wifi], 1), null)                   // only a virtual adapter: none
    assert.equal(Devices.pick([vmnet, builtin, dockEth], 1), dockEth)
    assert.equal(Devices.pick([wifi], 2), wifi)
    assert.equal(Devices.pick(undefined, 1), null)
})
test("Devices.wifiAction (Wi-Fi off while wired)", () => {
    const a = (e, w, on, t) => JSON.stringify(Devices.wifiAction(e, w, on, t))
    assert.equal(a(true, true, true, false), JSON.stringify({ wifi: false, turnedOff: true }))     // cable in: off
    assert.equal(a(true, false, false, true), JSON.stringify({ wifi: true, turnedOff: false }))    // cable out: back on
    assert.equal(a(true, false, false, false), JSON.stringify({ wifi: null, turnedOff: false }))  // you turned it off: stays off
    assert.equal(a(true, true, false, false), JSON.stringify({ wifi: null, turnedOff: false }))   // already off by you while wired
    assert.equal(a(true, true, false, true), JSON.stringify({ wifi: null, turnedOff: true }))     // still wired: keep
    assert.equal(a(false, true, false, true), JSON.stringify({ wifi: true, turnedOff: false }))   // option switched off: restore
    assert.equal(a(false, true, true, false), JSON.stringify({ wifi: null, turnedOff: false }))   // option off: nothing
})
const Vpn = load("VpnParse.js")
test("Vpn.tailscale", () => {
    const run = JSON.stringify({ BackendState: "Running", CurrentTailnet: { Name: "example.org" }, Self: { TailscaleIPs: ["100.1.2.3", "fd7a::1"] },
                                 Peer: { a: { Online: true }, b: { Online: false }, c: { Online: true } } })
    const r = Vpn.tailscale(0, run)
    assert.equal(r.on, true); assert.equal(r.tailnet, "example.org"); assert.equal(r.ip, "100.1.2.3"); assert.equal(r.peers, "2 / 3 online")
    assert.equal(Vpn.tailscale(0, JSON.stringify({ BackendState: "Stopped" })).on, false)
    const dead = Vpn.tailscale(1, "failed to connect to local tailscaled; it doesn't appear to be running\n")
    assert.equal(dead.on, false); assert.equal(dead.state, "not running"); assert.match(dead.error, /tailscaled/)
})
test("Vpn.netbird", () => {
    const r = Vpn.netbird(0, JSON.stringify({ daemonStatus: "Connected", netbirdIp: "100.90.1.2/16", peers: { total: 4, connected: 3 }, management: { connected: true } }))
    assert.equal(r.on, true); assert.equal(r.ip, "100.90.1.2"); assert.equal(r.peers, "3 / 4 connected"); assert.equal(r.error, ""); assert.equal(r.needsLogin, false)
    const exp = Vpn.netbird(0, JSON.stringify({ daemonStatus: "NeedsLogin", peers: { total: 0 }, management: { connected: false, error: "rpc error: code = PermissionDenied desc = peer login has expired, please log in once more" } }))
    assert.equal(exp.on, false); assert.equal(exp.needsLogin, true); assert.equal(exp.error, "peer login has expired, please log in once more")
})
test("Vpn.nmVpns", () => {
    const out = "Home Wi-Fi:abc:802-11-wireless:yes\nwork\\: vpn:u1:vpn:no\nwg0:u2:wireguard:yes\ndocker0:u3:bridge:yes\n"
    assert.deepEqual(JSON.parse(JSON.stringify(Vpn.nmVpns(out))), [{ name: "work: vpn", uuid: "u1", type: "vpn", active: false }, { name: "wg0", uuid: "u2", type: "wireguard", active: true }])
    assert.equal(Vpn.nmVpns("").length, 0)
})
test("day / hm (local time)", () => {
    const t = new Date(2026, 9, 3, 7, 5).getTime()
    assert.equal(Format.day(t), "2026-10-03")
    assert.equal(Format.day(new Date(2026, 0, 31, 23, 59)), "2026-01-31")
    assert.equal(Format.hm(t), "07:05")
    assert.equal(Format.hm(new Date(2026, 9, 3, 23, 59)), "23:59")
})
test("freeH (like free -h)", () => {
    assert.equal(Format.freeH(3716060), "3.5Gi")
    assert.equal(Format.freeH(14148480), "13Gi")
    assert.equal(Format.freeH(10432420), "9.9Gi")
    assert.equal(Format.freeH(193536), "189Mi")
    assert.equal(Format.freeH(10480000), "10Gi")       // 9.99 GiB: no "10.0Gi"
    assert.equal(Format.freeH(512), "512Ki")
})

const NetCheck = load("NetCheck.js")
const sample = [
    '@@URI s "http://check.example/nm.txt"',
    "@@GW 192.0.2.1",
    "--- 192.0.2.1 ping statistics ---",
    "3 packets transmitted, 3 received, 0% packet loss, time 604ms",
    "rtt min/avg/max/mdev = 1.912/2.345/2.801/0.363 ms",
    "@@NET 198.51.100.7",
    "3 packets transmitted, 2 received, 33.3333% packet loss, time 610ms",
    "rtt min/avg/max/mdev = 20.1/24.65/29.2/4.5 ms",
    "@@DNS",
    "ok 17",
].join("\n")
test("NetCheck.parse", () => {
    const r = NetCheck.parse(sample)
    assert.equal(r.uri, "http://check.example/nm.txt")
    assert.equal(r.gateway, "192.0.2.1")
    assert.deepEqual({ ...r.gwPing }, { sent: 3, received: 3, loss: 0, avg: 2.345 })
    assert.equal(r.netPing.received, 2)
    assert.equal(r.dns, 17)
    assert.equal(NetCheck.pingText(r.gwPing), "2.3 ms")
    assert.equal(NetCheck.pingText(r.netPing), "25 ms, 33% lost")
})
test("NetCheck.parse: no gateway, no answers, DNS failed", () => {
    const r = NetCheck.parse("@@URI\n@@GW\n@@NET 198.51.100.7\n3 packets transmitted, 0 received, 100% packet loss, time 2050ms\n@@DNS\nfail")
    assert.equal(r.uri, "")
    assert.equal(r.gateway, "")
    assert.equal(r.gwPing, null)
    assert.equal(NetCheck.pingText(r.gwPing), "not checked")
    assert.equal(NetCheck.pingText(r.netPing), "no answer")
    assert.equal(r.dns, -1)
    assert.equal(NetCheck.parse("").dns, null)
})

const DW = load("DeskWidgets.js")
test("DeskWidgets snapping", () => {
    assert.equal(DW.snap(23), 16)
    assert.equal(DW.snap(25), 32)
    assert.equal(DW.snapAngle(7, true), 0)
    assert.equal(DW.snapAngle(8, true), 15)
    assert.equal(DW.snapAngle(93, false), 90)
    assert.equal(DW.snapAngle(97, false), 97)
    assert.equal(DW.snapAngle(-2, false), 0)
    assert.equal(DW.snapAngle(190, false), -170)
    assert.equal(DW.snapAngle(-180, false), 180)
    assert.equal(DW.snapScale(5, false), 3)
    assert.equal(DW.snapScale(1.234, true), 1.2)
    assert.equal(DW.snapScale(1.234, false), 1.23)
    assert.equal(Math.round(DW.angleOf(0, 0, 10, 0)), 90)
    assert.equal(Math.round(DW.angleOf(0, 0, 0, -10)), 0)
    assert.equal(Math.round(DW.angleOf(0, 0, -10, 0)), -90)
})
test("DeskWidgets edge snapping", () => {
    const other = [{ x: 500, y: 300, w: 200, h: 100 }]      // left 400, right 600, top 250, bottom 350
    // 105 px wide box whose left edge is 5 px right of the other's right edge → touches it
    let r = DW.snapBox(605 + 52.5, 700, 105, 40, other, 1920, 1080)
    assert.equal(r.x - 52.5, 600)
    assert.equal(JSON.stringify(r.guides.map(g => g.axis + g.pos)), JSON.stringify(["x600"]))
    // top edge 3 px below the other's top → aligned tops
    r = DW.snapBox(1000, 253 + 20, 80, 40, other, 1920, 1080)
    assert.equal(r.y - 20, 250)
    // centres line up
    r = DW.snapBox(506, 900, 50, 50, other, 1920, 1080)
    assert.equal(r.x, 500)
    // screen edge
    r = DW.snapBox(1920 - 30 - 4, 600, 60, 60, [], 1920, 1080)
    assert.equal(r.x + 30, 1920)
    // nothing near: the left / top edge goes on the 16 px grid, no guide
    r = DW.snapBox(1000.5 + 25, 640.5 + 25, 50, 50, other, 1920, 1080)
    assert.equal(r.x - 25, 1008)       // 1000.5 / 16 = 62.53 → 63 × 16
    assert.equal(r.y - 25, 640)
    assert.equal(r.guides.length, 0)
})
test("DeskWidgets geometry", () => {
    assert.deepEqual({ ...DW.bounds(100, 50, 0) }, { w: 100, h: 50 })
    assert.deepEqual({ ...DW.bounds(100, 50, 90) }, { w: 50, h: 100 })
    assert.deepEqual({ ...DW.bounds(100, 100, 45) }, { w: 142, h: 142 })
    assert.equal(DW.toRel(960, 1920), 0.5)
    assert.equal(DW.toRel(-5, 1920), 0)
    assert.equal(DW.toRel(5000, 1920), 1)
    assert.equal(DW.newId("clock", ["clock-1", "clock-2"]), "clock-3")
})
test("DeskWidgets.showsOn", () => {
    const outs = [{ name: "eDP-1", ident: "BOE 0x0BCA Unknown" }, { name: "DP-3", ident: "Dell U2720Q ABC" }]
    assert.equal(DW.showsOn([], "DP-3", outs), true)
    assert.equal(DW.showsOn(null, "DP-3", outs), true)
    assert.equal(DW.showsOn(["Dell U2720Q ABC"], "DP-3", outs), true)
    assert.equal(DW.showsOn(["Dell U2720Q ABC"], "eDP-1", outs), false)
    assert.equal(DW.showsOn(["eDP-1"], "eDP-1", outs), true)
    assert.equal(DW.showsOn(["Gone Monitor X"], "eDP-1", outs), false)
})
test("DeskWidgets.validate", () => {
    const types = { clock: [{ key: "seconds", kind: "bool" }, { key: "size", kind: "number", min: 24, max: 300 },
                            { key: "style", kind: "choice", choices: [{ value: "digital" }, { value: "analog" }] }],
                    note: [{ key: "text", kind: "text" }], apps: [{ key: "apps", kind: "list" }] }
    const run = v => { const e = []; DW.validate(v, types, (path, m) => e.push(path.join(".") + ": " + m)); return e }
    assert.deepEqual(run({}), [])
    assert.deepEqual(run({ enabled: true, monitors: [], instances: [
        { id: "clock-1", type: "clock", x: 0.5, y: 0.2, rot: -10, scale: 1.5, monitors: null, opts: { seconds: true, size: 96, style: "analog" } },
        { id: "note-1", type: "note", x: 0, y: 1, opts: { text: "hi" } },
        { id: "apps-1", type: "apps", x: 0.1, y: 0.1, monitors: ["DP-3"], opts: { apps: ["firefox"] } }] }), [])
    const e = run({ enabled: "yes", monitors: [""], extra: 1, instances: [
        { id: "a", type: "clock", x: 2, rot: 400, scale: 9, monitors: "DP-3", opts: { seconds: 1, size: 5, style: "x", bogus: 1 }, z: 1 },
        { id: "a", type: "nope" }, 5] })
    for (const want of ["enabled:", "monitors:", "extra:", "instances.0.x:", "instances.0.rot:", "instances.0.scale:",
                        "instances.0.monitors:", "instances.0.opts.seconds:", "instances.0.opts.size:", "instances.0.opts.style:",
                        "instances.0.opts.bogus:", "instances.0.z:", "instances.1.id:", "instances.1.type:", "instances.2:"])
        assert.ok(e.some(m => m.startsWith(want)), "missing " + want + " in " + JSON.stringify(e))
    assert.equal(e.length, 15)
})

const LockItems = load("LockItems.js")
test("LockItems.resolve / check", () => {
    const d = LockItems.resolve({})
    assert.equal(d.notifications, "full")
    assert.equal(d.power, true)
    assert.equal(Object.keys(d).length, LockItems.items.length)
    const r = LockItems.resolve({ notifications: "private", power: false, blur: "no", media: null })
    assert.equal(r.notifications, "private")
    assert.equal(r.power, false)
    assert.equal(r.blur, true)
    assert.equal(r.media, true)
    assert.equal(LockItems.resolve({ notifications: "loud" }).notifications, "full")
    assert.equal(LockItems.check("power", false), "")
    assert.ok(LockItems.check("power", "no").includes("true or false"))
    assert.ok(LockItems.check("notifications", "loud").includes("full"))
    assert.equal(LockItems.check("monitors", []), null)
})

const MS = load("MediaSources.js")
const sess = (o) => Object.assign({ id: "x", origin: "remote", kind: "remote_controllable", controllable: true,
    capabilities: ["play", "pause", "seek"], player: { name: "Phone (Finamp)", device: "Phone", client: "Finamp" },
    track: { title: "T", artists: ["A", "B"], duration_ms: 100000 },
    playback: { state: "playing", position_ms: 10000, position_at: "2026-10-21T15:00:00.123456789+02:00", rate: null } }, o)
test("MediaSources.parseTime: nanoseconds, offsets, unknown", () => {
    assert.equal(MS.parseTime("2026-10-21T13:00:00.123456789Z"), Date.UTC(2026, 9, 21, 13, 0, 0, 123))
    assert.equal(MS.parseTime("2026-10-21T15:00:00+02:00"), Date.UTC(2026, 9, 21, 13))
    assert.ok(isNaN(MS.parseTime(null)))
    assert.ok(isNaN(MS.parseTime("")))
})
test("MediaSources.positionMs extrapolates only while playing, clamps, unknown = -1", () => {
    const at = MS.parseTime("2026-10-21T15:00:00.123456789+02:00")
    assert.equal(MS.positionMs(sess(), at + 5000), 15000)
    assert.equal(MS.positionMs(sess({ playback: { state: "paused", position_ms: 10000, position_at: "2026-10-21T15:00:00Z" } }), at + 5000), 10000)
    assert.equal(MS.positionMs(sess(), at + 500000), 100000)                // not past the end
    assert.equal(MS.positionMs(sess(), at - 5000), 10000)                   // clock behind: no going back
    const rated = sess(); rated.playback.rate = 2
    assert.equal(MS.positionMs(rated, at + 1000), 12000)
    assert.equal(MS.positionMs(sess({ playback: { state: "playing", position_ms: null } }), at), -1)   // stale
    assert.equal(MS.positionMs(null, at), -1)
})
test("MediaSources.can needs controllable + the capability", () => {
    assert.equal(MS.can(sess(), "seek"), true)
    assert.equal(MS.can(sess(), "next"), false)
    assert.equal(MS.can(sess({ controllable: false }), "play"), false)
    assert.equal(MS.can(sess({ capabilities: null }), "play"), false)
    assert.equal(MS.can(null, "play"), false)
})
test("MediaSources labels: no invented metadata", () => {
    assert.equal(MS.artists(sess()), "A, B")
    assert.equal(MS.artists(sess({ track: { title: null, artists: null } })), "")
    assert.equal(MS.playerName(sess()), "Phone (Finamp)")
    assert.equal(MS.playerName(sess({ player: {} })), "Unknown player")
    assert.equal(MS.placeLabel(sess()), "Phone · Finamp")
    assert.equal(MS.placeLabel(sess({ origin: "local" })), "This device")
    assert.equal(MS.kindLabel(sess({ kind: "remote_view_only" })), "remote · view only")
    assert.equal(MS.kindLabel(sess({ kind: "something_new" })), "remote")     // unknown enum values are fine
})
test("MediaSources.errorText", () => {
    assert.equal(MS.errorText({ code: "unsupported_capability" }), "This player doesn't support that")
    assert.equal(MS.errorText({ code: "timeout", message: "after 5s" }), "The player didn't answer in time: after 5s")
    assert.equal(MS.errorText({ code: "brand_new_code", message: "m" }), "Error: m")
    assert.equal(MS.errorText(null), "")
})
test("MediaSources.modeSummary: discovery toggles × mode", () => {
    const st = (mode, l, r) => ({ settings: { mode }, local_enabled: l, remote_enabled: r })
    assert.equal(MS.modeSummary(st("combined", true, true)).text, "Players on this device and remote sessions")
    assert.equal(MS.modeSummary(st("combined", true, false)).text, "Only players on this device")
    assert.equal(MS.modeSummary(st("combined", false, true)).text, "Only remote sessions")
    assert.equal(MS.modeSummary(st("remote_only", true, true)).text, "Only remote sessions")
    assert.equal(MS.modeSummary(st("combined", false, false)).empty, true)
    assert.ok(MS.modeSummary(st("local_only", false, true)).text.includes("discovery on this device is off"))
    assert.equal(MS.modeSummary(null).text, "")
})
test("MediaSources.nextKey wraps, unknown → first", () => {
    assert.equal(MS.nextKey(["a", "b", "c"], "b"), "c")
    assert.equal(MS.nextKey(["a", "b", "c"], "c"), "a")
    assert.equal(MS.nextKey(["a", "b"], "gone"), "a")
    assert.equal(MS.nextKey([], "a"), "")
})
test("MediaSources.serverUrl / serverName like the bridge's config check", () => {
    for (const u of ["https://jellyfin.example.org", "http://192.168.1.5:8096", "https://h/jellyfin"]) assert.equal(MS.serverUrl(u), "", u)
    for (const u of ["", "jellyfin.example.org", "ftp://h", "https://h/?x=1", "https://h#f", "https://user:pw@h"]) assert.notEqual(MS.serverUrl(u), "", u)
    assert.equal(MS.serverName("home"), "")
    assert.notEqual(MS.serverName("my server"), "")
    assert.notEqual(MS.serverName("x".repeat(33)), "")
})
test("MediaSources.clock", () => {
    assert.equal(MS.clock(74000), "1:14")
    assert.equal(MS.clock(3725000), "1:02:05")
    assert.equal(MS.clock(-1), "")
    assert.equal(MS.clock(null), "")
})

const AT = load("AuthText.js")
test("auth text: wrong password", () => {
    assert.equal(AT.failure("", false), "Wrong password")
    assert.equal(AT.failure("pam_authenticate: AUTH_ERR", false), "Wrong password")
})
test("auth text: faillock / max tries", () => {
    assert.equal(AT.failure("", true), "Too many attempts, wait a moment")
    assert.equal(AT.failure("The account is locked due to 3 failed logins.", false), "Too many attempts, wait a moment")
    assert.equal(AT.failure("pam_authenticate: MAXTRIES", false), "Too many attempts, wait a moment")
    assert.equal(AT.failure("The account is locked due to 3 failed logins.\n(1 minute left to unlock)", false), "Too many attempts, try again in 1 minute")
    assert.equal(AT.failure("(10 minutes left to unlock)", false), "Too many attempts, try again in 10 minutes")
    assert.equal(AT.locked("Password: ", false), "")
})

const GL = load("GreeterLib.js")
test("greeter: desktop entries", () => {
    const n = GL.parseDesktop("niri", "[Desktop Entry]\nName=Niri\nExec=niri-session\nType=Application\nDesktopNames=niri\n")
    assert.equal(n.name, "Niri"); assert.equal(n.exec, "niri-session"); assert.deepEqual([...n.desktopNames], ["niri"])
    const h = GL.parseDesktop("h", "[Desktop Entry]\nName=Hyprland (uwsm-managed)\nName[de]=X\nExec=uwsm start -e -D Hyprland hyprland.desktop\nTryExec=uwsm\n[Desktop Action x]\nExec=evil\n")
    assert.equal(h.exec, "uwsm start -e -D Hyprland hyprland.desktop"); assert.equal(h.tryExec, "uwsm")
    assert.equal(GL.parseDesktop("x", "[Desktop Entry]\nName=X\nExec=x\nHidden=true\n"), null)
    assert.equal(GL.parseDesktop("x", "[Desktop Entry]\nName=X\n"), null)
})
test("greeter: exec split", () => {
    assert.deepEqual([...GL.splitExec("uwsm start -e -D Hyprland hyprland.desktop")], ["uwsm", "start", "-e", "-D", "Hyprland", "hyprland.desktop"])
    assert.deepEqual([...GL.splitExec('a "b c" %U d\\e')], ["a", "b c", "d\\e"])
    assert.deepEqual([...GL.splitExec('x ""')], ["x", ""])
})
test("greeter: env + users + pick", () => {
    assert.deepEqual([...GL.sessionEnv({ name: "Hyprland", desktopNames: [] })], ["XDG_SESSION_TYPE=wayland", "XDG_CURRENT_DESKTOP=Hyprland", "XDG_SESSION_DESKTOP=hyprland"])
    const u = GL.users("root:x:0:0::/root:/bin/bash\nme:x:1000:1000:Me Myself,,,:/home/me:/usr/bin/zsh\ngreeter:x:964:964::/:/bin/bash\nsvc:x:1001:1001::/:/usr/bin/nologin\nnobody:x:65534:65534::/:/usr/bin/nologin\n")
    assert.deepEqual([...u.map(x => x.name)], ["me"]); assert.equal(u[0].gecos, "Me Myself")
    const l = [{ id: "a" }, { id: "b" }]
    assert.equal(GL.pick(l, "id", ["", "b"]).id, "b"); assert.equal(GL.pick(l, "id", ["z"]).id, "a"); assert.equal(GL.pick([], "id", ["a"]), null)
})

test("greeter: session icons", () => {
    const ic = (id, name, dn) => GL.sessionIcon({ id: id, name: name, desktopNames: dn ?? [] })
    assert.equal(ic("hyprland-uwsm", "Hyprland (uwsm-managed)", ["Hyprland"]), ic("hyprland", "Hyprland"))
    assert.equal(ic("plasma", "Plasma (Wayland)", ["KDE"]), ic("x", "KDE"))
    const all = ["niri", "hyprland", "gnome", "plasma", "weston"].map(n => ic(n, n))
    assert.equal(new Set(all).size, 5)
    assert.equal(GL.sessionIcon(null), ic("weston", "Weston"))
})

test("greeter: typed users", () => {
    for (const n of ["me", "jane.doe@corp.example", "CORP\\jane", " padded "]) assert.equal(GL.cleanUser(n), n.trim(), n)
    for (const n of ["", "   ", "-f", "a:b", "a/b", "a\nb", "x".repeat(129)]) assert.equal(GL.cleanUser(n), "", JSON.stringify(n))
    const l = GL.withOthers([{ name: "me", uid: 1000, gecos: "Me" }], ["jane@corp", "me", "", "a:b"])
    assert.deepEqual([...l.map(u => u.name + ":" + u.uid)], ["me:1000", "jane@corp:-1"])
    assert.deepEqual([...GL.rememberOther(["a", "b"], { name: "b", uid: -1 })], ["b", "a"])
    assert.deepEqual([...GL.rememberOther(["a", "b"], { name: "me", uid: 1000 })], ["a", "b"])
    assert.equal(GL.rememberOther(["a", "b", "c", "d", "e"], { name: "f", uid: -1 }).length, 5)
})

test("greeter: greetd mode + lock at start", () => {
    const greeter = '[terminal]\nvt = 1\n\n# login screen\n[default_session]\ncommand = "/usr/local/share/quickshell-greeter/greeter-session || agreety --cmd niri-session"\nuser = "greeter"\n'
    assert.equal(GL.greetdMode(greeter), "greeter")
    assert.equal(GL.greetdMode(greeter + '\n[initial_session]\ncommand = "niri-session"\nuser = "me"\n'), "autologin-boot")
    assert.equal(GL.greetdMode('[initial_session]\ncommand = "niri-session"\nuser = "me"\n[default_session]\ncommand = "niri-session"\nuser = "me"\n'), "autologin")
    assert.equal(GL.greetdMode('[default_session]\ncommand = "tuigreet"\nuser = "greeter"\n'), "unknown")
    assert.equal(GL.greetdMode(""), "unknown")
    assert.equal(GL.lockAtStart("greeter", "b1", ""), false)
    assert.equal(GL.lockAtStart("autologin-boot", "b1", "b0"), true); assert.equal(GL.lockAtStart("autologin-boot", "b1", "b1"), false)
    assert.equal(GL.lockAtStart("autologin-boot", "", ""), true)
    assert.equal(GL.lockAtStart("autologin", "b1", "b1"), true); assert.equal(GL.lockAtStart("unknown", "b1", "b1"), true)
})

const SN = load("Snap.js")
test("snap: raster + guides", () => {
    assert.equal(SN.grid(13, 8), 16); assert.equal(SN.grid(13, 0), 13)
    assert.equal(SN.snap1(103, [100, 200], 12, 8).value, 100); assert.equal(SN.snap1(130, [100], 12, 8).value, 128)
    const r = SN.snapRect({ x: 1225, y: 7, w: 100, h: 40 }, SN.screenGuides(2560, 1440, 10), 12, 8)
    assert.equal(r.x, 1230); assert.equal(r.gx, 1280)            // centre on the screen centre
    assert.equal(r.y, 10); assert.equal(r.gy, 10)                // top edge on the inset
    const f = SN.snapRect({ x: 501, y: 603, w: 10, h: 10 }, { x: [], y: [] }, 12, 8)
    assert.equal(f.x, 504); assert.equal(f.y, 600); assert.equal(f.gx, null)
})
test("snap: magnet pull", () => {
    const s = { x: 100, y: 0 }
    assert.deepEqual({ ...SN.pull({ x: 200, y: 0 }, s, 60) }, { x: 200, y: 0 })     // outside: free
    assert.deepEqual({ ...SN.pull({ x: 110, y: 0 }, s, 60) }, { x: 100, y: 0 })     // core: on the slot
    const m = SN.pull({ x: 140, y: 0 }, s, 60)
    assert.ok(m.x > 100 && m.x < 140, "between: " + m.x)
    assert.deepEqual({ ...SN.pull({ x: 5, y: 5 }, null, 60) }, { x: 5, y: 5 })
})
test("snap: edges + limits", () => {
    assert.equal(SN.nearestEdge(1280, 20, 2560, 1440), "top"); assert.equal(SN.nearestEdge(1280, 1430, 2560, 1440), "bottom")
    assert.equal(SN.nearestEdge(5, 700, 2560, 1440), "left"); assert.equal(SN.nearestEdge(2550, 700, 2560, 1440), "right")
    assert.equal(SN.vertical("left"), true); assert.equal(SN.vertical("top"), false)
    assert.equal(SN.clamp(5, 10, 20), 10); assert.equal(SN.clamp(25, 10, 20), 20); assert.equal(SN.clamp(5, 10, 0), 10)
    assert.equal(SN.resize(400, 13, 300, 800, 8), 416); assert.equal(SN.resize(400, -300, 300, 800, 8), 300)
})

const PG = load("PanelGeom.js")
test("panels: defaults, clamping, store", () => {
    const r = PG.resolve({})
    assert.equal(r.bar.edge, "top"); assert.equal(r.dashboard.width, 1070); assert.equal(r.controlCenter.along, "end")
    assert.equal(r.launcher.attach, "edge"); assert.equal(r.launcher.views.wallpapers.w, 960)
    const c = PG.resolve({ bar: { edge: "left", thickness: 9 }, dashboard: { width: "x", along: 0.3 }, launcher: { attach: "bar", views: { apps: { w: 700 } } } })
    assert.equal(c.bar.edge, "left"); assert.equal(c.bar.thickness, 36); assert.equal(c.dashboard.width, 1070); assert.equal(c.dashboard.along, 0.3)
    assert.equal(c.launcher.views.apps.w, 700); assert.equal(c.launcher.views.apps.h, 360)
    assert.equal(PG.resolve({ dashboard: { attach: "edge" } }).dashboard.attach, "bar")      // edge: launcher only
    assert.deepEqual(JSON.parse(JSON.stringify(PG.store({}, "dashboard", "width", 1200))), { width: 1200 })
    assert.equal(PG.store({ width: 1200 }, "dashboard", "width", 1070), null)
    assert.deepEqual(JSON.parse(JSON.stringify(PG.store({}, "launcher", "views", { apps: { w: 800, h: 360 } }))), { views: { apps: { w: 800 } } })
})
test("panels: import check", () => {
    assert.equal(PG.validate({ bar: { edge: "bottom" }, launcher: { views: { apps: { w: 700 } } } }), "")
    assert.notEqual(PG.validate({ bar: { edge: "middle" } }), "")
    assert.notEqual(PG.validate({ foo: {} }), "")
    assert.notEqual(PG.validate({ dashboard: { colour: 1 } }), "")
    assert.notEqual(PG.validate({ launcher: { views: { nope: { w: 1 } } } }), "")
    assert.notEqual(PG.validate([]), "")
    assert.equal(PG.validate({ cards: { tools: { perRow: 4, tile: 64 } } }), "")
    assert.notEqual(PG.validate({ cards: { tools: { size: 4 } } }), "")
    assert.notEqual(PG.validate({ cards: { "a b": { perRow: 2 } } }), "")
})
test("panels: button cards", () => {
    assert.deepEqual({ ...PG.card(undefined) }, { perRow: 3, tile: 56 })
    assert.equal(PG.resolve({ cards: { tools: { perRow: 9 } } }).cards.tools.perRow, 6)
    assert.deepEqual(JSON.parse(JSON.stringify(PG.storeCard({}, "tools", "perRow", 4))), { tools: { perRow: 4 } })
    assert.equal(PG.storeCard({ tools: { perRow: 4 } }, "tools", "perRow", 3), null)
})

const EM = load("EdgeMap.js")
test("edges: map points / rects / matrices agree", () => {
    const D = 300
    for (const e of ["top", "bottom", "left", "right"]) {
        const m = EM.matrix(e, D)
        for (const [u, v] of [[0, 0], [120, 40], [500, 299]]) {
            const p = EM.mapPoint(e, D, u, v)
            assert.equal(m[0] * u + m[1] * v + m[3], p.x, e + " x"); assert.equal(m[4] * u + m[5] * v + m[7], p.y, e + " y")
        }
        // a rect's mapped corners = the mapped rect
        const r = EM.mapRect(e, D, 100, 20, 400, 60)
        const a = EM.mapPoint(e, D, 100, 20), b = EM.mapPoint(e, D, 500, 80)
        assert.equal(r.x, Math.min(a.x, b.x), e); assert.equal(r.y, Math.min(a.y, b.y), e)
        assert.equal(r.w, Math.abs(a.x - b.x), e); assert.equal(r.h, Math.abs(a.y - b.y), e)
    }
    assert.deepEqual({ ...EM.mapRect("left", D, 100, 0, 400, 60) }, { x: 0, y: 100, w: 60, h: 400 })
})
test("edges: corners follow the map", () => {
    // each canonical corner point lands on the real corner named for it
    const D = 50, L = 1000, c = { outerStart: 1, outerEnd: 2, innerEnd: 3, innerStart: 4 }
    const at = { outerStart: [0, 0], outerEnd: [L, 0], innerEnd: [L, D], innerStart: [0, D] }
    for (const e of ["top", "bottom", "left", "right"]) {
        const k = EM.corners(e, c), r = EM.mapRect(e, D, 0, 0, L, D)
        for (const name in at) {
            const p = EM.mapPoint(e, D, at[name][0], at[name][1])
            const real = (p.y === r.y ? "t" : "b") + (p.x === r.x ? "l" : "r")
            assert.equal(k[real], c[name], e + " " + name)
        }
    }
})
test("edges: anchors, sizes, placing", () => {
    assert.deepEqual({ ...EM.anchors("bottom") }, { top: false, bottom: true, left: true, right: true })
    assert.deepEqual({ ...EM.anchors("left") }, { top: true, bottom: true, left: true, right: false })
    assert.equal(EM.opposite("top"), "bottom"); assert.equal(EM.opposite("left"), "right")
    assert.deepEqual({ ...EM.toCanon("right", 420, 900) }, { along: 900, depth: 420 })
    assert.equal(EM.place("start", 400, 2560, 10), 10); assert.equal(EM.place("end", 400, 2560, 10), 2150)
    assert.equal(EM.place("center", 400, 2560, 10), 1080); assert.equal(EM.place(0.25, 400, 2560, 10), 440)
    assert.equal(EM.place(0, 400, 2560, 10), 10); assert.equal(EM.place("end", 3000, 2560, 10), -220)
})

test("edges: the panel editor's picture", () => {
    const s = { w: 2560, h: 1440 }, bar = { edge: "top", thickness: 50, gap: 10, inset: 10 }
    assert.deepEqual({ ...EM.barRect(s, bar) }, { x: 10, y: 10, w: 2540, h: 50 })
    assert.deepEqual({ ...EM.barRect(s, { ...bar, edge: "right" }) }, { x: 2500, y: 10, w: 50, h: 1420 })
    // control center at the end of a top bar: flush right, under the bar
    assert.deepEqual({ ...EM.panelRect(s, 420, 700, { edge: "top", offset: 60, along: "end", flare: 30, inset: 10 }) }, { x: 2130, y: 60, w: 420, h: 700 })
    // dashboard centred on a left bar: right of it, centred vertically
    assert.deepEqual({ ...EM.panelRect(s, 1070, 480, { edge: "left", offset: 60, along: "center", flare: 30, inset: 10 }) }, { x: 60, y: 480, w: 1070, h: 480 })
    // launcher from the bottom screen edge
    assert.deepEqual({ ...EM.panelRect(s, 640, 300, { edge: "bottom", offset: 0, along: "center", flare: 30, inset: 10 }) }, { x: 960, y: 1140, w: 640, h: 300 })
    assert.deepEqual({ ...EM.panelRect(s, 400, 200, { float: true, x: 0.5, y: 0.5 }) }, { x: 1080, y: 620, w: 400, h: 200 })
    assert.equal(EM.alongAt(s, "top", 1285, 300, 1070, 10, 30, 48, 8), "center")
    assert.equal(EM.alongAt(s, "top", 2340, 300, 420, 10, 30, 48, 8), "end")
    assert.equal(EM.alongAt(s, "top", 800, 300, 420, 10, 30, 48, 8), 0.313)
    assert.equal(EM.depthOf(s, "bottom", 0, 1400), 40); assert.equal(EM.depthOf(s, "left", 300, 0), 300)
})

const LI = load("LockItems.js")
test("greeter settings follow the lockscreen", () => {
    const g = LI.resolveGreeter({ seconds: false, monitors: ["A B C"] }, {})
    assert.equal(g.follow, true); assert.equal(g.seconds, false); assert.equal(g.date, true)
    assert.deepEqual([...g.monitors], ["A B C"]); assert.equal(g.userPicker, "auto"); assert.equal(g.sync, true)
    const o = LI.resolveGreeter({ seconds: false, monitors: ["A B C"] }, { follow: false, blur: false, monitors: ["X"], defaultUser: "me" })
    assert.equal(o.seconds, true); assert.equal(o.blur, false); assert.deepEqual([...o.monitors], ["X"]); assert.equal(o.defaultUser, "me")
    assert.equal(LI.resolveGreeter(undefined, undefined).power, true)
})
test("greeter settings check", () => {
    assert.equal(LI.checkGreeter("follow", true), ""); assert.notEqual(LI.checkGreeter("follow", 1), "")
    assert.equal(LI.checkGreeter("userPicker", "off"), ""); assert.notEqual(LI.checkGreeter("userPicker", "x"), "")
    assert.equal(LI.checkGreeter("blur", false), ""); assert.equal(LI.checkGreeter("media", true), null)
    assert.equal(LI.checkGreeter("defaultUser", "arkaizn"), ""); assert.notEqual(LI.checkGreeter("defaultUser", "a b"), "")
    assert.equal(LI.checkGreeter("defaultSession", "niri"), ""); assert.notEqual(LI.checkGreeter("defaultSession", "../x"), "")
    assert.notEqual(LI.checkGreeter("monitors", "x"), "")
})

const MU = load("MailUtil.js")
// arrays from the vm context have another prototype: compare as JSON
const same = (a, b) => assert.deepEqual(JSON.parse(JSON.stringify(a)), b)
test("mail: base subject strips reply / forward prefixes", () => {
    assert.equal(MU.baseSubject("Re: AW: Fwd: Hallo"), "Hallo")
    assert.equal(MU.baseSubject("RE[2]: WG: Termin"), "Termin")
    assert.equal(MU.baseSubject("[list] Re: Patch"), "Patch")
    assert.equal(MU.baseSubject("Revenue report"), "Revenue report")
    assert.equal(MU.replySubject("Re: Re: x"), "Re: x")
    assert.equal(MU.forwardSubject("AW: x"), "Fwd: x")
})
test("mail: threads by references", () => {
    const m = (id, mid, refs, date, extra) => Object.assign({ id: id, messageId: mid, refs: refs, date: date, subject: "s", from: { name: id, email: id + "@x" }, seen: true }, extra || {})
    const t = MU.threads([
        m("a", "<1>", [], 1), m("b", "<2>", ["<1>"], 3, { seen: false }), m("c", "<3>", ["<1>", "<2>"], 5),
        m("d", "<4>", [], 4, { flagged: true }), m("e", "", [], 2),
        m("f", "<6>", ["<5-missing>"], 6), m("g", "<7>", ["<5-missing>"], 7)     // siblings of a missing parent
    ])
    same(t.map(x => x.msgs.map(y => y.id).join("")), ["fg", "abc", "d", "e"])
    assert.equal(t[1].unread, 1)
    assert.equal(t[2].flagged, true)
    same(t[1].people, ["a", "b", "c"])
})
test("mail: day groups and short dates", () => {
    const now = new Date(2026, 9, 28, 15, 0).getTime()          // a Wednesday
    const at = (d, h) => new Date(2026, 9, d, h || 10).getTime()
    assert.equal(MU.dayGroup(at(28), now), "Today")
    assert.equal(MU.dayGroup(at(27), now), "Yesterday")
    assert.equal(MU.dayGroup(at(26), now), "Monday")
    assert.equal(MU.dayGroup(at(22), now), "Last week")
    assert.equal(MU.dayGroup(at(5), now), "October")
    assert.equal(MU.dayGroup(new Date(2025, 2, 1).getTime(), now), "March 2025")
    assert.equal(MU.shortDate(new Date(2026, 9, 28, 9, 5).getTime(), now), "09:05")
    assert.equal(MU.shortDate(at(26), now), "Mon")
    assert.equal(MU.shortDate(at(3), now), "3 Oct")
    assert.equal(MU.shortDate(new Date(2024, 0, 9).getTime(), now), "9.1.24")
})
test("mail: address parsing", () => {
    const r = MU.parseAddresses('Lea <lea@x.org>, tom@x.org; "Keller, Tom" <t@k.ch>, nope, ')
    same(r.list, [{ name: "Lea", email: "lea@x.org" }, { name: "", email: "tom@x.org" }, { name: "Keller, Tom", email: "t@k.ch" }])
    same(r.bad, ["nope"])
    assert.equal(MU.formatAddress({ name: "Keller, Tom", email: "t@k.ch" }), '"Keller, Tom" <t@k.ch>')
    assert.equal(MU.formatAddress({ name: "", email: "a@b.c" }), "a@b.c")
})
test("mail: reply recipients", () => {
    const m = { from: { name: "Lea", email: "lea@x.org" }, replyTo: [], to: [{ name: "Me", email: "ME@me.org" }, { name: "Tom", email: "tom@x.org" }],
                cc: [{ name: "Lea again", email: "lea@x.org" }, { name: "Mia", email: "mia@x.org" }] }
    const one = MU.replyRecipients(m, ["me@me.org"], false)
    same(one.to.map(a => a.email), ["lea@x.org"]); same(one.cc, [])
    const all = MU.replyRecipients(m, ["me@me.org"], true)
    same(all.cc.map(a => a.email), ["tom@x.org", "mia@x.org"])          // not me, not Lea twice
    const list = MU.replyRecipients(Object.assign({}, m, { replyTo: [{ name: "List", email: "list@x.org" }] }), ["me@me.org"], false)
    same(list.to.map(a => a.email), ["list@x.org"])
    const own = MU.replyRecipients({ from: { email: "me@me.org" }, to: [{ email: "boss@x.org" }] }, ["me@me.org"], false)
    same(own.to.map(a => a.email), ["boss@x.org"])                       // my sent mail: to its recipients
})
test("mail: quote and forward", () => {
    const q = MU.quote("hi\n> old\n", { name: "Lea", email: "l@x" }, new Date(2026, 9, 28, 9, 5).getTime())
    assert.equal(q, "On Wednesday, 28 October 2026, 09:05, Lea wrote:\n> hi\n>> old")
    const f = MU.forwardText({ subject: "S", date: 0, from: { name: "", email: "a@b.c" }, to: [{ name: "T", email: "t@b.c" }] }, "body")
    assert.ok(f.startsWith("-------- Forwarded message --------\nSubject: S\n"))
    assert.ok(f.includes("From: a@b.c\nTo: T <t@b.c>\n\nbody"))
})
test("mail: quick filter", () => {
    const m = { subject: "Rechnung Oktober", from: { name: "Stadtwerke", email: "r@sw.ch" }, preview: "anbei", seen: true, flagged: true, attachments: 1, to: [] }
    assert.ok(MU.matches(m, { text: "rechnung stadt" }))
    assert.ok(!MU.matches(m, { text: "rechnung november" }))
    assert.ok(!MU.matches(m, { unread: true }))
    assert.ok(MU.matches(m, { flagged: true, attachments: true, text: "" }))
})
test("mail: collected addresses and completion", () => {
    let book = MU.collect([], [{ name: "Lea Fischer", email: "lea@x.org" }, { name: "", email: "tom@x.org" }, { name: "x", email: "bad" }], 1)
    book = MU.collect(book, [{ name: "", email: "LEA@x.org" }], 2)
    assert.equal(book.length, 2)
    assert.equal(book[0].name, "Lea Fischer"); assert.equal(book[0].count, 2)
    same(MU.complete(book, "tom@x.org, le").map(a => a.email), ["LEA@x.org"])
    same(MU.complete(book, "fisch").map(a => a.email), ["LEA@x.org"])
    assert.equal(MU.insertAddress("tom@x.org, le", { name: "Lea", email: "lea@x.org" }), "tom@x.org, Lea <lea@x.org>, ")
    assert.equal(MU.initials({ name: "Lea Fischer", email: "" }), "LF")
    assert.equal(MU.initials({ name: "", email: "tom@x.org" }), "T")
})

test("mail: mailto links", () => {
    same(MU.parseMailto("mailto:lea@x.org?subject=Hallo%20Lea&cc=tom@x.org&body=Zeile%201%0AZeile%202&x-evil=1"),
         { to: "lea@x.org", cc: "tom@x.org", bcc: "", subject: "Hallo Lea", body: "Zeile 1\nZeile 2" })
    same(MU.parseMailto("mailto:?to=a@x.org&to=b@x.org&subject=a+b").to, "a@x.org, b@x.org")
    assert.equal(MU.parseMailto("mailto:a@x.org?subject=x%0D%0ABcc:%20evil@x.org").subject, "x Bcc: evil@x.org")
    assert.equal(MU.parseMailto("mailto:bad%zz@x.org").to, "bad%zz@x.org")      // broken escapes don't throw
})
test("mail: attachment reminder", () => {
    assert.ok(MU.mentionsAttachment("Hallo,\nanbei die Rechnung."))
    assert.ok(MU.mentionsAttachment("See the attached file"))
    assert.ok(!MU.mentionsAttachment("Hi\n\n> anbei das Dokument"))           // only in the quote
    assert.ok(!MU.mentionsAttachment("Hi\n\n-- \nSee attachment policy"))      // only in the signature
    assert.ok(!MU.mentionsAttachment("Wir treffen uns morgen"))
})

test("mail: people you wrote to come first", () => {
    let book = MU.collect([], [{ name: "Anna News", email: "anna@news.example" }], 100)
    book = MU.collect(book, [{ name: "Anna News", email: "anna@news.example" }], 200)
    book = MU.collect(book, [{ name: "Anna Keller", email: "anna.keller@example.org" }], 50, true)
    const hits = MU.complete(book, "ann", 6)
    assert.equal(hits[0].email, "anna.keller@example.org")
    assert.equal(hits[0].sent, 1)
    assert.equal(book.find(a => a.email === "anna@news.example").sent, 0)
    assert.equal(MU.complete(book, "kel", 6)[0].email, "anna.keller@example.org")   // a later name word
})

const Cal = (() => {
    const ctx = vm.createContext({})
    vm.runInContext(readFileSync(join(lib, "..", "..", "modules", "calendar", "CalUtil.js"), "utf8").replace(/^\.pragma library/m, ""), ctx)
    return ctx
})()
test("calendar: short events keep their real length", () => {
    const day = new Date(2026, 9, 28)
    const t = (h, m) => new Date(2026, 9, 28, h, m).getTime()
    const items = Cal.layoutDay([{ start: t(14, 44), end: t(14, 48) }, { start: t(15, 0), end: t(16, 0) }], day, 20)
    assert.equal(items[0].top, 14 * 60 + 44)
    assert.equal(items[0].bottom, 14 * 60 + 48)            // not stretched past 15:00
    assert.equal(items[0].reach, 14 * 60 + 64)             // its label's room …
    assert.equal(items[1].cols, 2)                          // … puts the 15:00 one beside it
    const apart = Cal.layoutDay([{ start: t(14, 0), end: t(14, 4) }, { start: t(15, 0), end: t(16, 0) }], day, 20)
    assert.equal(apart[1].cols, 1)
})

test("MailUtil.linkCheck: what a link says vs. where it goes", () => {
    const html = '<a href="https://evil.example.ru/x?a=1&amp;b=2">www.paypal.com</a> <a href="https://www.paypal.com/de">PayPal</a>'
    const texts = MU.anchorTexts(html)
    assert.deepEqual(Object.keys(texts), ["https://evil.example.ru/x?a=1&b=2", "https://www.paypal.com/de"])
    assert.match(MU.linkCheck("https://evil.example.ru/x?a=1&b=2", texts["https://evil.example.ru/x?a=1&b=2"]).warn, /paypal\.com.*example\.ru/)
    assert.equal(MU.linkCheck("https://www.paypal.com/de", ["PayPal"]).warn, "")
    assert.equal(MU.linkCheck("https://links.paypal.com/t", ["paypal.com"]).warn, "")       // same site, other host
    assert.equal(MU.linkCheck("https://www.bbc.co.uk/news", ["bbc.co.uk"]).site, "bbc.co.uk")
    assert.match(MU.linkCheck("https://paypal.com@evil.ru/", []).warn, /disguise/)
    assert.match(MU.linkCheck("http://192.168.1.4/login", []).warn, /IP address/)
    assert.match(MU.linkCheck("https://xn--pypal-4ve.com/", []).warn, /look-alike/)
    assert.match(MU.linkCheck("javascript:alert(1)", []).warn, /javascript/)
    assert.equal(MU.linkCheck("mailto:a@b.org", []).warn, "")
})

test("MailUtil.findDates", () => {
    const now = new Date(2026, 9, 30, 10, 0).getTime()          // Fri 30 Oct 2026
    const at = (y, m, d, h, mi) => new Date(y, m, d, h ?? 0, mi ?? 0).getTime()
    let f = MU.findDates("Termin am 12.11.2026 um 14:00 Uhr im Büro", now)
    assert.deepEqual([f[0].start, f[0].allDay], [at(2026, 10, 12, 14), false])
    f = MU.findDates("Meeting: 3. Dezember, 9:30 – 11:00", now)
    assert.deepEqual([f[0].start, f[0].end], [at(2026, 11, 3, 9, 30), at(2026, 11, 3, 11)])
    f = MU.findDates("See you on November 5th at 2 pm", now)
    assert.equal(f[0].start, at(2026, 10, 5, 14))
    f = MU.findDates("Deadline 2026-12-01", now)
    assert.deepEqual([f[0].start, f[0].allDay], [at(2026, 11, 1), true])
    f = MU.findDates("Am 5.1. geht's los", now)                     // already past this year: next year
    assert.equal(f[0].start, at(2027, 0, 5))
    assert.equal(MU.findDates("Version 1.2.3, 12.50 CHF, gestern 01.10.2026", now).length, 0)
    assert.equal(MU.findDates("> am 12.11.2026 um 9:00\nneu", now).length, 0)              // quoted
    assert.equal(MU.findDates("12.11.2026 und nochmal 12.11.2026", now).length, 1)
})

test("MailUtil.linkDates: dates in the HTML become qsdate: links", () => {
    const now = new Date(2026, 9, 30, 10, 0).getTime()
    const s = new Date(2026, 9, 31).getTime()
    const h = MU.linkDates('<p>Am Samstag 31.&nbsp;Oktober gibt es <b>12.11.2026 um 14:00 Uhr</b> und <a href="x">5.12.2026</a></p>', now, "color:red")
    assert.ok(h.includes('<a href="qsdate:' + s + '-0-1" style="color:red">31.&nbsp;Oktober</a>'), h)
    const t = new Date(2026, 10, 12, 14).getTime()
    assert.ok(h.includes('<a href="qsdate:' + t + '-0-0" style="color:red">12.11.2026 um 14:00 Uhr</a>'), h)
    assert.ok(h.includes('<a href="x">5.12.2026</a>'))                   // already a link: left alone
    const d = MU.parseDateLink("qsdate:" + t + "-0-0")
    assert.deepEqual([d.start, d.end, d.allDay], [t, 0, false])
    assert.equal(MU.parseDateLink("https://x.org"), null)
})

const TC = load("ThemeCheck.js")
test("ThemeCheck keeps a plain theme, rebuilt", () => {
    const colors = {}; for (let i = 0; i < 16; i++) colors["color" + i] = "#10203" + (i % 10)
    const r = TC.clean({ special: { background: "#000000", foreground: "#ffffff" }, colors, wallpaper: "/home/u/Pictures/a b.png", alpha: "90", extra: "x" })
    assert.equal(r.ok, true)
    assert.equal(r.theme.special.cursor, "#ffffff")              // missing cursor: the foreground
    assert.equal(r.theme.wallpaper, "/home/u/Pictures/a b.png")
    assert.equal(r.theme.alpha, "90")
    assert.equal(r.theme.extra, undefined)
})
test("ThemeCheck refuses shell code in colours, drops it in the wallpaper", () => {
    const colors = {}; for (let i = 0; i < 16; i++) colors["color" + i] = "#000000"
    const bad = Object.assign({}, colors, { color3: "#000000'; touch /tmp/x; '" })
    assert.equal(TC.clean({ special: { background: "#000000", foreground: "#ffffff" }, colors: bad }).ok, false)
    const r = TC.clean({ special: { background: "#000000", foreground: "#ffffff" }, colors, wallpaper: "x'; curl e | sh; '" })
    assert.equal(r.ok, true)
    assert.equal(r.theme.wallpaper, undefined)
    assert.equal(TC.clean({ special: { background: "$(id)", foreground: "#ffffff" }, colors }).ok, false)
    assert.equal(TC.clean([]).ok, false)
})

test("ThemeCheck.wallpaperPath: pictures without shell characters", () => {
    const T = load("ThemeCheck.js")
    assert.ok(T.wallpaperPath("/home/u/Pictures/a b.jpg"))
    assert.ok(!T.wallpaperPath("/home/u/x.txt"))
    assert.ok(!T.wallpaperPath("relative.png"))
    assert.ok(!T.wallpaperPath("/home/u/it's.png"))
    assert.ok(!T.wallpaperPath("/home/u/$(x).png"))
    assert.ok(!T.wallpaperPath("/a/../etc/x.png"))
})
const FmSettings = load("FmSettings.js")
test("FmSettings checks values against the spec", () => {
    assert.equal(FmSettings.check("solid", true), "")
    assert.notEqual(FmSettings.check("solid", "yes"), "")
    assert.equal(FmSettings.check("sidebarWidth", 230), "")
    assert.notEqual(FmSettings.check("sidebarWidth", 9999), "")
    assert.notEqual(FmSettings.check("sidebarWidth", 230.5), "")
    assert.notEqual(FmSettings.check("nope", 1), "")
    assert.equal(FmSettings.check("openFrom", "window"), "")
    assert.notEqual(FmSettings.check("openFrom", "popup"), "")
})
test("FmSettings: page sections name real keys, allowed() by file system", () => {
    for (const sec of FmSettings.sections()) for (const it of sec.items) {
        assert.ok(it && it.key && it.label, "section item " + sec.title)
        assert.equal(FmSettings.check(it.key, it.def), "", it.key + " default fits its spec")
    }
    assert.equal(FmSettings.allowed("local", "ext4"), true)
    assert.equal(FmSettings.allowed("local", "cifs"), false)
    assert.equal(FmSettings.allowed("always", "cifs"), true)
    assert.equal(FmSettings.allowed("never", "ext4"), false)
})
test("FmTransfer: export file checked, merged without losing anything", () => {
    const T = load("FmTransfer.js")
    const J = x => JSON.parse(JSON.stringify(x))
    const src = { settings: { solid: true }, bookmarks: [{ uri: "file:///home/u/A", label: "" }, { uri: "sftp://me@host/x", label: "Box" }],
                  groups: [{ id: "g1", name: "Work", color: "blue", open: true }], groupPins: { "file:///home/u/A": "g1" },
                  servers: [{ uri: "sftp://me:secret@host", name: "host" }], starred: ["/home/u/s.txt"], views: { columns: ["size"] } }
    const all = T.build(T.PARTS, src, "2026-11-06")
    assert.equal(all.servers[0].uri, "sftp://me@host", "never a password")
    const only = T.build(["settings"], src, "x")
    assert.equal(only.bookmarks, undefined)
    // round trip
    const r = T.parse(JSON.stringify(all))
    assert.equal(r.error, "")
    assert.deepEqual(JSON.parse(JSON.stringify(T.count(r.doc))), { settings: 1, bookmarks: 2, servers: 1, starred: 1, views: 1 })
    // bad input
    assert.notEqual(T.parse("{").error, "")
    assert.notEqual(T.parse('{"quickshellSettings":1}').error, "")
    const bad = T.parse(JSON.stringify({ quickshellFiles: 1,
        bookmarks: [{ uri: "javascript:x" }, { uri: "file:///ok" }, { uri: "file:///a b" }, { uri: "file:///n", label: "two\nlines" }],
        groups: [{ id: "../x", name: "x" }, { id: "g", name: "G", color: "$(x)" }], groupPins: { "file:///ok": "g", "file:///gone": "g" },
        servers: [{ uri: "http://x" }, { uri: "smb://u:pw@srv/share" }], starred: ["rel", "/a/../etc", "/ok"], views: [] }))
    assert.equal(bad.error, "")
    assert.deepEqual(J(bad.doc.bookmarks.map(b => b.uri)), ["file:///ok"])
    assert.equal(bad.doc.groups.length, 1)
    assert.equal(bad.doc.groups[0].color, "blue")
    assert.deepEqual(J(Object.keys(bad.doc.groupPins)), ["file:///ok"])
    assert.deepEqual(J(bad.doc.servers.map(x => x.uri)), ["smb://u@srv/share"])
    assert.deepEqual(J(Array.from(bad.doc.starred)), ["/ok"])
    assert.ok(bad.problems.length >= 8)
    // merge: added to what's there; groups by name; a pinned bookmark stays in its group
    const cur = { bookmarks: [{ uri: "file:///home/u/A" }], groups: [{ id: "h1", name: "Work", color: "red", open: false }],
                  groupPins: {}, servers: [{ uri: "sftp://me@host", name: "mine" }], starred: ["/x"] }
    const doc = T.parse(JSON.stringify(Object.assign({}, all, { groups: all.groups.concat([{ id: "g2", name: "New", color: "teal" }]),
                                                              groupPins: { "file:///home/u/A": "g1", "sftp://me@host/x": "g2" } }))).doc
    const m = T.merge(cur, doc, ["bookmarks", "servers", "starred"], i => "n" + i)
    assert.deepEqual(J(m.bookmarks.map(b => b.uri)), ["sftp://me@host/x"])
    assert.deepEqual(J(m.groups.map(g => g.id + ":" + g.name)), ["h1:Work", "n0:New"])
    assert.equal(m.groupPins["file:///home/u/A"], "h1")
    assert.equal(m.groupPins["sftp://me@host/x"], "n0")
    assert.equal(m.servers.length, 1)
    assert.equal(m.servers[0].name, "mine")
    assert.deepEqual(J(m.starred), ["/x", "/home/u/s.txt"])
    assert.equal(m.views, undefined, "not picked")
})
test("FmSettings.checkRemote only lets the file manager write its own keys", () => {
    const zoom = ["50", "100", "125"]
    assert.equal(FmSettings.checkRemote("files", "solid", false, zoom), "")
    assert.equal(FmSettings.checkRemote("files", "solid", undefined, zoom), "")
    assert.notEqual(FmSettings.checkRemote("files", "nope", undefined, zoom), "")
    assert.equal(FmSettings.checkRemote("zoom", "files", "125", zoom), "")
    assert.notEqual(FmSettings.checkRemote("zoom", "files", "123", zoom), "")
    assert.notEqual(FmSettings.checkRemote("zoom", "mail", "125", zoom), "")
    assert.equal(FmSettings.checkRemote("icons", "files.home", "󰋜", zoom), "")
    assert.notEqual(FmSettings.checkRemote("icons", "arch", "x", zoom), "")
    assert.notEqual(FmSettings.checkRemote("icons", "files.../x", "x", zoom), "")
    assert.equal(FmSettings.checkRemote("iconColors", "files.home", false, zoom), "")
    assert.notEqual(FmSettings.checkRemote("iconColors", "files.home", true, zoom), "")
    assert.notEqual(FmSettings.checkRemote("properties", "radius", 3, zoom), "")
    assert.notEqual(FmSettings.checkRemote("files", "", 1, zoom), "")
})
test("FmSettings.launchCommand quotes the path, falls back to Nautilus", () => {
    assert.equal(FmSettings.launchCommand("/home/u/.config/quickshell"), "'/home/u/.config/quickshell/scripts/files/files.sh' || nautilus --new-window")
    assert.equal(FmSettings.launchCommand("/a'b"), "'/a'\\''b/scripts/files/files.sh' || nautilus --new-window")
})
test("FmSettings.validate reports every bad key", () => {
    const errs = []
    FmSettings.validate({ solid: 1, sidebarWidth: 200, x: 2 }, (path, m) => errs.push(path[0]))
    assert.deepEqual(errs, ["solid", "x"])
})

// ── the file manager's own libraries (modules/files/lib) ──
const fmLib = join(dirname(fileURLToPath(import.meta.url)), "..", "modules", "files", "lib")
function loadFm(name) {
    const ctx = vm.createContext({})
    vm.runInContext(readFileSync(join(fmLib, name), "utf8").replace(/^\.pragma library/m, ""), ctx)
    return ctx
}

const FmSort = loadFm("FmSort.js")
// the same names and order as tests/files/test_filesd.py (the backend sorts, this places changes)
const sortNames = ["file10.txt", "File2.txt", "file1.txt", "b", "a10", "a9", "a09b", "Zed", "z"]
const sortExpect = ["a9", "a09b", "a10", "b", "file1.txt", "File2.txt", "file10.txt", "z", "Zed"]
const it = n => ({ name: n, dir: false, size: 0, mtime: 0, type: "" })
test("FmSort: natural, case-insensitive, like the backend", () => {
    assert.deepEqual(sortNames.map(it).sort((a, b) => FmSort.compare(a, b, {})).map(i => i.name), sortExpect)
    const all = sortNames.map(it).concat([{ name: "zz dir", dir: true }, { name: "A dir", dir: true }])
    assert.deepEqual(all.sort((a, b) => FmSort.compare(a, b, { reverse: true })).map(i => i.name),
                     ["zz dir", "A dir"].concat(sortExpect.slice().reverse()))
    assert.deepEqual(all.sort((a, b) => FmSort.compare(a, b, { dirsFirst: false })).map(i => i.name),
                     ["a9", "a09b", "a10", "A dir", "b", "file1.txt", "File2.txt", "file10.txt", "z", "Zed", "zz dir"])
})
test("FmSort: huge numbers and ties", () => {
    assert.ok(FmSort.nameCmp("x99999999999999999999", "x100000000000000000000") < 0)
    assert.ok(FmSort.nameCmp("a", "A") > 0)                    // same key: by the exact name
    assert.ok(FmSort.nameCmp("a", "a1") < 0)
})
test("FmSort.insertIndex keeps the order", () => {
    const opts = { by: "size" }
    const list = [{ name: "d", dir: true, size: 0 }, { name: "a", size: 1 }, { name: "b", size: 5 }, { name: "c", size: 9 }]
    const at = i => list[i]
    assert.equal(FmSort.insertIndex(list.length, at, { name: "x", size: 5 }, opts), 3)
    assert.equal(FmSort.insertIndex(list.length, at, { name: "0", size: 0 }, opts), 1)
    assert.equal(FmSort.insertIndex(list.length, at, { name: "e", dir: true, size: 0 }, opts), 1)
    assert.equal(FmSort.insertIndex(0, at, { name: "x", size: 1 }, opts), 0)
})

const FmPath = loadFm("FmPath.js")
test("FmPath basics", () => {
    assert.equal(FmPath.normalize("/a//b/./c/../d/"), "/a/b/d")
    assert.equal(FmPath.normalize("/../.."), "/")
    assert.equal(FmPath.parent("/a/b"), "/a")
    assert.equal(FmPath.parent("/a"), "/")
    assert.equal(FmPath.parent("/"), "/")
    assert.equal(FmPath.base("/a/b c"), "b c")
    assert.equal(FmPath.join("/", "x"), "/x")
    assert.equal(FmPath.join("/a", "-rf"), "/a/-rf")
    assert.ok(FmPath.under("/home/u/x", "/home/u"))
    assert.ok(!FmPath.under("/home/user2", "/home/u"))
})
test("FmPath.crumbs starts at Home under home", () => {
    assert.deepEqual(JSON.parse(JSON.stringify(FmPath.crumbs("/home/u/a b", "/home/u"))),
                     [{ label: "Home", path: "/home/u", home: true }, { label: "a b", path: "/home/u/a b", home: false }])
    assert.deepEqual(Array.from(FmPath.crumbs("/etc/x", "/home/u"), c => c.path), ["/", "/etc", "/etc/x"])
    assert.deepEqual(Array.from(FmPath.crumbs("/", "/home/u"), c => c.label), ["/"])
})
test("FmPath.fromArg takes paths and file URIs only", () => {
    assert.equal(FmPath.fromArg("/tmp/x/"), "/tmp/x")
    assert.equal(FmPath.fromArg("file:///tmp/a%20b"), "/tmp/a b")
    assert.equal(FmPath.fromArg("file://localhost/tmp"), "/tmp")
    assert.equal(FmPath.fromArg("file://host/tmp"), "")
    assert.equal(FmPath.fromArg("file:///bad%zz"), "")
    assert.equal(FmPath.fromArg("relative"), "")
    assert.equal(FmPath.fromArg("sftp://h/x"), "")
    assert.equal(FmPath.fromArg("/a\0b"), "")
    assert.equal(FmPath.url("/tmp/a b#?"), "file:///tmp/a%20b%23%3F")
})
test("FmPath.validName", () => {
    assert.equal(FmPath.validName("ok.txt"), "")
    for (const n of ["", " ", ".", "..", "a/b", "a\0b"]) assert.notEqual(FmPath.validName(n), "", JSON.stringify(n))
})

const FmIcons = loadFm("FmIcons.js")
test("FmIcons picks by type", () => {
    assert.equal(FmIcons.item({ dir: true }), FmIcons.g.folder)
    assert.equal(FmIcons.item({ type: "image/png" }), FmIcons.g.image)
    assert.equal(FmIcons.item({ type: "application/x-compressed-tar" }), FmIcons.g.archive)
    assert.equal(FmIcons.item({ type: "text/x-python" }), FmIcons.g.code)
    assert.equal(FmIcons.item({ type: "application/octet-stream", exec: true }), FmIcons.g.script)
    assert.equal(FmIcons.item({ type: "inode/symlink", broken: true }), FmIcons.g.link)
    assert.equal(FmIcons.place("downloads"), FmIcons.g.downloads)
    assert.equal(FmIcons.place("whatever"), FmIcons.g.folder)
})

const FmFormat = loadFm("FmFormat.js")
test("FmFormat.when", () => {
    const now = new Date(2026, 10, 3, 15, 0).getTime()
    const s = d => d.getTime() / 1000
    assert.equal(FmFormat.when(s(new Date(2026, 10, 3, 9, 5)), now), "09:05")
    assert.equal(FmFormat.when(s(new Date(2026, 10, 2, 23, 59)), now), "Yesterday 23:59")
    assert.equal(FmFormat.when(s(new Date(2026, 9, 30, 8, 0)), now), "Fri 08:00")
    assert.equal(FmFormat.when(s(new Date(2026, 0, 7)), now), "7 Jan")
    assert.equal(FmFormat.when(s(new Date(2025, 11, 31)), now), "31 Dec 2025")
})
test("FmFormat.typeLabel", () => {
    assert.equal(FmFormat.typeLabel({ dir: true }), "Folder")
    assert.equal(FmFormat.typeLabel({ type: "image/png" }), "PNG image")
    assert.equal(FmFormat.typeLabel({ type: "image/svg+xml" }), "SVG image")
    assert.equal(FmFormat.typeLabel({ type: "text/x-python" }), "Python source")
    assert.equal(FmFormat.typeLabel({ type: "application/pdf" }), "PDF document")
    assert.equal(FmFormat.typeLabel({ type: "application/x-ms-dos-executable" }), "Windows program")
    assert.equal(FmFormat.typeLabel({ type: "application/x-foo-bar" }), "FOO file")
    assert.equal(FmFormat.typeLabel({ type: "" }), "File")
    assert.equal(FmFormat.items(1), "1 item")
    assert.equal(FmFormat.shown("new\nline\t.txt"), "new\u21B5line\uFFFD.txt")
})

// ── the file manager's process may only use these shared singletons (FILES_NOTES: 2.1 point 4).
// Others do work when they're created (VncServer starts wayvnc, GreeterSync writes
// /var/lib, Notifs takes the D-Bus name, …) and would do it a second time in the files process.
const root = join(dirname(fileURLToPath(import.meta.url)), "..")
const fmAllowed = new Set(["Settings", "Properties", "Colors", "Tokens", "Anim", "AppZoom", "Icons", "Panels", "Jobs",
                           "Compositor", "TokenFont", "TokenSpace", "TokenRadius", "TokenIcon", "TokenBorder", "TokenAlpha", "TokenSize"])
function walk(dir) {
    return readdirSync(dir).flatMap(n => {
        const p = join(dir, n)
        return statSync(p).isDirectory() ? walk(p) : /\.(qml|js)$/.test(n) ? [p] : []
    })
}
const noComments = t => t.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:"'\\])\/\/.*$/gm, "$1")
test("the file manager uses only side-effect-free shared services", () => {
    const singletons = readFileSync(join(root, "services", "qmldir"), "utf8").split("\n")
        .map(l => l.match(/^singleton\s+(\w+)/)).filter(Boolean).map(m => m[1])
    const files = walk(join(root, "modules", "files")).concat([join(root, "files.qml")])
    const bad = []
    for (const f of files) {
        const t = noComments(readFileSync(f, "utf8"))
        for (const s of singletons) {
            if (!fmAllowed.has(s) && new RegExp("\\b" + s + "\\s*\\.").test(t)) bad.push(f.slice(root.length + 1) + ": " + s)
        }
        // Compositor: only what doesn't start NiriIpc (focusedOutput does)
        if (/Compositor\s*\.\s*focusedOutput/.test(t)) bad.push(f.slice(root.length + 1) + ": Compositor.focusedOutput")
        // no other app's modules (Mail's pages import ../settings, which pulls in half the shell)
        for (const m of t.matchAll(/^import\s+"(\.\.\/[^"]+)"/gm)) bad.push(f.slice(root.length + 1) + ": import " + m[1])
        if (/\bDropZone\s*\{/.test(t)) bad.push(f.slice(root.length + 1) + ": DropZone (registers the edit IPC target)")
    }
    assert.deepEqual(bad, [])
})
test("the main shell never imports the file manager's modules (reload isolation)", () => {
    const bad = []
    for (const f of walk(join(root, "modules")).concat([join(root, "shell.qml")])) {
        if (f.includes("/modules/files/")) continue
        if (/^import\s+"(?:[^"]*\/)?files(?:\/[^"]*)?"/m.test(readFileSync(f, "utf8"))) bad.push(f.slice(root.length + 1))
    }
    assert.deepEqual(bad, [])
})

const FmSelect = loadFm("FmSelect.js")
test("FmSelect: clicks like Nautilus", () => {
    const names = ["a", "b", "c", "d", "e"], at = i => names[i], n = names.length
    const keys = st => Object.keys(st.sel).sort().join("")
    let st = FmSelect.click({ sel: {}, anchor: "" }, 1, 0, at, n)
    assert.equal(keys(st), "b")
    st = FmSelect.click(st, 3, FmSelect.SHIFT, at, n)             // b…d
    assert.equal(keys(st), "bcd")
    st = FmSelect.click(st, 2, FmSelect.CTRL, at, n)              // toggles c off, anchor c
    assert.equal(keys(st), "bd")
    st = FmSelect.click(st, 4, FmSelect.CTRL | FmSelect.SHIFT, at, n)   // adds c…e
    assert.equal(keys(st), "bcde")
    st = FmSelect.click(st, 0, 0, at, n)
    assert.equal(keys(st), "a")
    st = FmSelect.moveTo(st, 2, true, at, n)                       // Shift+↓↓ from a
    assert.equal(keys(st), "abc")
    st = FmSelect.moveTo(st, 3, false, at, n)
    assert.equal(keys(st), "d")
    assert.equal(Object.keys(FmSelect.all(n, at)).length, 5)
    st = FmSelect.prune({ sel: { a: true, x: true }, anchor: "x" }, { a: true, b: true })
    assert.equal(keys(st), "a")
    assert.equal(st.anchor, "")
})

test("FmSelect: invert, patterns, rubber band", () => {
    const names = ["a.png", "B.PNG", "c.jpg", "IMG_01.jpg", "notes.txt", "x[1].txt"], at = i => names[i], n = names.length
    assert.ok(FmSelect.glob("*.txt").test("new\nline.txt"))
    const keys = sel => Object.keys(sel).sort().join(" ")
    assert.equal(keys(FmSelect.invert({ "a.png": true }, n, at)), "B.PNG IMG_01.jpg c.jpg notes.txt x[1].txt")
    assert.equal(keys(FmSelect.matching(n, at, FmSelect.glob("*.png"))), "B.PNG a.png")
    assert.equal(keys(FmSelect.matching(n, at, FmSelect.glob("*.{png,jpg}"))), "B.PNG IMG_01.jpg a.png c.jpg")
    assert.equal(keys(FmSelect.matching(n, at, FmSelect.glob("IMG_??.jpg; *.txt"))), "IMG_01.jpg notes.txt x[1].txt")
    assert.equal(keys(FmSelect.matching(n, at, FmSelect.glob("[ab]*"))), "B.PNG a.png")
    assert.equal(keys(FmSelect.matching(n, at, FmSelect.glob("[!ab]*.jpg"))), "IMG_01.jpg c.jpg")
    assert.equal(keys(FmSelect.matching(n, at, FmSelect.glob("x[1].txt"))), "")      // a class, like the shell
    assert.equal(keys(FmSelect.matching(n, at, FmSelect.glob("x[[]1].txt"))), "x[1].txt")
    assert.equal(keys(FmSelect.matching(n, at, FmSelect.glob("a.png("))), "")         // regex characters are literal
    assert.equal(FmSelect.glob("  ; "), null)
    same(FmSelect.band({ x1: 0, y1: 25, x2: 10, y2: 75 }, { rowH: 30 }, 10), [0, 1, 2])
    same(FmSelect.band({ x1: 0, y1: 290, x2: 10, y2: 400 }, { rowH: 30 }, 10), [9])
    same(FmSelect.band({ x1: 150, y1: 10, x2: 50, y2: 110 }, { cellW: 100, cellH: 100, cols: 3 }, 5), [0, 1, 3, 4])
    same(FmSelect.band({ x1: 0, y1: -40, x2: 10, y2: -1 }, { rowH: 30 }, 10), [])        // above every row
    same(FmSelect.band({ x1: 0, y1: 0, x2: 10, y2: 10 }, { rowH: 30 }, 0), [])
})

test("FmPath.validName like the backend", () => {
    assert.equal(FmPath.validName("a b.txt", "ext4"), "")
    assert.notEqual(FmPath.validName("  ", "ext4"), "")
    assert.notEqual(FmPath.validName("..", "ext4"), "")
    assert.notEqual(FmPath.validName("a/b", "ext4"), "")
    assert.notEqual(FmPath.validName("é".repeat(128), "ext4"), "")       // 256 bytes
    assert.equal(FmPath.validName("é".repeat(127), "ext4"), "")
    assert.equal(FmPath.validName("a:b", "ext4"), "")
    assert.notEqual(FmPath.validName("a:b", "vfat"), "")
    assert.notEqual(FmPath.validName("end.", "exfat"), "")
    assert.notEqual(FmPath.nameWarning(".x"), "")
    assert.notEqual(FmPath.nameWarning("x "), "")
    assert.equal(FmPath.nameWarning("x"), "")
})

const FmDrop = loadFm("FmDrop.js")
test("FmDrop: drag data, web links, base64", () => {
    const m = FmDrop.mime(["/a b", "/x"], p => p === "/x" ? "" : "file:///a%20b")
    assert.equal(m["text/uri-list"], "file:///a%20b\r\n")
    assert.equal(m["text/plain"], "/a b\n/x")
    assert.equal(m["x-special/gnome-copied-files"], "copy\nfile:///a%20b")
    const l = FmDrop.webLink("https://user@example.com:8080/x?y", "A / page\n")
    assert.equal(l.name, "Saved from web — A page.desktop")
    assert.ok(l.text.includes("URL=https://user@example.com:8080/x?y\n"))
    assert.equal(FmDrop.webLink("https://example.com/\nExec=evil", "").text.split("\n").filter(x => x.startsWith("Exec")).length, 0)
    assert.equal(FmDrop.webLink("https://example.com", "").name, "Saved from web — example.com.desktop")
    assert.equal(FmDrop.b64(new Uint8Array([104, 105])), "aGk=")
    assert.equal(FmDrop.b64(new Uint8Array([1, 2, 3, 255])), Buffer.from([1, 2, 3, 255]).toString("base64"))
    assert.equal(FmDrop.imageType(["text/html", "image/jpeg", "image/png"]), "image/png")
    assert.equal(FmDrop.ext("image/jpeg"), "jpg")
})

const FmViews = loadFm("FmViews.js")
test("FmViews: per-folder memory over the defaults", () => {
    const defs = { view: "list", sort: { by: "name", reverse: false, dirsFirst: true }, iconSize: { list: 20, grid: 64 } }
    let f = {}
    assert.equal(FmViews.resolve(f, "/a", defs).view, "list")
    assert.equal(FmViews.resolve(f, "/a", defs).own, false)
    f = FmViews.remember(f, "/a", { view: "grid" }, 1)
    f = FmViews.remember(f, "/a", { iconSize: { grid: 96 } }, 2)
    const r = FmViews.resolve(f, "/a", defs)
    assert.equal(r.view, "grid")
    assert.equal(r.iconSize.grid, 96)
    assert.equal(r.iconSize.list, 20)                       // not changed there: the default
    assert.equal(r.sort.by, "name")
    assert.equal(r.own, true)
    assert.equal(FmViews.resolve(f, "/b", defs).view, "list")
    assert.equal(FmViews.resolve({ "/a": { view: "tree", sort: { by: "evil", reverse: 1 }, iconSize: { list: -3 } } }, "/a", defs).view, "list")
    same(FmViews.resolve({ "/a": { sort: { by: "evil", reverse: 1 } } }, "/a", defs).sort, defs.sort)
    assert.equal(Object.keys(FmViews.forget(f, "/a")).length, 0)
    let many = {}
    for (let i = 0; i < FmViews.CAP + 5; i++) many = FmViews.remember(many, "/f" + i, { view: "grid" }, i)
    assert.equal(Object.keys(many).length, FmViews.CAP)
    assert.equal(many["/f0"], undefined)                     // the oldest went
    assert.ok(many["/f" + (FmViews.CAP + 4)])
})
test("FmViews.windows reads v1 and v2, drops junk", () => {
    same(FmViews.windows([{ path: "/home/u" }]), [{ tabs: [{ path: "/home/u" }], active: 0 }])
    same(FmViews.windows([{ tabs: [{ path: "/a" }, { path: "rel" }, { path: "/b" }], active: 1, width: 900, height: 600 }]),
                     [{ tabs: [{ path: "/a" }, { path: "/b" }], active: 1, width: 900, height: 600 }])
    same(FmViews.windows([{ tabs: [{ path: "/a" }], active: 7 }]), [{ tabs: [{ path: "/a" }], active: 0 }])
    same(FmViews.windows([{ tabs: [] }, 3, null, { path: 5 }]), [])
    same(FmViews.windows("x"), [])
})

const FmColumns = loadFm("FmColumns.js")
test("FmColumns: chosen, fit, toggle, move, perms", () => {
    same(FmColumns.chosen(undefined), ["size", "mtime", "type"])
    same(FmColumns.chosen(["perms", "nope", "perms", "size"]), ["perms", "size"])
    same(FmColumns.chosen([]), [])
    same(Object.keys(FmColumns.fit(["size", "mtime", "type"], 44 * 20, 44)), ["size", "mtime", "type"])
    same(Object.keys(FmColumns.fit(["size", "mtime", "type"], 44 * 7, 44)), ["size"])
    same(Object.keys(FmColumns.fit(["type", "size"], 44 * 7, 44)), [])           // in order: type doesn't fit, so neither after it
    same(FmColumns.toggle(["size"], "perms"), ["size", "perms"])
    same(FmColumns.toggle(["size", "perms"], "size"), ["perms"])
    same(FmColumns.move(["size", "mtime", "type"], "type", -1), ["size", "type", "mtime"])
    same(FmColumns.move(["size", "mtime"], "size", -1), ["size", "mtime"])
    assert.equal(FmColumns.perms(0o755), "rwxr-xr-x")
    assert.equal(FmColumns.perms(0o4755), "rwsr-xr-x")
    assert.equal(FmColumns.perms(0o1777), "rwxrwxrwt")
    assert.equal(FmColumns.perms(0o2640), "rw-r-S---")
})

const FmAddress = loadFm("FmAddress.js")
test("FmAddress: saved servers for what's typed", () => {
    const sv = [{ uri: "smb://server01/public", name: "public on server01" }, { uri: "sftp://server01-lab", name: "lab" }, { uri: "smb://nas/media", name: "media" }]
    const of = t => [...FmAddress.serverOffers(t, sv)].map(o => o.server.uri + (o.continues ? " !" : ""))
    // a typed scheme stays: ssh:// never turns into the saved smb:// of that host
    assert.deepEqual(of("ssh://server01"), ["sftp://server01-lab !"])
    assert.deepEqual(of("ftp://server01"), [])
    // a whole host: the saved share is offered, not gone to by itself
    assert.deepEqual(of("smb://server01"), ["smb://server01/public"])
    assert.deepEqual(of("smb://ser"), ["smb://server01/public !"])
    assert.deepEqual(of("smb://med"), ["smb://nas/media"])
    assert.deepEqual(of("smb://"), ["smb://server01/public", "smb://nas/media"])
    // no scheme: a search by name / address
    assert.deepEqual(of("server01"), ["smb://server01/public !", "sftp://server01-lab !"])
    assert.deepEqual(of("s"), []); assert.deepEqual(of("ssh://x"), [])
    assert.equal(FmAddress.hasExact(["Doc", "Documents"], "Doc"), true)
    assert.equal(FmAddress.hasExact(["Documents"], "Doc"), false); assert.equal(FmAddress.hasExact(["a"], ""), false)
})
test("FmAddress: typed text to a path", () => {
    assert.equal(FmAddress.resolve("/usr//lib/", "/x", "/home/u"), "/usr/lib")
    assert.equal(FmAddress.resolve("~", "/x", "/home/u"), "/home/u")
    assert.equal(FmAddress.resolve("~/Doc ", "/x", "/home/u"), "/home/u/Doc")
    assert.equal(FmAddress.resolve("sub/../b", "/x", "/home/u"), "/x/b")
    assert.equal(FmAddress.resolve("..", "/", "/home/u"), "/")
    assert.equal(FmAddress.resolve("~user", "/x", "/home/u"), "/x/~user")     // not someone else's home
    assert.equal(FmAddress.resolve("file:///a%20b/c", "/x", "/home/u"), "/a b/c")
    assert.equal(FmAddress.resolve("file://host/a", "/x", "/home/u"), "")
    assert.equal(FmAddress.resolve("sftp://host/a", "/x", "/home/u"), "")
    assert.equal(FmAddress.resolve("file:///a%00b", "/x", "/home/u"), "")
    assert.equal(FmAddress.resolve("   ", "/x", "/home/u"), "")
})
test("FmAddress: mounted servers", () => {
    const g = "/run/user/1000/gvfs/"
    const mounts = [{ uri: "smb://srv/share/", path: g + "smb-share:server=srv,share=share" },
                    { uri: "sftp://u@box/", path: g + "sftp:host=box,user=u" },
                    { uri: "file:///mnt/usb", path: "/mnt/usb" }, null, { uri: 3 }]
    assert.equal(FmAddress.toServer(g + "smb-share:server=srv,share=share/My Dir", mounts), "smb://srv/share/My Dir")
    assert.equal(FmAddress.toServer(g + "sftp:host=box,user=u", mounts), "sftp://u@box")
    assert.equal(FmAddress.toServer("/mnt/usb/a", mounts), "")
    assert.equal(FmAddress.toServer(g + "smb-share:server=srv,share=shareX", mounts), "")
    assert.equal(FmAddress.fromServer("smb://srv/share/My%20Dir/", mounts), g + "smb-share:server=srv,share=share/My Dir")
    assert.equal(FmAddress.fromServer("SMB://srv/share", mounts), g + "smb-share:server=srv,share=share")
    assert.equal(FmAddress.fromServer("smb://srv/other", mounts), "")
    assert.equal(FmAddress.fromServer("smb://srv/share/../x", mounts), "")
    assert.equal(FmAddress.encodeUri("smb://srv/share/My Dir"), "smb://srv/share/My%20Dir")
    assert.equal(FmAddress.encodeUri("smb://srv/share/My%20Dir"), "smb://srv/share/My%20Dir")
    assert.equal(FmAddress.encodeUri("sftp://u@box:22"), "sftp://u@box:22")
})
test("FmAddress: completion", () => {
    same(FmAddress.split("~/Doc"), { dir: "~/", part: "Doc" })
    same(FmAddress.split("Doc"), { dir: "", part: "Doc" })
    same(FmAddress.split("/a/"), { dir: "/a/", part: "" })
    const names = ["Documents", "docs", ".config", "My Docs", "Downloads", "Desktop"]
    same(FmAddress.matches(names, "doc"), ["Documents", "docs", "My Docs"])
    same(FmAddress.matches(names, ""), ["Documents", "docs", "My Docs", "Downloads", "Desktop"])
    same(FmAddress.matches(names, ".c"), [".config"])
    same(FmAddress.matches(names, "docs"), ["My Docs"])          // the exact one is typed already
    assert.equal(FmAddress.common(["Documents", "docs"]), "Doc")
    assert.equal(FmAddress.common(["Downloads"]), "Downloads")
    assert.equal(FmAddress.common([]), "")
})

test("FmAddress: an address for another user", () => {
    assert.equal(FmAddress.withUser("smb://nas/share", "anna", "CORP"), "smb://CORP;anna@nas/share")
    assert.equal(FmAddress.withUser("smb://old@nas/share/dir", "anna", ""), "smb://anna@nas/share/dir")
    assert.equal(FmAddress.withUser("sftp://root@host:2222/srv", "me", "CORP"), "sftp://me@host:2222/srv")    // a domain is smb's
    assert.equal(FmAddress.withUser("smb://CORP;old@nas/share", "", ""), "smb://nas/share")
    assert.equal(FmAddress.withUser("smb://nas", "a b@x", "D;1"), "smb://D%3B1;a%20b%40x@nas")
    assert.equal(FmAddress.withUser("not an address", "x", ""), "not an address")
    assert.equal(JSON.stringify(FmAddress.userOf("smb://CORP;anna@nas/share")), JSON.stringify({ user: "anna", domain: "CORP" }))
    assert.equal(JSON.stringify(FmAddress.userOf("sftp://me:pw@host/x@y")), JSON.stringify({ user: "me", domain: "" }))
    assert.equal(JSON.stringify(FmAddress.userOf("smb://nas/a@b")), JSON.stringify({ user: "", domain: "" }))
    assert.equal(JSON.stringify(FmAddress.userOf(FmAddress.withUser("smb://nas", "a b@x", "D;1"))), JSON.stringify({ user: "a b@x", domain: "D;1" }))
})

const FmChooser = loadFm("FmChooser.js")
test("FmChooser: what a file dialog's filter shows", () => {
    const img = { name: "Images", globs: ["*.png", "*.[jJ][pP][gG]"], mimes: ["image/webp"] }
    const yes = n => FmChooser.accepts(img, { name: n, type: "", dir: false })
    assert.ok(yes("a.png") && yes("A.PNG") && yes("b.jpg") && yes("new\nline.png"))
    assert.ok(!yes("a.png.txt") && !yes("png") && !yes("a.gif"))
    assert.ok(FmChooser.accepts(img, { name: "x", type: "image/webp", dir: false }))
    assert.ok(FmChooser.accepts(img, { name: "notes", type: "inode/directory", dir: true }))      // folders always
    assert.ok(FmChooser.accepts({ name: "Pictures", globs: [], mimes: ["image/*"] }, { name: "x", type: "image/x-foo", dir: false }))
    assert.ok(!FmChooser.accepts({ name: "Pictures", globs: [], mimes: ["image/*"] }, { name: "x", type: "text/plain", dir: false }))
    // nothing to filter by: everything shows (no function to run per row)
    assert.equal(FmChooser.matcher({ name: "All", globs: ["*"], mimes: [] }), null)
    assert.equal(FmChooser.matcher({ name: "All", globs: ["*.png", "*"], mimes: [] }), null)
    assert.equal(FmChooser.matcher({ name: "x", globs: [], mimes: [] }), null)
    assert.equal(FmChooser.matcher(null), null)
    // regex characters in a glob are literal; a broken class too
    assert.ok(FmChooser.accepts({ globs: ["a+(1).txt"], mimes: [] }, { name: "a+(1).txt", dir: false }))
    assert.ok(!FmChooser.accepts({ globs: ["a+(1).txt"], mimes: [] }, { name: "aa(1).txt", dir: false }))
    assert.ok(FmChooser.accepts({ globs: ["x[1.txt"], mimes: [] }, { name: "x[1.txt", dir: false }))
    assert.ok(FmChooser.accepts({ globs: ["[!a]?.c"], mimes: [] }, { name: "bx.c", dir: false }))
    assert.ok(!FmChooser.accepts({ globs: ["[!a]?.c"], mimes: [] }, { name: "ax.c", dir: false }))
})
test("FmChooser: labels, titles, typed names", () => {
    assert.equal(FmChooser.label({ name: "Images", globs: ["*.png", "*.jpg"] }), "Images (*.png, *.jpg)")
    assert.equal(FmChooser.label({ name: "Text (*.txt)", globs: ["*.txt"] }), "Text (*.txt)")
    assert.equal(FmChooser.label({ name: "All files", globs: ["*"] }), "All files")
    assert.equal(FmChooser.label({ name: "", globs: [] }), "All files")
    assert.equal(FmChooser.label({ name: "Many", globs: ["*.a", "*.b", "*.c", "*.d", "*.e"] }), "Many (*.a, *.b, *.c, *.d, …)")
    assert.equal(FmChooser.verb({ mode: "open", accept: "" }), "Open")
    assert.equal(FmChooser.verb({ mode: "save", accept: "" }), "Save")
    assert.equal(FmChooser.verb({ mode: "folder", accept: " " }), "Select")
    assert.equal(FmChooser.verb({ mode: "open", accept: "Upload" }), "Upload")
    assert.equal(FmChooser.title({ mode: "open", multiple: true, title: "" }, "Files dialog — "), "Files dialog — Open files")
    assert.equal(FmChooser.title({ mode: "save", title: "Save As" }, "Files dialog — "), "Files dialog — Save As")
    // the dialogs' rule must not be the file manager's own (tiled) one
    assert.ok(!FmSettings.dialogPrefix.startsWith(FmSettings.titlePrefix) && !FmSettings.titlePrefix.startsWith(FmSettings.dialogPrefix))
    assert.equal(FmChooser.cleanName("  report.pdf "), "report.pdf")
    for (const bad of ["", " ", ".", "..", "a/b", "/etc/passwd", "a\0b"]) assert.equal(FmChooser.cleanName(bad), "")
})

console.log(passed + " passed, " + failed + " failed")
process.exit(failed ? 1 : 0)
