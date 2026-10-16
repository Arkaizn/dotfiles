pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services

// Monitor setup for the settings app (modules/settings/MonitorsPage.qml).
//
// Scans the outputs with `niri msg --json outputs`, applies changes live with
// `niri msg output …` (temporary, so they can be reverted), and once kept saves
// them in settings.json (Settings.monitors) and writes them to
//   ~/.config/niri/config/quickshell-outputs.kdl
// niri uses the FIRST `output` block that matches a monitor, so config.kdl
// includes that file *before* output.kdl: monitors set here win, and the ones
// never touched here still use output.kdl.
//
// Monitors are saved by "make model serial", so they keep their settings when
// plugged into another port.
Singleton {
    id: root

    readonly property string outputsPath: NiriSettings.configDir + "/config/quickshell-outputs.kdl"
    readonly property string includeLine: 'include "./config/quickshell-outputs.kdl"'

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
        scanProc.running = true
        root.included = NiriSettings.readFile(NiriSettings.mainConfig).split("\n").some(l => l.trim() === root.includeLine)
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
            root.error = code === 0 ? "" : (liveErr.text.trim() || "niri couldn't apply the change")
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

    function generate() {
        let t = "// Generated by the Quickshell settings app (Monitors page) — edits here get\n"
              + "// overwritten. Included BEFORE output.kdl in config.kdl: niri uses the first\n"
              + "// output block that matches, so these win over output.kdl.\n"
        const m = Settings.monitors
        for (const id of Object.keys(m).sort()) {
            const c = m[id]
            t += "\n// " + (c.name ?? "") + "\n"
            t += "output " + JSON.stringify(id) + " {\n"
            if (!c.enabled) t += "    off\n"
            t += "    mode " + JSON.stringify(c.mode) + "\n"
            t += "    scale " + Number(Number(c.scale).toFixed(3)) + "\n"
            t += "    transform " + JSON.stringify(c.transform) + "\n"
            t += "    position x=" + c.x + " y=" + c.y + "\n"
            if (c.vrr) t += "    variable-refresh-rate\n"
            t += "}\n"
        }
        return t
    }

    function write() {
        root.busy = true
        writeProc.command = ["sh", "-c", NiriSettings.installScript, "sh", generate(), root.outputsPath]
        writeProc.running = true
    }

    Process {
        id: writeProc
        stderr: StdioCollector { id: writeErr }
        onExited: code => {
            root.busy = false
            root.error = code === 0 ? "" : (writeErr.text.trim() || "niri validate failed")
            root.refresh()
        }
    }
}
