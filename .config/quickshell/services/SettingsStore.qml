pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import qs.services.lib

// Writes settings.json for the file manager's process (files.qml). That
// process reads the file like everyone else, but two processes rewriting the
// whole file would lose each other's changes, so its Settings runs in
// "remote" mode and hands every change to this target. Only the file
// manager's own keys are taken (FmSettings.checkRemote: Settings.files, its
// zoom, its icons), each checked before it's written.
//
//   qs ipc call settingsStore set <group> <key> <json value>
//   qs ipc call settingsStore reset <group> <key>
//   qs ipc call settingsStore apply '{ "<group>": { "set": { k: v }, "reset": [k] } }'
// Each returns "ok" or what was refused (nothing of a refused batch is written).
// Touched by ShellRest.qml, so the target is there from the start.
Singleton {
    id: root

    // the batch, checked; "" or the first problem
    function _check(batch) {
        if (batch === null || typeof batch !== "object" || Array.isArray(batch)) return "expected { group: { set, reset } }"
        for (const g of Object.keys(batch)) {
            const b = batch[g]
            if (b === null || typeof b !== "object" || Array.isArray(b)) return g + ": expected { set, reset }"
            for (const k of Object.keys(b)) if (k !== "set" && k !== "reset") return g + ": unknown part \"" + k + "\""
            const sets = b.set ?? {}
            if (sets === null || typeof sets !== "object" || Array.isArray(sets)) return g + ".set: expected an object"
            for (const k of Object.keys(sets)) {
                const m = FmSettings.checkRemote(g, k, sets[k], AppZoom.options)
                if (m !== "") return g + "." + k + ": " + m
            }
            const resets = b.reset ?? []
            if (!Array.isArray(resets)) return g + ".reset: expected a list"
            for (const k of resets) {
                const m = FmSettings.checkRemote(g, k, undefined, AppZoom.options)
                if (m !== "") return g + "." + k + ": " + m
            }
        }
        return ""
    }

    function apply(batch) {
        const m = _check(batch)
        if (m !== "") { console.warn("settingsStore: refused:", m); return m }
        for (const g of Object.keys(batch)) {
            const sets = batch[g].set ?? {}
            for (const k of Object.keys(sets)) Settings.set(g, k, sets[k])
            for (const k of batch[g].reset ?? []) Settings.reset(g, k)
        }
        return "ok"
    }

    IpcHandler {
        target: "settingsStore"
        function set(group: string, key: string, json: string): string {
            let v
            try { v = JSON.parse(json) } catch (e) { return "the value isn't JSON" }
            return root.apply({ [group]: { set: { [key]: v } } })
        }
        function reset(group: string, key: string): string { return root.apply({ [group]: { reset: [key] } }) }
        function apply(json: string): string {
            if (json.length > 65536) return "too big"
            let b
            try { b = JSON.parse(json) } catch (e) { return "not JSON" }
            return root.apply(b)
        }
    }
}
