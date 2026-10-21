import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import ".."
import "../network"

// One Jellyfin server of the bridge (jellyfin.servers): status, account,
// test, log in / out, and (when the bridge can) edit or remove it.
// Log in goes through the bridge (jellyfin.login): it stores only the token
// in the keyring. The password is in the field until "Log in" is pressed,
// then cleared; it's never saved, logged or shown.
ColumnLayout {
    id: row
    property var server: ({})
    property bool remoteOn: true
    property bool canManage: false
    property var stateLabels: ({})
    property var when: null

    Layout.fillWidth: true
    spacing: 0

    readonly property var status: server.status ?? null
    readonly property var details: status?.details ?? ({})
    readonly property string pstate: status?.state ?? (server.enabled === false ? "disabled" : "stopped")
    readonly property bool loggedIn: row.pstate === "running" || row.pstate === "degraded"
    property bool loginOpen: false
    property bool busy: false
    property string message: ""
    property bool messageError: false
    function say(text, isError) { row.message = text; row.messageError = isError }

    ConfirmArm { id: arm }

    NetRow {
        label: row.server.name + "  ·  " + (row.server.url ?? "")
        desc: !row.remoteOn ? "remote discovery is off"
            : (row.stateLabels[row.pstate] ?? row.pstate)
              + (row.details.user_name ? " · " + row.details.user_name + " on " + (row.details.server_name ?? "Jellyfin") + " " + (row.details.server_version ?? "") : "")
              + (row.status?.sessions !== undefined && row.pstate === "running" ? " · " + row.status.sessions + " session(s)" : "")
              + (row.status?.last_error && row.pstate !== "running" ? "\n" + MediaSources.errorText(row.status.last_error) : "")
        descError: row.remoteOn && (row.pstate === "degraded" || row.pstate === "error" || row.pstate === "unauthenticated")
        ActionButton {
            visible: row.remoteOn
            icon: "󰓅"; text: "Test"
            interactive: !row.busy
            onClicked: row.test()
        }
        ActionButton {
            visible: row.remoteOn && !row.loggedIn && !row.loginOpen && row.pstate !== "unauthenticated"     // else the form is open already
            icon: "󰍂"; text: "Log in"; primary: row.pstate === "unauthenticated"
            onClicked: row.loginOpen = true
        }
        ActionButton {
            visible: row.loggedIn
            icon: "󰍃"
            text: arm.armed === "logout" ? "Log out?" : "Log out"
            textColor: arm.armed === "logout" ? Colors.red : Colors.ink
            interactive: !row.busy
            onClicked: if (arm.confirm("logout")) row.logout()
        }
    }

    // log in
    NetRow {
        visible: row.loginOpen || (row.remoteOn && row.pstate === "unauthenticated")
        sub: true
        wide: true
        label: "Log in to " + row.server.name
        desc: "Your Jellyfin account. The password is sent once to the bridge, which keeps only an access token in your keyring."
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            SearchField {
                id: user
                Layout.fillWidth: true
                icon: "󰀄"
                placeholderText: "User name"
                // once: a binding would overwrite what's typed on every status update
                Component.onCompleted: text = row.details.user_name ?? ""
                onAccepted: pw.forceActiveFocus()
            }
            SearchField {
                id: pw
                Layout.fillWidth: true
                icon: "󰌾"
                password: true
                placeholderText: "Password"
                onAccepted: row.login()
            }
            ActionButton {
                icon: "󰍂"; text: row.busy ? "Logging in…" : "Log in"; primary: true
                interactive: !row.busy && user.text.trim() !== ""
                onClicked: row.login()
            }
            ActionButton {
                visible: row.loginOpen
                text: "Cancel"
                onClicked: { pw.text = ""; row.loginOpen = false }
            }
        }
    }

    // edit / remove (only when the bridge has the API for it)
    NetRow {
        visible: row.canManage
        sub: true
        label: "Address"
        desc: MediaSources.serverUrl(url.text) || "Changing it keeps the login only if it's the same server"
        descError: MediaSources.serverUrl(url.text) !== ""
        SearchField {
            id: url
            Layout.preferredWidth: 260
            icon: "󰖟"
            clearable: false
            Component.onCompleted: text = row.server.url ?? ""
        }
        ActionButton {
            visible: url.text.trim() !== (row.server.url ?? "")
            icon: "󰆓"; text: "Save"
            interactive: !row.busy && MediaSources.serverUrl(url.text) === ""
            onClicked: {
                row.busy = true
                MediaSync.updateServer({ name: row.server.name, url: url.text.trim() }, (err, res) => {
                    row.busy = false
                    row.say(err ? MediaSources.errorText(err) : "Saved", !!err)
                })
            }
        }
        ActionButton {
            icon: "󰆴"
            text: arm.armed === "remove" ? "Remove?" : "Remove"
            textColor: arm.armed === "remove" ? Colors.red : Colors.ink
            interactive: !row.busy
            onClicked: if (arm.confirm("remove")) {
                row.busy = true
                MediaSync.removeServer(row.server.name, err => { row.busy = false; if (err) row.say(MediaSources.errorText(err), true) })
            }
        }
    }

    NetRow {
        visible: row.message !== ""
        sub: true
        label: row.messageError ? "Didn't work" : "Done"
        desc: row.message
        descError: row.messageError
    }

    function login() {
        if (row.busy || user.text.trim() === "") return
        const name = user.text.trim(), secret = pw.text
        pw.text = ""                                   // gone from the UI before anything else happens
        row.busy = true
        row.say("", false)
        MediaSync.login(row.server.name, name, secret, (err, res) => {
            row.busy = false
            if (err) { row.say(MediaSources.errorText(err), true); return }
            row.loginOpen = false
            row.say("Logged in as " + (res.user_name ?? name) + " on " + (res.server_name ?? "Jellyfin") + " " + (res.server_version ?? "")
                    + " · token stored in " + (res.credential_backend ?? "the keyring"), false)
        })
    }

    function logout() {
        row.busy = true
        MediaSync.logout(row.server.name, (err, res) => {
            row.busy = false
            if (err) { row.say(MediaSources.errorText(err), true); return }
            row.say((res.revoked ? "Token revoked on the server" : "The server couldn't be told (offline?)")
                    + (res.credential_deleted ? ", deleted from the keyring" : "") + (res.detail ? " · " + res.detail : ""), false)
        })
    }

    // with jellyfin.test: the address itself; otherwise the bridge's own last contact with the server
    function test() {
        row.busy = true
        row.say("Testing…", false)
        if (MediaSync.hasMethod("jellyfin.test")) {
            MediaSync.testServer(row.server.url, (err, res) => {
                row.busy = false
                row.say(err ? MediaSources.errorText(err) : "Reachable: " + (res.server_name ?? "Jellyfin") + " " + (res.server_version ?? ""), !!err)
            })
            return
        }
        MediaSync.request("providers.status", {}, (err, res) => {
            row.busy = false
            if (err) { row.say(MediaSources.errorText(err), true); return }
            MediaSync.providers = res.providers ?? []
            const p = (res.providers ?? []).find(x => x.instance === row.server.instance)
            if (!p) { row.say("The bridge doesn't run this server (disabled, or remote discovery off)", true); return }
            if (p.state === "running")
                row.say("Reachable: " + (p.details?.server_name ?? "Jellyfin") + " " + (p.details?.server_version ?? "")
                        + ", logged in as " + (p.details?.user_name ?? "?") + " · last answer " + (row.when ? row.when(p.last_success) : ""), false)
            else
                row.say((row.stateLabels[p.state] ?? p.state) + (p.last_error ? ": " + MediaSources.errorText(p.last_error) : ""), true)
        })
    }
}
