pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Single shared update checker. checkupdates locks a shared temp db, so
// running one instance per bar makes all but one fail (and report 0).
//
// Settings.updates: { interval (minutes, 0 = only by hand; default 30),
//                     aur (also yay -Qua; default true), notify (new updates → notification),
//                     rebootNotify (reboot needed → notification with a Reboot button; default true) }
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
    // AUR packages that failed to update and were put on hold by the upgrade
    // (scripts/upgrade.sh): skipped until a newer version comes out, and not
    // counted as pending. File lines: "name version". [{ name, version }]
    readonly property string heldFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/quickshell/aur-held"
    property var held: []
    function isHeld(u) { return held.some(h => h.name === u.name && h.version === u.new) }
    readonly property var aurPending: aur.filter(u => !isHeld(u))
    readonly property var aurHeld: aur.filter(u => isHeld(u))
    readonly property int count: repo.length + (withAur ? aurPending.length : 0)
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
        loadHeld()
        loadPacnew()
        const kernel = Files.read("/proc/sys/kernel/osrelease").trim()
        if (kernel !== "") Jobs.run(["test", "-d", "/usr/lib/modules/" + kernel], code => rebootNeeded = code !== 0)
    }

    function loadHeld() {
        Jobs.run(["cat", "--", heldFile], (code, out) => {
            held = out.split("\n").map(l => l.trim().split(/\s+/)).filter(p => p.length === 2).map(p => ({ name: p[0], version: p[1] }))
        })
    }
    // take a package off hold: the next upgrade tries it again
    function release(name) {
        Jobs.run(["sh", "-c", 'awk -v n="$2" \'$1 != n\' "$1" > "$1.tmp" && mv "$1.tmp" "$1"', "sh", heldFile, name], () => loadHeld())
    }

    // reboot needed: a notification (Settings.updates.rebootNotify), once each time it turns true
    onRebootNeededChanged: if (rebootNeeded && (cfg.rebootNotify ?? true)) notifyReboot()
    function notifyReboot() {
        Jobs.run(["notify-send", "-a", "Updates", "-u", "critical", "-i", "system-reboot", "-A", "reboot=Reboot now", "-A", "later=Later",
                  "Reboot needed", "The kernel was updated. Reboot to finish the update (until then, USB sticks or VPNs may not work)."],
                 (code, out) => { if (out.trim() === "reboot") Session.reboot() })
    }

    function loadNews() {
        Jobs.run(["yay", "-Pw"], (code, out) => { news = out.replace(/\x1b\[[0-9;]*m/g, "").trim(); newsLoaded = true })
    }

    // Runs the system upgrade in a terminal, then re-checks once it closes
    function upgrade() {
        if (!upgradeProc.running)
            upgradeProc.running = true;
    }

    function loadPacnew() {
        Jobs.run(["pacdiff", "-o"], (code, out) => pacnew = out.split("\n").filter(l => l.startsWith("/")))
    }

    // Removes .pacnew / .pacsave files, or puts a .pacnew in place of its file
    // ("overwrite", pacdiff's (O)), as root through polkit (pkexec), no terminal.
    // Removing only drops the new default (your file stays as it is): always safe.
    // Overwriting first copies your file to /var/backups/pacnew/<time>/<its path>.
    // The root script takes the paths as arguments and checks each one again: only
    // regular files in /etc ending in .pacnew / .pacsave, no "..".
    //   pacnewAct("remove" | "overwrite", [paths], done(ok, message))
    property bool pacnewBusy: false
    readonly property string pacnewScript: 'act=$1; shift; ts=$(date +%Y%m%d-%H%M%S); rc=0\n'
        + 'for f; do\n'
        + '  case $f in *..*) echo "skipped $f" >&2; rc=1; continue ;; /etc/*.pacnew|/etc/*.pacsave) ;; *) echo "skipped $f" >&2; rc=1; continue ;; esac\n'
        + '  if [ ! -f "$f" ] || [ -L "$f" ]; then echo "skipped $f: not a regular file" >&2; rc=1; continue; fi\n'
        + '  if [ "$act" = overwrite ]; then\n'
        + '    case $f in *.pacnew) ;; *) echo "skipped $f: only a .pacnew can replace its file" >&2; rc=1; continue ;; esac\n'
        + '    t=${f%.pacnew}\n'
        + '    if [ -e "$t" ]; then b=/var/backups/pacnew/$ts$t; mkdir -p "${b%/*}" && cp -a "$t" "$b" || { echo "no backup of $t, left it alone" >&2; rc=1; continue; }; fi\n'
        + '    mv -f "$f" "$t" && echo "replaced $t" || rc=1\n'
        + '  else rm -f "$f" && echo "removed $f" || rc=1; fi\n'
        + 'done; exit $rc'
    function pacnewAct(action, files, done) {
        if (pacnewBusy || files.length === 0) return
        pacnewBusy = true
        Jobs.run(["pkexec", "sh", "-c", pacnewScript, "sh", action].concat(files), (code, out, err) => {
            pacnewBusy = false
            loadPacnew()
            const n = out.split("\n").filter(l => l.trim()).length
            if (done) done(code === 0, code === 126 || code === 127 ? "cancelled (no password given)"
                : (action === "remove" ? n + " removed" : n + " replaced (your old file: /var/backups/pacnew/)")
                  + (err.trim() ? " · " + err.trim().split("\n").pop() : ""))
        })
    }

    // Merges the .pacnew / .pacsave files (pacdiff, side by side in nvim) in a
    // terminal, then re-checks once it closes
    function mergePacnew() {
        if (!pacdiffProc.running)
            pacdiffProc.running = true;
    }

    // a notification for packages that weren't pending before (Settings.updates.notify)
    property var notifiedNames: []
    property bool notifiedOnce: false
    property int lastNotified: 0            // how many the last notification was about
    // once per check, after both the repo and the AUR lists are in
    onCheckingChanged: if (!checking) notifyNew()
    function notifyNew() {
        const all = repo.concat(withAur ? aurPending : []).map(u => u.name + " " + u.new)
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
        // repos, then each AUR package on its own; failed ones can be retried
        // by hand or put on hold (scripts/upgrade.sh)
        command: ["kitty", "--class", "custom_hover", "--title", "System upgrade", "-e", Quickshell.shellDir + "/scripts/upgrade.sh"]
        onExited: root.refresh()
    }
    Process {
        id: pacdiffProc
        command: ["kitty", "--class", "custom_hover", "--title", "Merge .pacnew files", "-e", "bash", "-c",
                  'sudo DIFFPROG="nvim -d" pacdiff; echo; read -rp "Done. Press Enter to close" _']
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
