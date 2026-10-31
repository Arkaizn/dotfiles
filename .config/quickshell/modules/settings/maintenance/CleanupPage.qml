import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import ".."
import "../network"

// Cleanup: what takes space and can go, with the size first and a
// confirmation before anything is removed. Your own files (app caches,
// trash) are handled here; anything that needs root (package cache, journal,
// crash dumps, orphans) opens a terminal so you see the command and sudo / pacman
// ask there.
ColumnLayout {
    id: page
    spacing: 16

    readonly property string home: Quickshell.env("HOME")
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache")
    readonly property string trashDir: home + "/.local/share/Trash"

    property var caches: []                 // [{ path, size }]
    property real cacheTotal: 0
    property string pkgSaved: ""            // paccache dry run (keep 1 version)
    property string pkgUninstalled: ""      // cached packages that aren't installed any more
    property string journal: ""
    property real trash: -1
    property real coredumps: -1
    property var orphans: []                // [{ name, size }]
    // which action waits for its second click (within 4 s)
    ConfirmArm { id: arm; timeout: 4000 }
    property bool loading: false

    Component.onCompleted: refresh()

    function refresh() {
        loading = true
        Jobs.run(["du", "-x", "-d", "1", "-b", "--", cacheDir], (code, out) => {
            const l = out.split("\n").map(x => /^(\d+)\t(.+)$/.exec(x)).filter(m => m)
            cacheTotal = Number(l.find(m => m[2] === cacheDir)?.[1] ?? 0)
            caches = l.filter(m => m[2] !== cacheDir).map(m => ({ path: m[2], size: Number(m[1]) })).sort((a, b) => b.size - a.size).slice(0, 12)
            loading = false
        })
        const saved = (code, out) => (/disk space saved: ([^)]+)\)/.exec(out)?.[1]) ?? (/no candidate/.test(out) ? "nothing" : "")
        Jobs.run(["paccache", "-d", "-k", "1"], (c, o, e) => pkgSaved = saved(c, o + e))
        Jobs.run(["paccache", "-d", "-u", "-k", "0"], (c, o, e) => pkgUninstalled = saved(c, o + e))
        Jobs.run(["journalctl", "--disk-usage"], (c, o) => journal = (/take up ([\d.]+\s?[KMGT]?)/.exec(o)?.[1]) ?? "")
        Jobs.run(["du", "-sb", "--", trashDir], (c, o) => trash = c === 0 ? Number(o.split("\t")[0]) : 0)
        Jobs.run(["du", "-sb", "/var/lib/systemd/coredump"], (c, o) => coredumps = Number(o.split("\t")[0]) || 0)
        Jobs.run(["pacman", "-Qdtq"], (c, o) => {
            const names = o.split("\n").filter(n => /^[A-Za-z0-9@._+-]+$/.test(n))
            if (names.length === 0) { orphans = []; return }
            Jobs.run(["pacman", "-Qi", "--"].concat(names), (c2, o2) => {
                const out = []
                let cur = null
                for (const l of o2.split("\n")) {
                    let m
                    if ((m = /^Name\s*:\s*(\S+)/.exec(l))) { cur = { name: m[1], size: 0 }; out.push(cur) }
                    else if (cur && (m = /^Installed Size\s*:\s*([\d.]+)\s*(\w+)/.exec(l)))
                        cur.size = Number(m[1]) * ({ B: 1, KiB: 1024, MiB: 1048576, GiB: 1073741824 }[m[2]] ?? 1)
                }
                orphans = out.sort((a, b) => b.size - a.size)
            }, { LC_ALL: "C" })
        })
    }

    function armed(id) { return arm.armed === id }

    // a terminal for root actions; fixed scripts, arguments passed as data
    function terminal(title, script, args) {
        Quickshell.execDetached(["kitty", "--title", title, "bash", "-c",
            script + '\necho; read -r -p "Done. Press Enter to close." _', "bash"].concat(args ?? []))
    }

    // only folders right inside ~/.cache
    function isCache(p) { return p.startsWith(cacheDir + "/") && !p.includes("/..") && p !== cacheDir + "/" }
    function clearCache(p) {
        if (!isCache(p)) return
        Jobs.run(["rm", "-rf", "--", p], () => refresh())
    }
    // every folder the list shows (the biggest ones), in one go
    readonly property real listedSize: caches.reduce((n, c) => n + c.size, 0)
    function clearListed() {
        const ps = caches.map(c => c.path).filter(isCache)
        if (ps.length > 0) Jobs.run(["rm", "-rf", "--"].concat(ps), () => refresh())
    }

    NetCard {
        Layout.fillWidth: true
        title: "App caches (" + Format.bytes(page.cacheTotal) + ")"
        icon: "󰃢"
        header: ActionButton { icon: "󰑓"; text: page.loading ? "Measuring…" : "Measure again"; onClicked: page.refresh() }
        NetRow {
            first: true
            wide: true
            label: "~/.cache"
            desc: "safe to clear: apps rebuild what they need (close the app first; the next start can be slower)"
            ActionButton {
                visible: page.caches.length > 0
                icon: "󰃢"
                text: page.armed("listed") ? "Delete " + page.caches.length + " folders, " + Format.bytes(page.listedSize) : "Clear all listed…"
                textColor: page.armed("listed") ? Colors.red : Colors.ink
                onClicked: { if (arm.confirm("listed")) page.clearListed() }
            }
        }
        Repeater {
            model: page.caches
            NetRow {
                required property var modelData
                sub: true
                label: modelData.path.replace(page.home, "~")
                RowLayout {
                    spacing: 8
                    Text { text: Format.bytes(modelData.size); color: Colors.ink; font.pixelSize: 12; font.family: Properties.fontFamily }
                    ActionButton {
                        text: page.armed(modelData.path) ? "Delete " + Format.bytes(modelData.size) : "Clear…"
                        textColor: page.armed(modelData.path) ? Colors.red : Colors.ink
                        onClicked: { if (arm.confirm(modelData.path)) page.clearCache(modelData.path) }
                    }
                }
            }
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "System"
        icon: "󰏗"
        NetRow {
            first: true
            label: "Package cache"
            desc: "old versions (keeps the last one, for downgrades): " + (page.pkgSaved || "…")
                  + "  ·  removed packages: " + (page.pkgUninstalled || "…")
            ActionButton {
                text: page.armed("pkg") ? "Open terminal" : "Clean…"
                interactive: page.pkgSaved !== "nothing" || page.pkgUninstalled !== "nothing"
                onClicked: { if (arm.confirm("pkg")) page.terminal("Clean package cache", "sudo paccache -r -k 1 && sudo paccache -r -u -k 0") }
            }
        }
        NetRow {
            label: "System journal (logs)"
            desc: (page.journal || "…") + " · shrink to the newest 500 MB"
            ActionButton {
                text: page.armed("journal") ? "Open terminal" : "Shrink…"
                onClicked: { if (arm.confirm("journal")) page.terminal("Shrink journal", "sudo journalctl --vacuum-size=500M") }
            }
        }
        NetRow {
            label: "Crash dumps"
            desc: (page.coredumps < 0 ? "…" : Format.bytes(page.coredumps)) + " in /var/lib/systemd/coredump (only needed to debug a crash)"
            ActionButton {
                text: page.armed("dumps") ? "Open terminal" : "Delete…"
                interactive: page.coredumps > 0
                onClicked: { if (arm.confirm("dumps")) page.terminal("Delete crash dumps", "sudo find /var/lib/systemd/coredump -type f -delete && echo deleted") }
            }
        }
        NetRow {
            wide: page.orphans.length > 0
            label: page.orphans.length + " orphan packages  ·  " + Format.bytes(page.orphans.reduce((a, o) => a + o.size, 0))
            desc: page.orphans.length === 0 ? "installed as dependencies, nothing needs them any more"
                  : "installed as dependencies that nothing needs any more (some may be optional extras you use!). Biggest: "
                    + page.orphans.slice(0, 12).map(o => o.name + " " + Format.bytes(o.size)).join(", ") + (page.orphans.length > 12 ? ", …" : "")
                    + "\nThe terminal shows pacman's full list and asks before removing."
            ActionButton {
                text: page.armed("orphans") ? "Open terminal" : "Review…"
                interactive: page.orphans.length > 0
                onClicked: { if (arm.confirm("orphans")) page.terminal("Remove orphan packages", 'sudo pacman -Rns -- "$@"', page.orphans.map(o => o.name)) }
            }
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "Trash"
        icon: "󰩹"
        NetRow {
            first: true
            label: page.trash < 0 ? "…" : page.trash === 0 ? "Empty" : Format.bytes(page.trash)
            desc: "~/.local/share/Trash"
            RowLayout {
                spacing: 6
                ActionButton { icon: "󰉋"; text: "Open"; onClicked: Quickshell.execDetached(["xdg-open", "trash:///"]) }
                ActionButton {
                    text: page.armed("trash") ? "Empty for good" : "Empty…"
                    textColor: page.armed("trash") ? Colors.red : Colors.ink
                    interactive: page.trash > 0
                    onClicked: { if (arm.confirm("trash")) Jobs.run(["gio", "trash", "--empty"], () => page.refresh()) }
                }
            }
        }
    }
}
