// Unit tests for services/lib/*.js (plain `.pragma library` files).
// Run: node tests/lib.test.mjs
import { readFileSync } from "node:fs"
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
    assert.equal(LI.checkGreeter("userPicker", "on"), ""); assert.notEqual(LI.checkGreeter("userPicker", "x"), "")
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

console.log(passed + " passed, " + failed + " failed")
process.exit(failed ? 1 : 0)
