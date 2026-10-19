import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Mirrors: how old /etc/pacman.d/mirrorlist is and which servers it uses;
// refresh it with reflector in a terminal (sudo there; the old list is kept as
// mirrorlist.bak).
ColumnLayout {
    id: page
    spacing: 16

    readonly property string file: "/etc/pacman.d/mirrorlist"
    property var servers: []
    property string generated: ""
    property real ageDays: -1
    property bool hasPacnew: false
    property string countries: Settings.updates.mirrorCountries ?? ""
    property string latest: "20"
    property string sort: "rate"
    property string error: ""

    Component.onCompleted: load()

    function load() {
        const text = Files.read(file)
        servers = text.split("\n").map(l => /^\s*Server\s*=\s*(\S+)/.exec(l)).filter(m => m).map(m => m[1])
        generated = (/(?:Generated on|When:)\s*(.+)/.exec(text)?.[1] ?? "").trim()
        Jobs.run(["stat", "-c", "%Y", file], (c, o) => ageDays = c === 0 ? Math.floor((Date.now() / 1000 - Number(o)) / 86400) : -1)
        Jobs.run(["test", "-f", file + ".pacnew"], c => hasPacnew = c === 0)
        // default countries: the "## Country" headers of the current list
        if (countries === "") {
            const cs = []
            const re = /^## ([A-Z][A-Za-z ]+)$/gm     // (no String.matchAll in Qt's JS engine)
            let m
            while ((m = re.exec(text))) if (!cs.includes(m[1]) && !/Arch Linux|Filtered|Generated/.test(m[1])) cs.push(m[1])
            countries = cs.join(",")
        }
    }

    function check() {
        if (!/^[A-Za-z][A-Za-z ,]{0,120}$/.test(countries.trim())) return "countries: names or codes, separated by commas (e.g. CH,DE,AT)"
        if (!/^\d{1,2}$/.test(latest) || Number(latest) < 3 || Number(latest) > 50) return "number of mirrors: 3–50"
        if (!["rate", "score", "age", "delay"].includes(sort)) return "unknown sort"
        return ""
    }

    function refresh() {
        error = check()
        if (error) return
        Settings.set("updates", "mirrorCountries", countries.trim())
        // fixed script, the choices are passed as arguments
        Quickshell.execDetached(["kitty", "--title", "Refresh mirrors", "bash", "-c",
            'sudo cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak && '
          + 'sudo reflector --protocol https --country "$1" --latest "$2" --sort "$3" --save /etc/pacman.d/mirrorlist && '
          + 'echo && head -n 20 /etc/pacman.d/mirrorlist; echo; read -r -p "Done (old list: mirrorlist.bak). Press Enter to close." _',
            "bash", countries.trim(), latest, sort])
    }

    NetCard {
        Layout.fillWidth: true
        title: "Mirror list"
        icon: "󰒍"
        header: ActionButton { icon: "󰑓"; text: "Reload"; onClicked: page.load() }
        NetRow {
            first: true
            label: page.servers.length + " servers  ·  " + (page.ageDays < 0 ? "?" : page.ageDays === 0 ? "updated today" : "updated " + page.ageDays + " days ago")
            desc: (page.generated ? "generated " + page.generated + "  ·  " : "") + page.file
                  + (page.ageDays > 90 ? "\n󰀦 older than 3 months: mirrors may have gone away or got slow" : "")
        }
        Repeater {
            model: page.servers.slice(0, 8)
            NetRow {
                required property var modelData
                required property int index
                sub: true
                label: (index + 1) + ". " + modelData.replace(/\/\$repo.*$/, "")
            }
        }
        NetRow {
            visible: page.hasPacnew
            wide: true
            label: "mirrorlist.pacnew is waiting"
            desc: "the package shipped a new full list; refreshing with reflector below makes it unnecessary (you can delete the .pacnew then)"
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "Refresh with reflector"
        NetRow {
            first: true
            label: "Countries"
            desc: page.error !== "" ? page.error : "names or codes, separated by commas"
            SearchField {
                Layout.preferredWidth: 240
                icon: ""; clearable: false
                text: page.countries
                error: page.error.startsWith("countries")
                onTextEdited: page.countries = text
            }
        }
        NetRow {
            label: "Keep the"
            desc: "most recently synced mirrors, then sorted"
            RowLayout {
                spacing: 8
                SearchField { Layout.preferredWidth: 60; icon: ""; clearable: false; text: page.latest; onTextEdited: page.latest = text }
                Segmented {
                    small: true
                    options: [{ label: "fastest", value: "rate" }, { label: "best score", value: "score" }, { label: "newest", value: "age" }]
                    value: page.sort
                    onEdited: v => page.sort = v
                }
            }
        }
        NetRow {
            label: "Refresh"
            desc: "opens a terminal: sudo reflector (takes ~30 s for \"fastest\"); the current list is copied to mirrorlist.bak first"
            ActionButton { icon: "󰑓"; text: "Refresh…"; primary: true; onClicked: page.refresh() }
        }
    }
}
