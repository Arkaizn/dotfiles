import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Form for one connection (new or existing). Checks every field before it
// saves; a keyring password is stored with secret-tool, never in settings.
ColumnLayout {
    id: ed
    property var conn: null                 // null = new
    signal done()

    readonly property bool isNew: conn === null
    property string cid: conn?.id ?? RemoteConnections.newId()
    property string name: conn?.name ?? ""
    property string type: conn?.type ?? "ssh"
    property string host: conn?.host ?? ""
    property string port: String(conn?.port ?? "")
    property string user: conn?.user ?? ""
    property string password: conn?.password ?? "none"
    property bool clipboard: conn?.clipboard ?? true
    property bool dynres: conn?.dynres ?? true
    property bool shareHome: conn?.shareHome ?? false
    property bool ignoreCert: conn?.ignoreCert ?? false
    property string extra: (conn?.extra ?? []).join(" ")

    property var errors: ({})
    property string message: ""
    property bool inKeyring: false
    property string newPassword: ""

    Component.onCompleted: if (!isNew && password === "keyring") RemoteConnections.hasPassword(cid, has => ed.inKeyring = has)

    function draft() {
        return {
            id: cid, name: name, type: type, host: host.trim(),
            port: port.trim() === "" ? RemoteConnections.types[type].port : Number(port.trim()),
            user: user.trim(), password: type === "rdp" ? password : "none",
            clipboard: clipboard, dynres: dynres, shareHome: shareHome, ignoreCert: ignoreCert,
            extra: type === "rdp" ? extra.split(/\s+/).filter(x => x !== "") : [],
            lastUsed: conn?.lastUsed ?? 0
        }
    }

    function save() {
        const d = draft()
        const e = RemoteConnections.validate(Object.assign({}, d, { port: port.trim() === "" ? undefined : port.trim() }))
        if (d.password === "keyring" && !inKeyring && newPassword === "") e.password = "enter the password to store in the keyring"
        errors = e
        if (Object.keys(e).length > 0) { message = "Check the marked fields"; return }
        const finish = () => {
            RemoteConnections.put(d)
            // switched away from the keyring: remove what was stored
            if (!isNew && conn.password === "keyring" && d.password !== "keyring") RemoteConnections.clearPassword(cid, () => {})
            ed.done()
        }
        if (d.password === "keyring" && newPassword !== "") {
            message = "Storing the password…"
            RemoteConnections.setPassword(cid, d.name, newPassword, (ok, err) => {
                ed.newPassword = ""
                if (ok) finish()
                else ed.message = "The keyring refused the password" + (err ? ": " + err : "") + " (nothing saved)"
            })
        } else finish()
    }

    spacing: 0

    NetRow {
        first: true
        label: "Name"
        desc: ed.errors.name ?? ""
        SearchField {
            Layout.preferredWidth: 280
            icon: ""; clearable: false
            text: ed.name
            error: ed.errors.name !== undefined
            onTextEdited: ed.name = text
        }
    }
    NetRow {
        label: "Type"
        Segmented {
            small: true
            options: [{ label: "SSH", value: "ssh" }, { label: "RDP", value: "rdp" }, { label: "VNC", value: "vnc" }]
            value: ed.type
            onEdited: v => ed.type = v
        }
    }
    NetRow {
        label: "Host"
        desc: ed.errors.host ?? (ed.type === "ssh" ? "a name, IP or an alias from ~/.ssh/config" : "name or IP address")
        SearchField {
            Layout.preferredWidth: 280
            icon: ""; clearable: false
            text: ed.host
            placeholderText: ed.type === "ssh" ? "server or ssh alias" : "192.168.0.10"
            error: ed.errors.host !== undefined
            onTextEdited: ed.host = text
        }
    }
    NetRow {
        label: "Port"
        desc: ed.errors.port ?? ("empty = " + RemoteConnections.types[ed.type].port)
        SearchField {
            Layout.preferredWidth: 120
            icon: ""; clearable: false
            text: ed.port
            placeholderText: String(RemoteConnections.types[ed.type].port)
            error: ed.errors.port !== undefined
            onTextEdited: ed.port = text
        }
    }
    NetRow {
        visible: ed.type !== "vnc"
        label: "User"
        desc: ed.errors.user ?? (ed.type === "ssh" ? "empty = from ~/.ssh/config or your login name" : "DOMAIN\\user works too")
        SearchField {
            Layout.preferredWidth: 280
            icon: ""; clearable: false
            text: ed.user
            error: ed.errors.user !== undefined
            onTextEdited: ed.user = text
        }
    }

    // ── RDP ─────────────────────────────────────────────────────────────────
    NetRow {
        visible: ed.type === "rdp"
        label: "Password"
        desc: ed.errors.password ?? (ed.password === "keyring" ? (ed.inKeyring ? "stored in the keyring; type a new one to replace it" : "stored in the keyring (secret-tool)")
                                    : ed.password === "ask" ? "a prompt on every connect" : "the server asks, or no password")
        Segmented {
            small: true
            options: [{ label: "None", value: "none" }, { label: "Ask", value: "ask" }, { label: "Keyring", value: "keyring" }]
            value: ed.password
            onEdited: v => ed.password = v
        }
    }
    NetRow {
        visible: ed.type === "rdp" && ed.password === "keyring"
        sub: true
        label: ed.inKeyring ? "New password" : "Password"
        desc: "Never written to the settings file"
        SearchField {
            Layout.preferredWidth: 280
            icon: "󰌋"
            password: true
            text: ed.newPassword
            placeholderText: ed.inKeyring ? "unchanged" : ""
            error: ed.errors.password !== undefined
            onTextEdited: ed.newPassword = text
        }
    }
    NetRow {
        visible: ed.type === "rdp"
        label: "Shared clipboard"
        ToggleSwitch { checked: ed.clipboard; onToggled: v => ed.clipboard = v }
    }
    NetRow {
        visible: ed.type === "rdp"
        label: "Resize with the window"
        desc: "+dynamic-resolution"
        ToggleSwitch { checked: ed.dynres; onToggled: v => ed.dynres = v }
    }
    NetRow {
        visible: ed.type === "rdp"
        label: "Share my home folder"
        desc: "the server sees ~ as a drive called \"home\""
        ToggleSwitch { checked: ed.shareHome; onToggled: v => ed.shareHome = v }
    }
    NetRow {
        visible: ed.type === "rdp"
        label: "Ignore certificate"
        desc: "/cert:ignore: no check of the server's identity (only on networks you trust)"
        ToggleSwitch { checked: ed.ignoreCert; onToggled: v => ed.ignoreCert = v }
    }
    NetRow {
        visible: ed.type === "rdp"
        wide: true
        label: "More xfreerdp3 arguments"
        desc: ed.errors.extra ?? "separated by spaces, e.g. /ipv4 /sec:tls /size:1920x1080"
        SearchField {
            Layout.fillWidth: true
            icon: ""; clearable: false
            text: ed.extra
            error: ed.errors.extra !== undefined
            onTextEdited: ed.extra = text
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.margins: 14
        spacing: 8
        Text {
            Layout.fillWidth: true
            text: ed.message
            color: ed.message.startsWith("Storing") ? Qt.rgba(1, 1, 1, 0.6) : "#f38ba8"
            font.pixelSize: 11
            font.family: Properties.fontFamily
            wrapMode: Text.Wrap
        }
        ActionButton { text: "Cancel"; onClicked: ed.done() }
        ActionButton { icon: "󰆓"; text: ed.isNew ? "Add" : "Save"; primary: true; onClicked: ed.save() }
    }
}
