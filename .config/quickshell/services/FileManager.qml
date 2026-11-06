pragma Singleton

import Quickshell
import QtQuick

// "Open folder" / "Show in folder" from anywhere in the shell: the file manager
// (its own process, started by scripts/files/files.sh if it isn't running) —
// or the desktop's default app for folders when it can't start (files.sh exits 1).
//   FileManager.open(folder)     the folder (a tab or a window: Settings.files.openFrom)
//   FileManager.select(path)     its folder, with it selected
//   FileManager.call(fn, args, cb)   one of its IPC functions (it's started first, without a window):
//                                cb(answer) — "notready" answers are asked again for a few seconds;
//                                cb("", error) when it couldn't be reached
Singleton {
    id: root

    readonly property string script: Quickshell.shellDir + "/scripts/files/files.sh"

    function open(dir) {
        if (typeof dir !== "string" || !dir.startsWith("/")) return
        Jobs.run([script, dir], code => { if (code !== 0) Jobs.detached(["xdg-open", dir]) })
    }
    function call(fn, args, cb, tries) {
        Jobs.run([script, "--start"], code => {
            if (code !== 0) { cb("", "The file manager didn't start (qs log -p " + Quickshell.shellDir + "/files.qml)"); return }
            Jobs.run(["qs", "ipc", "-p", Quickshell.shellDir + "/files.qml", "call", "files", fn].concat(args), (c, out, err) => {
                // (the answer is the last line: a locale warning can come first)
                const r = String(out ?? "").trim().split("\n").pop()
                if (c !== 0) { cb("", String(err ?? "").trim() || "The file manager didn't answer"); return }
                // just started: its sidebar (bookmarks) is read a moment later
                if (r === "notready" && (tries ?? 0) < 20) { Jobs.later(250, () => root.call(fn, args, cb, (tries ?? 0) + 1)); return }
                cb(r === "notready" ? "" : r, r === "notready" ? "The file manager isn't ready — try again" : "")
            }, { LC_ALL: "C.UTF-8" })
        })
    }
    function select(path) {
        if (typeof path !== "string" || !path.startsWith("/")) return
        Jobs.run([script, "--select", path], code => {
            if (code !== 0) Jobs.detached(["xdg-open", path.replace(/\/[^/]*$/, "") || "/"])
        })
    }
}
