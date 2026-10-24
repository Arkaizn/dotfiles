pragma ComponentBehavior: Bound
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import "network"

// Login screen page (greetd + greeter/): whether it's installed and its theme
// copy up to date (GreeterSync), what it shows — the same as the lockscreen
// by default (LockItems.greeterItems / resolveGreeter) — and the default user
// and session.
//   Settings.greeter: { follow, sessionPicker, userPicker, sync, defaultUser,
//                       defaultSession, + with follow off: seconds, date, hint,
//                       avatar, batteries, power, blur, monitors }
ColumnLayout {
    id: page
    spacing: 16

    readonly property var cfg: Settings.greeter
    readonly property var show: LockItems.resolveGreeter(Settings.lockscreen, cfg)
    function setKey(key, v, def) { v === def ? Settings.reset("greeter", key) : Settings.set("greeter", key, v) }

    // ── the code installed vs. this config's (greeter/build.sh prints its hash) ──
    property string builtVersion: ""
    readonly property string installedVersion: GreeterSync.installedVersion
    function checkVersion() {
        const out = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/quickshell-greeter-check"
        Jobs.run(["bash", Quickshell.shellDir + "/greeter/build.sh", out], (code, o) => page.builtVersion = code === 0 ? o.trim() : "")
        GreeterSync.readVersion()
    }

    // users and sessions for the defaults
    readonly property var users: GreeterLib.users(Files.read("/etc/passwd"))
    property var sessions: []
    function loadSessions() {
        Jobs.run(["sh", "-c", "ls /usr/share/wayland-sessions/*.desktop 2>/dev/null"], (code, out) => {
            page.sessions = out.split("\n").filter(f => f !== "").map(f =>
                GreeterLib.parseDesktop(f.replace(/^.*\//, "").replace(/\.desktop$/, ""), Files.read(f))).filter(s => s !== null)
        })
    }

    Component.onCompleted: { checkVersion(); loadSessions(); Monitors.refresh() }

    NetCard {
        Layout.fillWidth: true
        title: "Login screen"
        icon: "󰍂"

        NetRow {
            first: true
            label: "Installed"
            desc: GreeterSync.installed
                ? (page.installedVersion === "" ? "Theme folder there, no greeter code installed"
                   : page.builtVersion !== "" && page.builtVersion !== page.installedVersion
                     ? "Older than this config (" + page.installedVersion + " → " + page.builtVersion + "): run the install command below again"
                     : "Up to date (" + page.installedVersion + ")")
                : "Not yet. greetd still logs you in straight away"
            descError: GreeterSync.installed && page.builtVersion !== "" && page.installedVersion !== "" && page.builtVersion !== page.installedVersion
        }
        NetRow {
            label: "Install / update"
            desc: "In a terminal (sudo): sudo ~/.config/quickshell/greeter/install.sh — see greeter/RECOVERY.md for how to get back from a TTY"
        }
        NetRow {
            label: "Theme copy"
            desc: GreeterSync.status === "up to date" ? "Up to date (last written " + GreeterSync.lastSync + ")"
                : GreeterSync.status === "off" ? "Not kept up to date (switched off below)"
                : GreeterSync.status === "not installed" ? "/var/lib/quickshell-greeter isn't there yet (install creates it)"
                : GreeterSync.status
            descError: GreeterSync.status.startsWith("failed")
            ActionButton {
                icon: "󰑐"
                text: "Update now"
                interactive: GreeterSync.status !== "updating" && GreeterSync.installed && page.show.sync
                onClicked: GreeterSync.sync()
            }
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "What it shows"
        icon: "󰈈"

        NetRow {
            readonly property var item: LockItems.greeterItems.find(i => i.key === "follow")
            first: true
            label: item.label
            desc: item.desc
            changed: !page.show.follow
            ToggleSwitch {
                checked: page.show.follow
                onToggled: v => page.setKey("follow", v, true)
            }
        }

        // its own items (follow off): the lockscreen's, minus what needs a session
        Repeater {
            model: page.show.follow ? [] : LockItems.items.filter(it => LockItems.greeterShared.includes(it.key))
            NetRow {
                id: ownRow
                required property var modelData
                sub: true
                label: modelData.label
                desc: modelData.desc
                changed: page.show[modelData.key] !== modelData.def
                ToggleSwitch {
                    checked: page.show[ownRow.modelData.key] === true
                    onToggled: v => page.setKey(ownRow.modelData.key, v, ownRow.modelData.def)
                }
            }
        }
        NetRow {
            visible: !page.show.follow
            sub: true
            label: "Monitor"
            desc: "The others show the blurred wallpaper"
            DropdownControl {
                implicitWidth: 260
                options: [{ label: "All monitors", value: "" }].concat(Monitors.outputs.map(o => ({ label: o.ident.replace(/ Unknown$/, "") + "  (" + o.name + ")", value: o.ident })))
                value: page.show.monitors[0] ?? ""
                onEdited: v => v === "" ? Settings.reset("greeter", "monitors") : Settings.set("greeter", "monitors", [v])
            }
        }
        NetRow {
            visible: page.show.follow
            sub: true
            label: "Monitor"
            desc: page.show.monitors.length === 0 ? "All monitors, as the lockscreen (Settings → Lockscreen)"
                : "As the lockscreen: " + page.show.monitors.map(m => m.replace(/ Unknown$/, "")).join(", ")
        }
        Repeater {
            model: LockItems.greeterItems.filter(i => i.key !== "follow")
            NetRow {
                id: itemRow
                required property var modelData
                label: modelData.label
                desc: modelData.desc
                changed: page.show[modelData.key] !== modelData.def
                ToggleSwitch {
                    visible: itemRow.modelData.kind === "bool"
                    checked: page.show[itemRow.modelData.key] === true
                    onToggled: v => page.setKey(itemRow.modelData.key, v, itemRow.modelData.def)
                }
                DropdownControl {
                    visible: itemRow.modelData.kind === "choice"
                    implicitWidth: 160
                    options: itemRow.modelData.choices ?? []
                    value: page.show[itemRow.modelData.key]
                    onEdited: v => page.setKey(itemRow.modelData.key, v, itemRow.modelData.def)
                }
            }
        }
    }

    NetCard {
        Layout.fillWidth: true
        title: "Defaults"
        icon: "󰀄"

        NetRow {
            first: true
            label: "User"
            desc: "Who's picked when the login screen starts"
            changed: page.show.defaultUser !== ""
            DropdownControl {
                implicitWidth: 220
                options: [{ label: "The last one (else you)", value: "" }].concat(page.users.map(u => ({ label: u.gecos ? u.gecos + " (" + u.name + ")" : u.name, value: u.name })))
                value: page.show.defaultUser
                onEdited: v => page.setKey("defaultUser", v, "")
            }
        }
        NetRow {
            label: "Session"
            desc: "Started after logging in, unless you pick another one"
            changed: page.show.defaultSession !== ""
            DropdownControl {
                implicitWidth: 220
                options: [{ label: "The last one used", value: "" }].concat(page.sessions.map(s => ({ label: s.name, value: s.id })))
                value: page.show.defaultSession
                onEdited: v => page.setKey("defaultSession", v, "")
            }
        }
    }
}
