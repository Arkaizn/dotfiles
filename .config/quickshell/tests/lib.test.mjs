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

console.log(passed + " passed, " + failed + " failed")
process.exit(failed ? 1 : 0)
