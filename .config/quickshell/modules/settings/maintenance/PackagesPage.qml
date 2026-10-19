import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import ".."
import "../network"

// Package maintenance: keep the system lean.
//   · Unused programs: the packages you installed, sorted by when you last ran
//     one of their programs (access time of their /usr/bin files; the file
//     system updates it at most once a day). Services run read-only and never
//     update it, so a package with an enabled / running systemd unit counts as
//     in use. Only apps with a launcher by default (command-line tools like
//     wget are useful even when rarely run); never base / base-devel, never
//     ones you keep (Settings.updates.keepPackages). Pick some and remove them
//     (scripts/remove-packages.sh: skips what other packages still need, then
//     pacman -Rns, which shows everything and asks first).
//     Data: scripts/package-usage.sh
//   · Orphans: just the count (removing them: CleanupPage, the other tab).
//   · Biggest packages, and what was recently installed / updated / removed.
// Packages without programs (fonts, themes, libraries) can't be rated by use.
ColumnLayout {
    id: page
    spacing: 16

    // [{ name, size, explicit, date, aur, bins, used, changed, service, app, requiredBy, groups }]
    //   bins: programs in /usr/bin · used: last run (unix s, 0 = not since it
    //   was installed / updated) · changed: when its programs were installed / updated
    //   · service: has an enabled or running systemd unit (counts as in use)
    //   · app: has a launcher (.desktop) · requiredBy: installed packages that need it
    property var pkgs: []
    property var history: []                // [{ time, action, name, version }]
    property var orphans: []                // names
    property string kind: "all"             // all | explicit | deps | aur
    property string query: ""
    property bool loading: true
    property int unusedDays: 90             // 0 = all
    property bool cliToo: false             // also command-line tools (no launcher)
    readonly property var keep: Settings.updates.keepPackages ?? []
    property var selected: ({})             // name → true
    property string confirm: ""

    readonly property var shown: {
        const q = query.trim().toLowerCase()
        return pkgs.filter(p => (kind === "all" || (kind === "explicit" && p.explicit) || (kind === "deps" && !p.explicit) || (kind === "aur" && p.aur))
                              && (q === "" || p.name.includes(q)))
    }
    readonly property real totalSize: pkgs.reduce((a, p) => a + p.size, 0)
    readonly property real now: Date.now() / 1000

    // yours, with programs, by last activity (never run since installed first)
    readonly property var rated: pkgs.filter(p => p.explicit && p.bins > 0 && !p.service && (p.app || cliToo)
                                                  && !keep.includes(p.name) && !p.groups.some(g => g === "base" || g === "base-devel"))
    readonly property var unused: rated.filter(p => unusedDays === 0 || now - (p.used || p.changed) > unusedDays * 86400)
                                       .sort((a, b) => (a.used || a.changed) - (b.used || b.changed))
    readonly property var picked: pkgs.filter(p => selected[p.name])
    readonly property int noPrograms: pkgs.filter(p => p.explicit && p.bins === 0).length

    Component.onCompleted: load()

    function load() {
        loading = true
        selected = ({})
        Jobs.run(["pacman", "-Qmq"], (c0, aurOut) => {
            const aur = aurOut.split("\n").filter(x => x)
            Jobs.run(["pacman", "-Qi"], (code, out) => {
                const list = []
                let cur = null
                let field = ""
                const unit = { B: 1, KiB: 1024, MiB: 1048576, GiB: 1073741824 }
                for (const l of out.split("\n")) {
                    let m
                    if (/^\S/.test(l)) field = ""          // a new field ends a continued list
                    if ((m = /^Name\s*:\s*(\S+)/.exec(l))) { cur = { name: m[1], size: 0, explicit: false, date: "", aur: aur.includes(m[1]), bins: 0, used: 0, changed: 0, service: false, app: false, requiredBy: [], groups: [] }; list.push(cur); field = "" }
                    else if (!cur) continue
                    // long lists go on in lines starting with spaces
                    else if ((m = /^\s+(\S.*)$/.exec(l)) && (field === "req" || field === "grp")) (field === "req" ? cur.requiredBy : cur.groups).push(...m[1].trim().split(/\s+/))
                    else if ((m = /^Required By\s*:\s*(.*)$/.exec(l))) { field = "req"; cur.requiredBy = m[1].trim() === "None" ? [] : m[1].trim().split(/\s+/) }
                    else if ((m = /^Groups\s*:\s*(.*)$/.exec(l))) { field = "grp"; cur.groups = m[1].trim() === "None" ? [] : m[1].trim().split(/\s+/) }
                    else if ((m = /^Installed Size\s*:\s*([\d.]+)\s*(\w+)/.exec(l))) cur.size = Number(m[1]) * (unit[m[2]] ?? 1)
                    else if ((m = /^Install Reason\s*:\s*(.*)$/.exec(l))) cur.explicit = m[1].startsWith("Explicitly")
                    else if ((m = /^Install Date\s*:\s*(.*)$/.exec(l))) cur.date = m[1].trim()
                }
                list.sort((a, b) => b.size - a.size)
                loadUsage(list)
            }, { LC_ALL: "C" })
        })
        Jobs.run(["pacman", "-Qdtq"], (c, out) => orphans = out.split("\n").filter(x => x))
        Jobs.run(["tail", "-n", "3000", "/var/log/pacman.log"], (code, out) => {
            history = out.split("\n").map(l => /^\[([^\]]+)\] \[ALPM\] (installed|upgraded|removed|downgraded) (\S+) \((.*)\)$/.exec(l))
                         .filter(m => m).map(m => ({ time: m[1].replace("T", " ").slice(0, 16), action: m[2], name: m[3], version: m[4] }))
                         .reverse().slice(0, 40)
        })
    }

    // programs, their access / change times and the systemd units (scripts/package-usage.sh)
    function loadUsage(list) {
        Jobs.run([Quickshell.shellDir + "/scripts/package-usage.sh"], (code, out) => {
            const owner = {}, byName = {}, units = [], active = new Set()
            // foo@bar.service → foo@.service (template units)
            const base = u => u.replace(/@[^.]*\./, "@.")
            for (const p of list) byName[p.name] = p
            for (const l of out.split("\n")) {
                const f = l.split("\t")
                if (f[0] === "P" && f.length === 3) { owner[f[2]] = byName[f[1]]; if (byName[f[1]]) byName[f[1]].bins++ }
                else if (f[0] === "S" && f.length === 4) {
                    const p = owner[f[3]]
                    if (!p) continue
                    const at = Number(f[1]), ct = Number(f[2])
                    p.changed = Math.max(p.changed, ct)
                    // read after it was installed / updated = it ran
                    if (at > ct + 120) p.used = Math.max(p.used, at)
                }
                else if (f[0] === "U" && f.length === 3) units.push(f)
                else if (f[0] === "A" && f.length === 2) active.add(base(f[1]))
                else if (f[0] === "D" && f.length === 2 && byName[f[1]]) byName[f[1]].app = true
            }
            for (const u of units) if (byName[u[1]] && active.has(base(u[2]))) byName[u[1]].service = true
            pkgs = list
            loading = false
        })
    }

    function ago(t) {
        const d = Math.floor((now - t) / 86400)
        return d < 1 ? "today" : d < 2 ? "yesterday" : d < 60 ? d + " days ago" : d < 730 ? Math.round(d / 30) + " months ago" : Math.round(d / 365) + " years ago"
    }
    function usageText(p) {
        return p.used ? "last used " + ago(p.used)
                      : "not used since it was " + (p.changed ? "installed / updated " + ago(p.changed) : "installed")
    }

    // pick / unpick everything in the current "not used for" list
    // (not the ones other packages still need: they can't be removed alone)
    readonly property var pickable: unused.filter(p => p.requiredBy.length === 0)
    readonly property bool allPicked: pickable.length > 0 && pickable.every(p => selected[p.name])
    function pickAll(on) {
        const s = Object.assign({}, selected)
        for (const p of pickable) { if (on) s[p.name] = true; else delete s[p.name] }
        selected = s
    }
    function setKeep(name, on) {
        const k = keep.filter(x => x !== name)
        if (on) k.push(name)
        Settings.set("updates", "keepPackages", k.sort())
        if (on && selected[name]) toggle(name)
    }

    function toggle(name) {
        const s = Object.assign({}, selected)
        if (s[name]) delete s[name]; else s[name] = true
        selected = s
    }
    function ask(id) { confirm = id; confirmTimer.restart() }
    Timer { id: confirmTimer; interval: 3000; onTriggered: page.confirm = "" }

    NetCard {
        Layout.fillWidth: true
        title: "Installed"
        icon: "󰏗"
        header: ActionButton { icon: "󰑓"; text: page.loading ? "Reading…" : "Reload"; onClicked: page.load() }
        NetRow {
            first: true
            label: page.loading ? "Reading the package database…" : page.pkgs.length + " packages  ·  " + Format.bytes(page.totalSize)
            desc: page.pkgs.filter(p => p.explicit).length + " installed by you, " + page.pkgs.filter(p => !p.explicit).length
                  + " as dependencies, " + page.pkgs.filter(p => p.aur).length + " from the AUR / not in the repos"
        }
        NetRow {
            label: page.orphans.length === 0 ? "No orphans" : page.orphans.length + " orphans"
            desc: page.orphans.length === 0 ? "every dependency is still needed by something"
                  : "dependencies nothing needs any more: review and remove them in the Free space tab"
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "Unused programs"
        icon: "󰒡"
        NetRow {
            first: true
            label: "Not used for"
            desc: page.loading ? "reading…"
                  : page.unused.length + " of the " + page.rated.length + " packages with programs you installed"
                    + (page.noPrograms > 0 ? "  ·  " + page.noPrograms + " without programs (fonts, themes, libraries) can't be rated" : "")
                    + "  ·  ones with an enabled / running service count as in use"
                    + (page.keep.length > 0 ? "  ·  " + page.keep.length + " kept" : "")
            RowLayout {
                spacing: 8
                Segmented {
                    small: true
                    options: [{ label: "30 days", value: 30 }, { label: "90 days", value: 90 }, { label: "1 year", value: 365 }, { label: "All", value: 0 }]
                    value: page.unusedDays
                    onEdited: v => page.unusedDays = v
                }
                ActionButton {
                    icon: page.allPicked ? "󰄱" : "󰄲"
                    text: page.allPicked ? "Unpick all" : "Pick all " + page.pickable.length
                    interactive: page.pickable.length > 0
                    onClicked: page.pickAll(!page.allPicked)
                }
            }
        }
        NetRow {
            sub: true
            label: "Command-line tools too"
            desc: page.cliToo ? "also programs without a launcher (wget, arp-scan, …): only remove ones you're sure about"
                              : "off: only apps with a launcher; command-line tools stay, even if rarely run"
            ToggleSwitch { checked: page.cliToo; onToggled: v => page.cliToo = v }
        }
        NetRow {
            sub: true
            visible: page.keep.length > 0
            label: page.keep.length + " kept (never suggested)"
            desc: page.keep.join(", ")
            ActionButton { text: "Forget all"; onClicked: Settings.set("updates", "keepPackages", []) }
        }
        Repeater {
            model: page.unused.slice(0, 40)
            NetRow {
                required property var modelData
                readonly property bool isPicked: !!page.selected[modelData.name]
                sub: true
                readonly property bool needed: modelData.requiredBy.length > 0
                label: modelData.name + (modelData.aur ? "  ·  AUR" : "") + (modelData.app ? "" : "  ·  command-line")
                desc: page.usageText(modelData) + "  ·  " + modelData.bins + (modelData.bins === 1 ? " program" : " programs")
                      + (needed ? "\nneeded by " + modelData.requiredBy.slice(0, 4).join(", ") + (modelData.requiredBy.length > 4 ? ", …" : "") + ": can't be removed alone" : "")
                RowLayout {
                    spacing: 8
                    Text { Layout.preferredWidth: 72; horizontalAlignment: Text.AlignRight; text: Format.bytes(modelData.size); color: Colors.ink; font.pixelSize: 12; font.family: Properties.fontFamily }
                    IconButton {
                        icon: "󰐃"
                        tooltip: "Keep: never suggest it here"
                        onClicked: page.setKeep(modelData.name, true)
                    }
                    IconButton {
                        icon: isPicked ? "󰄲" : "󰄱"
                        active: isPicked
                        interactive: !needed || isPicked
                        textColor: isPicked ? Colors.red : Properties.color
                        tooltip: isPicked ? "Don't remove" : "Pick for removal"
                        onClicked: page.toggle(modelData.name)
                    }
                }
            }
        }
        NetRow {
            visible: page.unused.length > 40
            sub: true
            label: "… and " + (page.unused.length - 40) + " more (pick a shorter time to narrow it)"
        }
        NetRow {
            visible: page.picked.length > 0
            label: page.picked.length + " picked  ·  " + Format.bytes(page.picked.reduce((a, p) => a + p.size, 0))
            desc: page.picked.map(p => p.name).join(", ")
                  + "\nOnes other packages still need are skipped; pacman -Rns also removes what only these needed. The terminal lists everything and asks first."
            RowLayout {
                spacing: 6
                ActionButton { text: "Clear"; onClicked: page.selected = ({}) }
                ActionButton {
                    icon: "󰆴"
                    text: page.confirm === "remove" ? "Open terminal" : "Remove…"
                    textColor: page.confirm === "remove" ? Colors.red : Colors.ink
                    onClicked: page.confirm === "remove"
                        ? (Quickshell.execDetached(["kitty", "--title", "Remove packages", Quickshell.shellDir + "/scripts/remove-packages.sh"].concat(page.picked.map(p => p.name))), page.confirm = "")
                        : page.ask("remove")
                }
            }
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "Biggest packages"
        NetRow {
            first: true
            label: "Show"
            RowLayout {
                spacing: 8
                Segmented {
                    small: true
                    options: [{ label: "All", value: "all" }, { label: "Yours", value: "explicit" }, { label: "Dependencies", value: "deps" }, { label: "AUR / local", value: "aur" }]
                    value: page.kind
                    onEdited: v => page.kind = v
                }
                SearchField { Layout.preferredWidth: 180; text: page.query; onTextEdited: page.query = text; placeholderText: "name" }
            }
        }
        Repeater {
            model: page.shown.slice(0, 30)
            NetRow {
                required property var modelData
                sub: true
                label: modelData.name + (modelData.aur ? "  ·  AUR / not in repos" : "") + (modelData.explicit ? "" : "  ·  dependency")
                desc: "installed " + modelData.date + (modelData.bins > 0 ? "  ·  " + page.usageText(modelData) : "")
                RowLayout {
                    spacing: 8
                    Rectangle {
                        implicitWidth: 120 * Math.min(1, modelData.size / Math.max(1, page.shown[0]?.size ?? 1))
                        implicitHeight: 6; radius: 3; color: Colors.color6
                    }
                    Text { Layout.preferredWidth: 80; horizontalAlignment: Text.AlignRight; text: Format.bytes(modelData.size); color: Colors.ink; font.pixelSize: 12; font.family: Properties.fontFamily }
                }
            }
        }
        NetRow {
            visible: page.shown.length > 30
            sub: true
            label: "… and " + (page.shown.length - 30) + " more (search to find one)"
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "Recently changed"
        NetRow {
            first: true
            visible: page.history.length === 0
            label: "Nothing in /var/log/pacman.log"
        }
        Repeater {
            model: page.history
            NetRow {
                required property var modelData
                required property int index
                first: index === 0
                label: modelData.name
                desc: modelData.version
                RowLayout {
                    spacing: 10
                    Text {
                        text: modelData.action
                        color: modelData.action === "removed" ? Colors.red : modelData.action === "installed" ? Colors.green : Colors.fade(0.6)
                        font.pixelSize: 11; font.family: Properties.fontFamily
                    }
                    Text { text: modelData.time; color: Colors.fade(0.45); font.pixelSize: 11; font.family: Properties.fontFamily }
                }
            }
        }
    }
}
