import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Settings → Apps → Servers (the Servers app, modules/servers). Every setting
// here is this device's own (~/.local/state/quickshell/servers-app.json via
// ServerStore.setPref): it never goes into settings.json, exports or profiles.
ColumnLayout {
    id: page
    spacing: Tokens.space.s16

    property bool scriptOk: false
    property string terminal: ""
    function checkScript() { Jobs.run(["test", "-x", ServerStore.script], code => page.scriptOk = code === 0) }
    Component.onCompleted: { checkScript(); DefaultApps.terminalApp(a => page.terminal = a) }

    Section {
        Layout.fillWidth: true
        title: "Servers"
        icon: "󰒋"
        header: ActionButton { icon: "󰒋"; text: "Open Servers"; onClicked: Panels.call("servers", "open") }
        SettingRow {
            first: true
            wide: true
            label: ServerStore.active.length + (ServerStore.active.length === 1 ? " server" : " servers") + (ServerStore.archived.length ? " (+" + ServerStore.archived.length + " archived)" : "")
                   + "  ·  " + ServerStore.groups.length + " groups"
            desc: "Everything about them lives in servers.json next to manage-svs.sh, on this device only (the settings below too). To bring them to another device: Export here, Import there."
            ActionButton { icon: "󰈝"; text: "Export…"; onClicked: Panels.call("servers", "transfer", "export") }
            ActionButton { icon: "󰋺"; text: "Import…"; onClicked: Panels.call("servers", "transfer", "import") }
        }
    }

    Section {
        Layout.fillWidth: true
        title: "Automatic scans"
        icon: "󰑓"
        SettingRow {
            first: true
            label: "This device scans automatically"
            desc: "a minute after the shell starts (unless the last scan is under 30 min old), then regularly; turn it off on a device that shouldn't (e.g. the laptop)"
            ToggleSwitch { checked: ServerRuns.autoScan; onToggled: v => ServerStore.setPref("autoScan", v) }
        }
        SettingRow {
            label: "Every"
            desc: "hours between scans (each scan also runs the health checks)"
            NumberField { from: 1; to: 48; value: ServerRuns.scanHours; onEdited: v => ServerStore.setPref("scanHours", Math.round(v)) }
        }
        SettingRow {
            label: "Notifications"
            desc: "when a scan finds something critical that wasn't there before (security updates, a reboot needed) — with Show / Update critical — and when an update finishes"
            ToggleSwitch { checked: ServerRuns.notifyOn; onToggled: v => ServerStore.setPref("notify", v) }
        }
        SettingRow {
            label: "Updates at boot"
            desc: "once after you log in: what the servers have waiting (also in Settings → Notifications)"
            ToggleSwitch { checked: ServerRuns.bootNotify; onToggled: v => ServerStore.setPref("bootNotify", v) }
        }
        SettingRow {
            label: "Notify again about everything critical now"
            desc: "forgets what it already told you"
            ActionButton { icon: "󰂚"; text: "Remind me"; onClicked: { ServerStore.setPref("seenCritical", {}); ServerRuns.checkCritical() } }
        }
    }

    Section {
        Layout.fillWidth: true
        title: "Updates"
        icon: "󰚰"
        SettingRow {
            first: true
            label: "Reboots"
            desc: "the default in the update confirmation; Proxmox hosts and servers marked \"never reboot\" are never rebooted automatically"
            Segmented {
                small: true
                options: [{ label: "Don't reboot", value: "none" }, { label: "Reboot when needed", value: "auto" }]
                value: ServerStore.prefs.rebootMode === "auto" ? "auto" : "none"
                onEdited: v => ServerStore.setPref("rebootMode", v)
            }
        }
        SettingRow {
            label: "Ask me when something goes wrong"
            desc: ServerRuns.askOnFailure ? "a failed check after an update, a snapshot that can't be taken, a failed server before the next wave: the update waits and asks (panel + notification), with the reason and the choices (roll back / keep / skip)"
                                          : "nobody is asked: svs.conf decides (AUTO_ROLLBACK, SNAPSHOT_REQUIRED, STOP_ON_FAILURE), like the nightly cron run"
            ToggleSwitch { checked: ServerRuns.askOnFailure; onToggled: v => ServerStore.setPref("askOnFailure", v) }
        }
        SettingRow {
            visible: ServerRuns.askOnFailure
            label: "Wait for my answer"
            desc: "minutes; after that svs.conf decides, so an update never hangs forever"
            NumberField { from: 1; to: 240; value: ServerRuns.askMinutes; onEdited: v => ServerStore.setPref("askMinutes", Math.round(v)) }
        }
        SettingRow {
            label: "Proxmox snapshots before updating"
            desc: "a snapshot of each Proxmox guest (VM / LXC) right before its update. Keep: a rollback point, deleted after SNAPSHOT_KEEP_DAYS · Delete after success: removed again once the update and its checks passed. The default of the update confirmation (changeable there per run)"
            Segmented {
                small: true
                options: [{ label: "Off", value: "off" }, { label: "Keep", value: "keep" }, { label: "Delete after success", value: "drop" }]
                value: ServerStore.snapshotMode
                onEdited: v => ServerStore.setPref("snapshots", v)
            }
        }
        SettingRow {
            visible: ServerStore.snapshotMode !== "off"
            label: "If a snapshot can't be taken"
            desc: "Skip: the server isn't updated (svs.conf SNAPSHOT_REQUIRED) · Update anyway: without a rollback point (e.g. while its Proxmox host is unreachable)"
            Segmented {
                small: true
                options: [{ label: "Skip the server", value: "skip" }, { label: "Update anyway", value: "update" }]
                value: ServerStore.snapshotFail
                onEdited: v => ServerStore.setPref("snapshotFail", v)
            }
        }
    }

    // what the script does when nobody decides (these win over svs.conf)
    Section {
        Layout.fillWidth: true
        title: "When nobody decides"
        icon: "󰒓"
        SettingRow {
            first: true
            label: "Something broke after an update"
            desc: (ServerRuns.askOnFailure ? "when you don't answer in time (and for runs outside the app): " : "")
                  + (ServerStore.policy.autoRollback === "none" ? "left as it is, reported as failed"
                   : ServerStore.policy.autoRollback === "snapshot" ? "the whole server goes back to its snapshot (containers only, where there is none)"
                   : "the updated containers go back to their previous images; packages stay")
                  + ". Only when the update touched what broke: anything else is \"needs a look\", never rolled back"
            wide: true
            Segmented {
                small: true
                options: [{ label: "Leave it", value: "none" }, { label: "Roll back the containers", value: "containers" }, { label: "Roll back to the snapshot", value: "snapshot" }]
                value: ServerStore.policy.autoRollback
                onEdited: v => ServerStore.setPolicy("autoRollback", v)
            }
        }
        SettingRow {
            label: "A server failed"
            desc: ServerStore.policy.stopOnFailure ? "the servers of the next waves aren't started (the ones running finish)" : "the next waves go on anyway"
            Segmented {
                small: true
                options: [{ label: "Stop before the next wave", value: "stop" }, { label: "Go on", value: "go" }]
                value: ServerStore.policy.stopOnFailure ? "stop" : "go"
                onEdited: v => ServerStore.setPolicy("stopOnFailure", v === "stop")
            }
        }
        SettingRow {
            label: "Servers at once"
            desc: "over all runs that are going, not per run"
            NumberField { from: 1; to: 16; value: ServerStore.policy.maxParallel; onEdited: v => ServerStore.setPolicy("maxParallel", Math.round(v)) }
        }
        SettingRow {
            label: "Keep update snapshots"
            desc: "days; older ones of this tool (svsupd_…) are deleted after a successful update of that guest. Never your own snapshots"
            NumberField { from: 0; to: 90; value: ServerStore.policy.snapshotKeepDays; onEdited: v => ServerStore.setPolicy("snapshotKeepDays", Math.round(v)) }
        }
        SettingRow {
            label: "Keep old container images"
            desc: "days; what a container rollback needs (svs-rollback/…)"
            NumberField { from: 0; to: 90; value: ServerStore.policy.rollbackKeepDays; onEdited: v => ServerStore.setPolicy("rollbackKeepDays", Math.round(v)) }
        }
        SettingRow {
            wide: true
            label: "Timeouts and ntfy"
            desc: "stay in svs.conf in the data folder (VERIFY_TIMEOUT, REBOOT_WAIT_TIMEOUT, NOTIFY_URL, NOTIFY_TOKEN, …): scripts/servers/svs.conf.sample lists them all"
        }
    }

    // every server and how it updates: what the confirmation preselects (here), and its
    // own rules in words (changed in its editor)
    Section {
        Layout.fillWidth: true
        title: "Every server, and how it updates"
        icon: "󰒆"
        SettingRow {
            first: true
            label: "Every server, unless set below"
            desc: ServerStore.updateDefault === "pending" ? "What's pending: everything on servers where the last scan found something, the rest skipped"
                : ServerStore.updateDefault === "skip" ? "nothing preselected: you tick what to update each time"
                : ServerStore.choiceLabel(ServerStore.updateDefault) + " on every reachable server"
            Segmented {
                small: true
                options: [{ label: "What's pending", value: "pending" }].concat(ServerStore.updateChoices.map(o => ({ label: o.label, value: o.value })))
                value: ServerStore.updateDefault
                onEdited: v => ServerStore.setPref("updateDefault", v)
            }
        }
        Repeater {
            model: ServerStore.active
            SettingRow {
                id: per
                required property var modelData
                readonly property string own: ServerStore.updatePerOf(modelData.name)
                label: modelData.name
                desc: (own ? "" : "the default above (" + ServerStore.choiceLabel(ServerStore.updateDefault).toLowerCase() + ")  ·  ") + ServerStore.howItUpdates(modelData)
                wide: true
                ActionButton { variant: "ghost"; icon: "󰏫"; text: "Its rules…"; tooltip: "Containers, reboot, snapshot and wave of " + modelData.name + ", in its editor"
                               onClicked: Panels.call("servers", "edit", modelData.name) }
                Segmented {
                    small: true
                    options: [{ label: "Default", value: "" }, { label: "Pending", value: "pending" }].concat(ServerStore.updateChoices.map(o => ({ label: o.label, value: o.value })))
                    value: per.own
                    onEdited: v => ServerStore.setUpdatePer(per.modelData.name, v)
                }
            }
        }
        SettingRow {
            wide: true
            label: "Servers that can't be reached are always skipped"
            desc: "and \"Save as defaults\" in the update confirmation writes these choices too"
        }
    }

    Section {
        Layout.fillWidth: true
        title: "Script and apps"
        icon: "󰆍"
        SettingRow {
            first: true
            label: "Data folder"
            desc: page.scriptOk ? "your servers, their settings, logs and reports (this device only, never synced): " + ServerStore.dataDir
                                : "the program is missing: " + ServerStore.script
            SearchField {
                Layout.preferredWidth: 280
                icon: "󰉋"; clearable: false
                placeholderText: ServerStore.home + "/.local/share/quickshell/servers"
                text: ServerStore.prefs.dataDir ?? ""
                onAccepted: { ServerStore.setPref("dataDir", text.trim().replace(/\/+$/, "")); page.checkScript() }
            }
        }
        SettingRow {
            label: "Terminal for SSH"
            desc: (page.terminal ? DefaultApps.name(page.terminal) : "not set (kitty)") + "  ·  the default terminal"
            ActionButton { icon: "󰀻"; text: "Default apps"; onClicked: Panels.call("settings", "openPage", "defaultapps") }
        }
        SettingRow {
            label: "Files for SFTP"
            desc: "the default file manager (Default apps → File manager): the shell's Files app connects directly, others get an sftp:// address"
            ActionButton { icon: "󰀻"; text: "Default apps"; onClicked: Panels.call("settings", "openPage", "defaultapps") }
        }
    }
}
