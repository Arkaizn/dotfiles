pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Single shared update checker. checkupdates locks a shared temp db, so
// running one instance per bar makes all but one fail (and report 0).
//
// Settings.updates: { interval (minutes, 0 = only by hand; default 30),
//                     aur (also yay -Qua; default true), notify (new updates → notification) }
// The settings app (Maintenance → Updates) shows the lists, Arch news, .pacnew
// files and whether a reboot is due.
Singleton {
    id: root

    readonly property var cfg: Settings.updates
    readonly property int interval: Math.max(0, Math.min(1440, cfg.interval ?? 30))
    readonly property bool withAur: cfg.aur ?? true

    // [{ name, old, new }]
    property var repo: []
    property var aur: []
    readonly property int count: repo.length + (withAur ? aur.length : 0)
    property bool checking: checkProc.running || aurChecking
    property bool aurChecking: false
    property real lastCheck: 0
    property string error: ""

    property var pacnew: []                 // /etc files with a .pacnew / .pacsave next to them
    property bool rebootNeeded: false       // the running kernel's modules are gone (kernel was updated)
    property string news: ""
    property bool newsLoaded: false

    function parse(text) {
        return text.split("\n").map(l => /^(\S+) (\S+) -> (\S+)/.exec(l)).filter(m => m)
                   .map(m => ({ name: m[1], old: m[2], new: m[3] }))
    }

    function refresh() {
        if (!checkProc.running)
            checkProc.running = true;
        if (withAur && !aurChecking) {
            aurChecking = true
            Jobs.which(["yay"], have => {
                if (!have.yay) { aurChecking = false; aur = []; return }
                Jobs.run(["yay", "-Qua"], (code, out) => { aur = parse(out); aurChecking = false })
            })
        }
        Jobs.run(["pacdiff", "-o"], (code, out) => pacnew = out.split("\n").filter(l => l.startsWith("/")))
        const kernel = NiriSettings.readFile("/proc/sys/kernel/osrelease").trim()
        if (kernel !== "") Jobs.run(["test", "-d", "/usr/lib/modules/" + kernel], code => rebootNeeded = code !== 0)
    }

    function loadNews() {
        Jobs.run(["yay", "-Pw"], (code, out) => { news = out.replace(/\x1b\[[0-9;]*m/g, "").trim(); newsLoaded = true })
    }

    // Runs the system upgrade in a terminal, then re-checks once it closes
    function upgrade() {
        if (!upgradeProc.running)
            upgradeProc.running = true;
    }

    // a notification for packages that weren't pending before (Settings.updates.notify)
    property var notifiedNames: []
    property bool notifiedOnce: false
    property int lastNotified: 0            // how many the last notification was about
    // once per check, after both the repo and the AUR lists are in
    onCheckingChanged: if (!checking) notifyNew()
    function notifyNew() {
        const all = repo.concat(withAur ? aur : []).map(u => u.name + " " + u.new)
        const fresh = all.filter(n => !notifiedNames.includes(n))
        const first = !notifiedOnce             // first check since login: what's pending, not "new"
        notifiedOnce = true
        notifiedNames = all
        if (!(cfg.notify ?? false) || fresh.length === 0) return
        lastNotified = fresh.length
        Jobs.run(["notify-send", "-a", "Updates", "-i", "system-software-update",
                  // all.length, not count: count may not have updated yet when this runs
                  first ? all.length + (all.length === 1 ? " update available" : " updates available")
                        : fresh.length + (fresh.length === 1 ? " new update" : " new updates") + " (" + all.length + " pending)",
                  fresh.slice(0, 8).map(n => n.split(" ")[0]).join(", ") + (fresh.length > 8 ? ", …" : "")], () => {})
    }

    Process {
        id: checkProc
        // exit codes: 0 = updates available, 2 = no updates, anything else = error
        command: ["checkupdates", "--nocolor"]
        running: true
        stdout: StdioCollector { id: collector }
        stderr: StdioCollector { id: errCollector }
        onExited: exitCode => {
            if (exitCode === 0) {
                root.repo = root.parse(collector.text);
                root.error = "";
                root.lastCheck = Date.now();
                retryTimer.stop();
            } else if (exitCode === 2) {
                root.repo = [];
                root.error = "";
                root.lastCheck = Date.now();
                retryTimer.stop();
            } else {
                // network down / db locked: keep the last known list, try again soon
                root.error = errCollector.text.trim().split("\n").pop() || "checkupdates failed (exit " + exitCode + ")";
                retryTimer.restart();
            }
        }
    }

    Process {
        id: upgradeProc
        command: ["kitty", "--class", "custom_hover", "-e", "bash", "-c",
            "sudo ls >/dev/null 2>&1 && sudo pacman -Syu --noconfirm && yay -Quq --aur | xargs -n 1 yay -S --noconfirm"]
        onExited: root.refresh()
    }

    Timer {
        interval: Math.max(1, root.interval) * 60 * 1000  // regular re-check (Settings → Updates)
        running: root.interval > 0
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        id: retryTimer
        interval: 60 * 1000  // retry a failed check after 1 minute
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()

    IpcHandler {
        target: "updates"
        function check(): void { root.refresh() }
        function count(): int { return root.count }
        function list(): string {
            return root.repo.concat(root.withAur ? root.aur.map(u => Object.assign({ aur: true }, u)) : [])
                       .map(u => u.name + " " + u.old + " -> " + u.new + (u.aur ? " (AUR)" : "")).join("\n")
        }
    }
}
