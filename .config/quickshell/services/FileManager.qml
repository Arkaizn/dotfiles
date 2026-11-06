pragma Singleton

import Quickshell
import QtQuick

// "Open folder" / "Show in folder" from anywhere in the shell: the file manager
// (its own process, started by scripts/files/files.sh if it isn't running) —
// or the desktop's default app for folders when it can't start (files.sh exits 1).
//   FileManager.open(folder)     the folder (a tab or a window: Settings.files.openFrom)
//   FileManager.select(path)     its folder, with it selected
Singleton {
    id: root

    readonly property string script: Quickshell.shellDir + "/scripts/files/files.sh"

    function open(dir) {
        if (typeof dir !== "string" || !dir.startsWith("/")) return
        Jobs.run([script, dir], code => { if (code !== 0) Jobs.detached(["xdg-open", dir]) })
    }
    function select(path) {
        if (typeof path !== "string" || !path.startsWith("/")) return
        Jobs.run([script, "--select", path], code => {
            if (code !== 0) Jobs.detached(["xdg-open", path.replace(/\/[^/]*$/, "") || "/"])
        })
    }
}
