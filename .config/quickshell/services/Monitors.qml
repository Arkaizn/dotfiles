pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services

// Monitor setup for the settings app (modules/settings/MonitorsPage.qml).
//
// niri: scans the outputs with `niri msg --json outputs`, applies changes live
// with `niri msg output …` (temporary, so they can be reverted), and once kept
// saves them in settings.json (Settings.monitors) and writes them to
//   ~/.config/niri/config/quickshell-outputs.kdl
// niri uses the FIRST `output` block that matches a monitor, so config.kdl
// includes that file *before* output.kdl: monitors set here win, and the ones
// never touched here still use output.kdl.
//
// Hyprland: scans with `hyprctl -j monitors all`, applies live with
// `hyprctl eval 'hl.monitor({…})'` (undone by the next reload), and writes
//   ~/.config/hypr/quickshell-monitors.lua
// which the settings override file (HyprSettings) loads last: Hyprland uses
// the LAST matching monitor rule, so these win over monitors.lua too.
//
// Monitors are saved by "make model serial", so they keep their settings when
// plugged into another port, and the same saved setup works for both.
Singleton {
    id: root

    readonly property string outputsPath: NiriSettings.configDir + "/config/quickshell-outputs.kdl"
    readonly property string includeLine: Compositor.isHyprland ? HyprSettings.includeLine
                                                                : Syntax.fmt("niri.include", { path: Syntax.kdlString("./config/quickshell-outputs.kdl") })
    readonly property var transforms: ["normal", "90", "180", "270", "flipped", "flipped-90", "flipped-180", "flipped-270"]

    // live state from niri, one object per output:
    //   { name, ident, make, model, serial, modes, enabled, width, height, refresh,
    //     scale, transform, x, y, vrrSupported, vrr, physical }
    property var outputs: []
    property bool included: false
    property string error: ""
    property bool busy: false

    function ident(o) {
        return [o.make || "Unknown", o.model || "Unknown", o.serial || "Unknown"].join(" ")
    }

    function modeString(w, h, refresh) {
        return w + "x" + h + "@" + (refresh / 1000).toFixed(3)
    }

    // niri's IPC says "Normal", "_90", "Flipped90"…; config + CLI want "normal", "90", "flipped-90"
    function transformName(t) {
        const s = String(t ?? "normal").toLowerCase().replace("_", "")
        return s.startsWith("flipped") && s.length > 7 ? "flipped-" + s.slice(7) : s
    }

    // logical size: mode / scale, swapped when rotated
    function logicalSize(c) {
        let w = c.width / c.scale, h = c.height / c.scale
        if (/90|270/.test(c.transform)) [w, h] = [h, w]
        return { w: Math.round(w), h: Math.round(h) }
    }

    function refresh() {
        if (Compositor.isHyprland) {
            HyprSettings.refresh()
            root.included = HyprSettings.included     // the override file loads the monitor file
            hyprScanProc.running = true
            return
        }
        scanProc.running = true
        root.included = Files.read(NiriSettings.mainConfig).split("\n").some(l => l.trim() === root.includeLine)
    }

    // Hyprland: modes are "2560x1440@359.98Hz" (the first is the preferred one),
    // transform is 0–7 → the same objects niri gives
    Process {
        id: hyprScanProc
        command: ["hyprctl", "-j", "monitors", "all"]
        stdout: StdioCollector {
            onStreamFinished: {
                let data
                try { data = JSON.parse(text) } catch (e) { root.error = "Couldn't read the monitors from Hyprland"; return }
                const list = data.map(o => {
                    const modes = (o.availableModes ?? []).map((m, i) => {
                        const r = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(m)
                        return r ? { width: +r[1], height: +r[2], refresh_rate: Math.round(parseFloat(r[3]) * 1000), is_preferred: i === 0 } : null
                    }).filter(m => m !== null)
                    const saved = Settings.monitors[root.ident(o)]
                    const live = o.disabled ? null : root.nearestMode(modes, o.width, o.height, o.refreshRate * 1000)
                    const fallback = live ?? (saved ? root.parseMode(saved.mode, modes) : null) ?? modes[0]
                        ?? { width: o.width, height: o.height, refresh_rate: Math.round(o.refreshRate * 1000) }
                    return {
                        name: o.name,
                        ident: root.ident(o),
                        make: o.make ?? "",
                        model: o.model ?? "",
                        serial: o.serial ?? "",
                        modes: modes,
                        physical: [o.physicalWidth ?? 0, o.physicalHeight ?? 0],
                        enabled: !o.disabled,
                        width: fallback.width,
                        height: fallback.height,
                        refresh: fallback.refresh_rate,
                        scale: o.disabled ? (saved?.scale ?? 1) : o.scale,
                        transform: o.disabled ? (saved?.transform ?? "normal") : (root.transforms[o.transform] ?? "normal"),
                        x: o.disabled ? (saved?.x ?? 0) : o.x,
                        y: o.disabled ? (saved?.y ?? 0) : o.y,
                        vrrSupported: true,
                        vrr: !!o.vrr
                    }
                })
                list.sort((a, b) => a.x - b.x || a.y - b.y || a.name.localeCompare(b.name))
                root.outputs = list
            }
        }
    }

    function nearestMode(modes, w, h, refresh) {
        const same = modes.filter(x => x.width === w && x.height === h)
        if (same.length === 0) return null
        return same.reduce((a, b) => Math.abs(b.refresh_rate - refresh) < Math.abs(a.refresh_rate - refresh) ? b : a)
    }

    Process {
        id: scanProc
        command: ["niri", "msg", "--json", "outputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                let data
                try { data = JSON.parse(text) } catch (e) { root.error = "Couldn't read the monitors from niri"; return }
                const list = Object.values(data).map(o => {
                    const m = o.current_mode !== null && o.current_mode !== undefined ? o.modes[o.current_mode] : null
                    const saved = Settings.monitors[root.ident(o)]
                    // turned-off outputs have no mode/position: use the saved or preferred ones
                    const pref = o.modes.find(x => x.is_preferred) ?? o.modes[0]
                    const fallback = m ?? (saved ? root.parseMode(saved.mode, o.modes) : null) ?? pref
                    return {
                        name: o.name,
                        ident: root.ident(o),
                        make: o.make ?? "",
                        model: o.model ?? "",
                        serial: o.serial ?? "",
                        modes: o.modes,
                        physical: o.physical_size,
                        enabled: o.logical !== null && o.logical !== undefined,
                        width: fallback.width,
                        height: fallback.height,
                        refresh: fallback.refresh_rate,
                        scale: o.logical?.scale ?? saved?.scale ?? 1,
                        transform: root.transformName(o.logical?.transform ?? saved?.transform),
                        x: o.logical?.x ?? saved?.x ?? 0,
                        y: o.logical?.y ?? saved?.y ?? 0,
                        vrrSupported: o.vrr_supported,
                        vrr: o.vrr_enabled
                    }
                })
                list.sort((a, b) => a.x - b.x || a.y - b.y || a.name.localeCompare(b.name))
                root.outputs = list
            }
        }
    }

    function parseMode(s, modes) {
        const m = /^(\d+)x(\d+)(?:@([\d.]+))?$/.exec(s ?? "")
        if (!m) return null
        const w = +m[1], h = +m[2], r = m[3] ? Math.round(parseFloat(m[3]) * 1000) : 0
        const same = modes.filter(x => x.width === w && x.height === h)
        if (same.length === 0) return null
        return r ? same.reduce((a, b) => Math.abs(b.refresh_rate - r) < Math.abs(a.refresh_rate - r) ? b : a) : same[0]
    }

    // ── Live changes (temporary until saved) ─────────────────────────────────
    // cfgs: output objects like in `outputs`
    function applyLive(cfgs) {
        if (Compositor.isHyprland) {
            // on first, then off — so the layout is never empty
            const calls = cfgs.filter(c => c.enabled).map(c => hyprMonitorCall(c, Compositor.luaString(c.name)))
                .concat(cfgs.filter(c => !c.enabled).map(c => hyprMonitorCall(c, Compositor.luaString(c.name))))
            root.busy = true
            liveProc.command = ["hyprctl", "eval", "(function() " + calls.join("; ") + " end)()"]
            liveProc.running = true
            return
        }
        const cmds = []
        const q = s => "'" + String(s).replace(/'/g, "'\\''") + "'"
        // on first, then modes, then positions, then off — so the layout is never empty
        for (const c of cfgs) if (c.enabled) cmds.push("niri msg output " + q(c.name) + " on")
        for (const c of cfgs) {
            if (!c.enabled) continue
            const o = q(c.name)
            cmds.push("niri msg output " + o + " mode " + modeString(c.width, c.height, c.refresh))
            cmds.push("niri msg output " + o + " scale " + c.scale)
            cmds.push("niri msg output " + o + " transform " + c.transform)
            if (c.vrrSupported) cmds.push("niri msg output " + o + " vrr " + (c.vrr ? "on" : "off"))
        }
        for (const c of cfgs) if (c.enabled) cmds.push("niri msg output " + q(c.name) + " position set " + Math.round(c.x) + " " + Math.round(c.y))
        for (const c of cfgs) if (!c.enabled) cmds.push("niri msg output " + q(c.name) + " off")
        root.busy = true
        liveProc.command = ["sh", "-c", cmds.join("\n")]
        liveProc.running = true
    }

    Process {
        id: liveProc
        stderr: StdioCollector { id: liveErr }
        onExited: code => {
            root.busy = false
            root.error = code === 0 ? "" : (liveErr.text.trim() || Compositor.name + " couldn't apply the change")
            root.refresh()
        }
    }

    // ── Try → keep / revert ──────────────────────────────────────────────────
    // Like other desktops: apply live, then revert by itself unless kept, in
    // case the new mode leaves a screen black. Lives here (not in the page) so
    // it still reverts when the settings window is closed.
    property var before: null          // live state before trying
    property var trying: null          // what's being tried
    property int countdown: 0
    readonly property bool pending: before !== null

    function tryLive(cfgs) {
        root.before = JSON.parse(JSON.stringify(root.outputs))
        root.trying = JSON.parse(JSON.stringify(cfgs))
        applyLive(cfgs)
        root.countdown = 15
        confirmTimer.restart()
    }

    function keep() {
        confirmTimer.stop()
        save(root.trying)
        root.before = null
        root.trying = null
    }

    function revert() {
        confirmTimer.stop()
        if (root.before) applyLive(root.before)
        root.before = null
        root.trying = null
    }

    Timer {
        id: confirmTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown--
            if (root.countdown <= 0) root.revert()
        }
    }

    // ── Saving ───────────────────────────────────────────────────────────────
    function save(cfgs) {
        const m = Object.assign({}, Settings.monitors)
        for (const c of cfgs) {
            m[c.ident] = {
                name: c.name,
                enabled: c.enabled,
                mode: modeString(c.width, c.height, c.refresh),
                scale: c.scale,
                transform: c.transform,
                x: Math.round(c.x),
                y: Math.round(c.y),
                vrr: c.vrr
            }
        }
        Settings.setGroup("monitors", m)
        write()
    }

    // drop everything saved here: monitors go back to output.kdl / niri's defaults
    function forget() {
        Settings.resetGroup("monitors")
        write()
    }

    // hl.monitor({…}) for one output; `output` is a Lua string
    function hyprMonitorCall(c, output) {
        if (!c.enabled) return Syntax.fmt("hypr.monitorOff", { output: output })
        const mode = typeof c.mode === "string" ? c.mode : modeString(c.width, c.height, c.refresh)
        return Syntax.fmt("hypr.monitor", {
            output: output,
            mode: Compositor.luaString(mode),
            position: Compositor.luaString(Math.round(c.x) + "x" + Math.round(c.y)),
            scale: String(Number(Number(c.scale).toFixed(3))),
            transform: String(Math.max(0, transforms.indexOf(c.transform))),
            vrr: c.vrr ? "1" : "0"
        })
    }

    // Hyprland matches "desc:" by the start of "make model serial"
    function hyprDesc(id) {
        return id.split(" ").filter(w => w !== "Unknown").join(" ")
    }

    function generateHypr() {
        let t = "-- Generated by the Quickshell settings app (Monitors page) — edits here get\n"
              + "-- overwritten. Loaded by quickshell.lua, after monitors.lua: Hyprland uses\n"
              + "-- the last monitor rule that matches, so these win over monitors.lua.\n"
        const m = Settings.monitors
        for (const id of Object.keys(m).sort()) {
            t += "\n-- " + (m[id].name ?? "") + "\n"
            t += hyprMonitorCall(m[id], Compositor.luaString("desc:" + hyprDesc(id))) + "\n"
        }
        return t
    }

    function generate() {
        let t = "// Generated by the Quickshell settings app (Monitors page) — edits here get\n"
              + "// overwritten. Included BEFORE output.kdl in config.kdl: niri uses the first\n"
              + "// output block that matches, so these win over output.kdl.\n"
        const m = Settings.monitors
        for (const id of Object.keys(m).sort()) {
            const c = m[id]
            const lines = []
            if (!c.enabled) lines.push(Syntax.fmt("niri.outputOff", {}))
            lines.push(Syntax.fmt("niri.outputMode", { mode: Syntax.kdlString(c.mode) }))
            lines.push(Syntax.fmt("niri.outputScale", { scale: String(Number(Number(c.scale).toFixed(3))) }))
            lines.push(Syntax.fmt("niri.outputTransform", { transform: Syntax.kdlString(c.transform) }))
            lines.push(Syntax.fmt("niri.outputPosition", { x: String(c.x), y: String(c.y) }))
            if (c.vrr) lines.push(Syntax.fmt("niri.outputVrr", {}))
            t += "\n// " + (c.name ?? "") + "\n"
            t += Syntax.fmt("niri.output", { name: Syntax.kdlString(id), body: lines.map(l => "    " + l + "\n").join("") }) + "\n"
        }
        return t
    }

    // writes the file of every compositor that's set up here, so switching
    // between them keeps the same monitor setup
    function write() {
        if (Files.read(NiriSettings.mainConfig) !== "") {
            writeProc.command = ["sh", "-c", NiriSettings.installScript, "sh", generate(), root.outputsPath]
            writeProc.running = true
        }
        if (HyprSettings.available) {
            hyprWriteProc.command = ["sh", "-c", HyprSettings.installScript, "sh", generateHypr(), HyprSettings.monitorsPath]
            hyprWriteProc.running = true
        }
        root.busy = writeProc.running || hyprWriteProc.running
    }

    Process {
        id: writeProc
        stderr: StdioCollector { id: writeErr }
        onExited: code => {
            root.busy = hyprWriteProc.running
            if (!Compositor.isHyprland) root.error = code === 0 ? "" : (writeErr.text.trim() || "niri validate failed")
            root.refresh()
        }
    }

    Process {
        id: hyprWriteProc
        stderr: StdioCollector { id: hyprWriteErr }
        onExited: code => {
            root.busy = writeProc.running
            if (Compositor.isHyprland) root.error = code === 0 ? "" : (hyprWriteErr.text.trim() || "Hyprland --verify-config failed")
            root.refresh()
        }
    }
}
