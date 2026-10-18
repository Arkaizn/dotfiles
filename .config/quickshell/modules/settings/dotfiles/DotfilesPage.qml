import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Dotfiles page (services/Dotfiles.qml): repo state, what differs from
// ~/.config, and the sync scripts, each behind a confirmation that says what
// it will overwrite. Committing and pushing stay with you.
ColumnLayout {
    id: page
    spacing: 16

    property string profile: Settings.dotfiles.profile ?? "default"
    property string confirm: ""            // "push" | "pull" | "update" | ""
    property bool showLog: false

    Component.onCompleted: { Dotfiles.refresh(); Dotfiles.check() }

    readonly property var pushLog: Jobs.state("dotfiles-push")
    readonly property int maxList: 12

    function kindIcon(k) { return k === "new" ? "󰐕" : k === "deleted" ? "󰍴" : "󰏫" }
    function kindColor(k) { return k === "new" ? Colors.green : k === "deleted" ? Colors.red : Colors.yellow }

    // ── Repository ──────────────────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        title: "Repository"
        header: [
            ActionButton {
                icon: Dotfiles.fetching ? "󰜺" : "󰇚"
                text: Dotfiles.fetching ? "Cancel" : "Fetch"
                interactive: Dotfiles.isRepo
                onClicked: Dotfiles.fetching ? Dotfiles.cancelFetch() : Dotfiles.fetch()
            },
            ActionButton { icon: "󰆍"; text: "Terminal"; interactive: Dotfiles.isRepo; onClicked: Dotfiles.openTerminal() }
        ]
        NetRow {
            first: true
            label: "Folder"
            desc: Dotfiles.isRepo ? "a git repository" : (Dotfiles.loading ? "checking…" : Dotfiles.error)
            TextControl {
                value: Settings.dotfiles.repo ?? "~/git/dotfiles"
                onEdited: v => { Settings.set("dotfiles", "repo", v.trim() || "~/git/dotfiles"); Qt.callLater(() => { Dotfiles.refresh(); Dotfiles.check() }) }
            }
        }
        NetRow {
            visible: Dotfiles.isRepo
            label: Dotfiles.branch + (Dotfiles.upstream ? "  →  " + Dotfiles.upstream : "  (no upstream)")
            desc: (Dotfiles.lastCommit ? "last commit " + Dotfiles.lastCommit.hash + " " + Dotfiles.lastCommit.subject + " (" + Dotfiles.lastCommit.when + ")" : "")
                  + (Dotfiles.fetchedAt > 0 ? "  ·  fetched " + new Date(Dotfiles.fetchedAt).toLocaleTimeString(Qt.locale(), "HH:mm")
                                            : "  ·  ahead / behind as of the last fetch")
            RowLayout {
                spacing: 6
                Chip { text: "↑ " + Dotfiles.ahead; label: "ahead"; copyable: false; accent: Dotfiles.ahead > 0 }
                Chip { text: "↓ " + Dotfiles.behind; label: "behind"; copyable: false; accent: Dotfiles.behind > 0 }
            }
        }
        NetRow {
            visible: Dotfiles.isRepo
            label: Dotfiles.files.length === 0 ? "No uncommitted changes" : Dotfiles.files.length + " uncommitted " + (Dotfiles.files.length === 1 ? "file" : "files")
            desc: Dotfiles.files.length === 0 ? "working tree clean"
                  : Dotfiles.files.slice(0, page.maxList).map(f => f.xy.trim() + " " + f.path).join("\n")
                    + (Dotfiles.files.length > page.maxList ? "\n… and " + (Dotfiles.files.length - page.maxList) + " more" : "")
                    + "\nCommit and push them yourself (Terminal)."
        }
    }

    // ── ~/.config vs repo ───────────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        visible: Dotfiles.isRepo
        title: "~/.config compared with the repo"
        header: ActionButton {
            icon: "󰑓"; text: Dotfiles.checking ? "Checking…" : "Check again"
            interactive: !Dotfiles.checking && !Dotfiles.pushing
            onClicked: Dotfiles.check()
        }
        NetRow {
            first: true
            label: Dotfiles.checking && !Dotfiles.checked ? "Checking…"
                 : Dotfiles.checkError !== "" ? "check.sh failed"
                 : Dotfiles.diffs.length === 0 ? "Same as the repo" : Dotfiles.diffs.length + " differences"
            desc: Dotfiles.checkError !== "" ? Dotfiles.checkError
                : Dotfiles.diffs.length === 0 ? "per-device files (custom/, settings.json, …) are not compared"
                : "a copy into the repo would change these; a pull + update would overwrite them here"
        }
        Repeater {
            model: Dotfiles.diffs.slice(0, page.maxList)
            NetRow {
                required property var modelData
                sub: true
                label: modelData.path
                RowLayout {
                    spacing: 6
                    Text { text: page.kindIcon(modelData.kind); color: page.kindColor(modelData.kind); font.pixelSize: 14; font.family: Properties.fontFamily }
                    Text { text: modelData.kind; color: page.kindColor(modelData.kind); font.pixelSize: 11; font.family: Properties.fontFamily }
                }
            }
        }
        NetRow {
            visible: Dotfiles.diffs.length > page.maxList
            sub: true
            label: "… and " + (Dotfiles.diffs.length - page.maxList) + " more"
        }
    }

    // ── Sync ────────────────────────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        visible: Dotfiles.isRepo
        title: "Sync"
        NetRow {
            first: true
            label: "Profile"
            desc: page.profile === "default" ? "per-device files (custom/, monitors, settings.json, …) are left alone"
                                             : "full: per-device files are copied too"
            Segmented {
                small: true
                options: [{ label: "default", value: "default" }, { label: "full", value: "full" }]
                value: page.profile
                onEdited: v => { page.profile = v; Settings.set("dotfiles", "profile", v) }
            }
        }

        NetRow {
            label: "Copy my config into the repo"
            desc: "push.sh " + page.profile + ": rsync ~/.config → repo working tree. Nothing is committed or pushed."
            ActionButton {
                icon: "󰕒"; text: Dotfiles.pushing ? "Copying…" : "Copy…"
                interactive: !Dotfiles.pushing && page.confirm === ""
                onClicked: page.confirm = "push"
            }
        }
        NetRow {
            label: "Pull and update"
            desc: "pull.sh " + page.profile + ": git pull, then update.sh copies the repo over ~/.config. In a terminal; may ask for sudo; restarts the shell."
            ActionButton { icon: "󰇚"; text: "Pull…"; interactive: page.confirm === ""; onClicked: page.confirm = "pull" }
        }
        NetRow {
            label: "Update from the repo (no pull)"
            desc: "update.sh " + page.profile + ": copy the repo as it is now over ~/.config. In a terminal; restarts the shell."
            ActionButton { icon: "󰑓"; text: "Update…"; interactive: page.confirm === ""; onClicked: page.confirm = "update" }
        }

        // confirmation: what it will overwrite
        Reveal {
            open: page.confirm !== ""
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: 12
                implicitHeight: cf.implicitHeight + 24
                radius: 10
                color: Qt.rgba(0.98, 0.89, 0.69, 0.07)
                border.width: 1
                border.color: Qt.rgba(0.98, 0.89, 0.69, 0.4)
                ColumnLayout {
                    id: cf
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Colors.ink
                        font.pixelSize: 12
                        font.family: Properties.fontFamily
                        text: page.confirm === "push"
                              ? "Copy ~/.config into " + Dotfiles.repo.replace(Dotfiles.home, "~") + " (" + page.profile + ")?\n"
                                + (Dotfiles.diffs.length > 0 ? Dotfiles.diffs.length + " repo files change (" + Dotfiles.diffs.filter(d => d.kind === "deleted").length + " deleted from the repo). " : "Nothing differs right now. ")
                                + (Dotfiles.files.length > 0 ? "The repo already has " + Dotfiles.files.length + " uncommitted changes, which may be overwritten. " : "")
                                + "You review, commit and push afterwards."
                              : (page.confirm === "pull" ? "Pull from " + (Dotfiles.upstream || "the remote") + " and copy the repo over ~/.config (" + page.profile + ")?\n"
                                                         : "Copy the repo over ~/.config (" + page.profile + ")?\n")
                                + (Dotfiles.diffs.length > 0 ? "󰀦 " + Dotfiles.diffs.length + " files in ~/.config differ from the repo and will be OVERWRITTEN (list above). Copy them into the repo first if you want to keep them. "
                                                             : "~/.config matches the repo, nothing local is lost. ")
                                + "Runs in a terminal and restarts the shell at the end."
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: 8
                        ActionButton { text: "Cancel"; onClicked: page.confirm = "" }
                        ActionButton {
                            icon: "󰄬"
                            primary: true
                            text: page.confirm === "push" ? "Copy to repo" : page.confirm === "pull" ? "Pull + update" : "Update"
                            onClicked: {
                                const what = page.confirm
                                page.confirm = ""
                                if (what === "push") { page.showLog = true; Dotfiles.push(page.profile) }
                                else if (what === "pull") Dotfiles.pullUpdate(page.profile)
                                else Dotfiles.update(page.profile)
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Output of the last copy ─────────────────────────────────────────────
    NetCard {
        Layout.fillWidth: true
        visible: page.showLog && page.pushLog.lines.length > 0
        title: "push.sh output" + (Dotfiles.pushing ? " (running)" : page.pushLog.code === 0 ? " (done)" : page.pushLog.code > 0 ? " (exit " + page.pushLog.code + ")" : "")
        header: ActionButton { text: "Hide"; onClicked: page.showLog = false }
        Text {
            Layout.fillWidth: true
            Layout.margins: 14
            text: page.pushLog.lines.slice(-20).map(l => l.text.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "")).filter(t => t.trim() !== "").join("\n")
            color: Colors.fade(0.7)
            font.pixelSize: 11
            font.family: "monospace"
            wrapMode: Text.WrapAnywhere
        }
    }
}
