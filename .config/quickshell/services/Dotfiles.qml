pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Dotfiles repo status and the sync scripts (settings app → Maintenance → Dotfiles).
//
// Reads git state, and runs the repo's own scripts (scripts/config/*.sh):
//   check.sh            dry run: what differs between ~/.config and the repo
//   push.sh <profile>   copy ~/.config into the repo's working tree
//   pull.sh / update.sh <profile>   in a terminal (they may ask for sudo and
//                       restart the shell)
// It never commits, pushes, resets or discards anything; that stays with you.
//
//   qs ipc call dotfiles status
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string repo: (Settings.dotfiles.repo ?? "~/git/dotfiles").replace(/^~(?=\/|$)/, home)
    readonly property string scripts: repo + "/scripts/config"

    // git state
    property bool isRepo: false
    property bool loading: false
    property string branch: ""
    property string upstream: ""
    property int ahead: 0
    property int behind: 0
    property var files: []                 // [{ xy, path }] uncommitted in the repo
    property var lastCommit: null          // { hash, subject, when }
    property real fetchedAt: 0
    property string error: ""

    // ~/.config vs repo (check.sh)
    property var diffs: []                 // [{ kind: "changed" | "new" | "deleted", path }]
    property bool checked: false
    property string checkError: ""

    readonly property bool fetching: Jobs.isRunning("dotfiles-fetch")
    readonly property bool checking: Jobs.isRunning("dotfiles-check")
    readonly property bool pushing: Jobs.isRunning("dotfiles-push")

    // no password / host-key prompts from a background git
    readonly property var gitEnv: ({ GIT_TERMINAL_PROMPT: "0", GIT_SSH_COMMAND: "ssh -o BatchMode=yes -o ConnectTimeout=10" })

    function refresh() {
        loading = true
        error = ""
        Jobs.run(["git", "-C", repo, "status", "--porcelain=v1", "-b", "-uall"], (code, out, err) => {
            loading = false
            isRepo = code === 0
            if (code !== 0) { error = err.trim() || "not a git repository"; files = []; return }
            const lines = out.split("\n").filter(l => l !== "")
            const head = lines[0] ?? ""
            const m = /^## (.+?)(?:\.\.\.(\S+))?(?: \[(.*)\])?$/.exec(head)
            branch = m ? m[1].replace(/^No commits yet on /, "") : ""
            upstream = m?.[2] ?? ""
            const ab = m?.[3] ?? ""
            ahead = Number(/ahead (\d+)/.exec(ab)?.[1] ?? 0)
            behind = Number(/behind (\d+)/.exec(ab)?.[1] ?? 0)
            files = lines.slice(1).map(l => ({ xy: l.slice(0, 2), path: l.slice(3) }))
        })
        Jobs.run(["git", "-C", repo, "log", "-1", "--format=%h%x09%s%x09%cr"], (code, out) => {
            const p = out.trim().split("\t")
            lastCommit = code === 0 && p.length === 3 ? { hash: p[0], subject: p[1], when: p[2] } : null
        })
    }

    function fetch() {
        Jobs.start("dotfiles-fetch", ["git", "-C", repo, "fetch", "--prune"], {
            timeout: 60000, env: gitEnv,
            onExit: code => { if (code === 0) fetchedAt = Date.now(); refresh() }
        })
    }
    function cancelFetch() { Jobs.cancel("dotfiles-fetch") }

    function check() {
        checkError = ""
        Jobs.start("dotfiles-check", ["bash", scripts + "/check.sh"], {
            timeout: 60000, cwd: home,
            onExit: code => {
                const lines = Jobs.state("dotfiles-check").lines
                const d = []
                for (const l of lines) {
                    const m = /^(\S+) (.+)$/.exec(l.text)
                    if (!m || l.err) continue
                    if (m[1] === "*deleting") d.push({ kind: "deleted", path: m[2] })
                    else if (/^[<>c]f\+/.test(m[1])) d.push({ kind: "new", path: m[2] })
                    else if (/^[<>c][fL]/.test(m[1])) d.push({ kind: "changed", path: m[2] })
                }
                diffs = d
                checked = code === 0 || code === 1
                if (!checked) checkError = Jobs.state("dotfiles-check").missing
                    ? "missing: " + Jobs.state("dotfiles-check").missing
                    : (lines.filter(l => l.err).map(l => l.text).slice(-2).join(" ") || "check.sh failed (exit " + code + ")")
            }
        })
    }

    // copy ~/.config into the repo working tree (nothing is committed)
    function push(profile, cb) {
        Jobs.start("dotfiles-push", ["bash", scripts + "/push.sh", profile], {
            timeout: 300000, cwd: home,
            onExit: code => { refresh(); check(); if (cb) cb(code) }
        })
    }

    // push.sh in a terminal you can watch (the bar's push button); nothing is committed
    function pushInTerminal(profile) {
        Quickshell.execDetached(["kitty", "--title", "Dotfiles: push", "--directory", home, "bash", scripts + "/push.sh", profile])
    }

    // these may ask for sudo and restart the shell: a terminal you can watch
    function pullUpdate(profile) {
        Quickshell.execDetached(["kitty", "--title", "Dotfiles: pull + update", "--directory", home, "bash", scripts + "/pull.sh", profile])
    }
    function update(profile) {
        Quickshell.execDetached(["kitty", "--title", "Dotfiles: update", "--directory", home, "bash", scripts + "/update.sh", profile])
    }
    function openTerminal() {
        Quickshell.execDetached(["kitty", "--directory", repo])
    }

    IpcHandler {
        target: "dotfiles"
        function status(): string {
            if (!root.isRepo) return root.error || "not loaded yet: qs ipc call dotfiles refresh"
            return root.branch + (root.upstream ? " → " + root.upstream : "") + "  ahead " + root.ahead + ", behind " + root.behind
                 + "  ·  " + root.files.length + " uncommitted" + (root.checked ? "  ·  " + root.diffs.length + " differences with ~/.config" : "")
        }
        function refresh(): void { root.refresh(); root.check() }
    }
}
