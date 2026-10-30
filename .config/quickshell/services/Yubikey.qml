pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// YubiKey login (scripts/postinstall/yubikey.sh in the dotfiles sets it up).
//   mode     what the key does for this user: "none", "otp" (pam_yubico: the key
//            types a code into the password field) or "fido2" (pam_u2f: a touch).
//            From system-auth's auth lines + the user's line in the module's mappings,
//            the same rules as the script's status; OTP and FIDO2 at once (set up by
//            hand) counts as "otp": the typed field covers both then.
//   present  mode !== "none"
// The lockscreen re-checks on every lock (refresh()); the login screen gets it
// through GreeterSync. Read straight from the files (no repo, no process), so a
// lock never depends on the dotfiles being there.
//
//   status   the script's `--status --json` (settings app → YubiKey), null until
//            loaded: { mode, packages, keyPresent, serials, pin, linked { fido2, otp },
//            polkit { fido2, otp }, failures, backups, origin, user, warnings }.
//            Never has the OTP API key or a key handle in it.
//   setup()  the script in kitty; status and mode are read again when it closes
Singleton {
    id: root

    property string mode: "none"
    readonly property bool present: mode !== "none"

    function refresh() {
        const auth = Files.read("/etc/pam.d/system-auth").split("\n")
            .filter(l => /^\s*-?auth\s/.test(l))
        const user = Quickshell.env("USER") ?? ""
        const home = Quickshell.env("HOME") ?? ""
        // the module's authfile=, else its default (pam_yubico / pam_u2f without one)
        const linked = (line, def) => {
            const file = (/authfile=(\S+)/.exec(line) ?? [])[1] ?? def
            return Files.read(file).split("\n").some(l => l.split(":")[0] === user && l.split(":").length > 1)
        }
        const otp = auth.find(l => /pam_yubico\.so/.test(l))
        const u2f = auth.find(l => /pam_u2f\.so/.test(l))
        mode = otp && linked(otp, home + "/.yubico/authorized_yubikeys") ? "otp"
             : u2f && linked(u2f, home + "/.config/Yubico/u2f_keys") ? "fido2" : "none"
    }
    Component.onCompleted: refresh()

    // ── the setup script's view (settings app) ──
    readonly property string script: Dotfiles.repo + "/scripts/postinstall/yubikey.sh"
    property var status: null
    property string statusError: ""
    readonly property bool loading: Jobs.isRunning("yubikey-status")
    readonly property bool settingUp: Jobs.isRunning("yubikey-setup")

    function loadStatus() {
        if (loading) return
        let out = ""
        Jobs.start("yubikey-status", ["bash", script, "--status", "--json"], {
            timeout: 20000, store: false,
            onLine: (text, isErr) => { if (!isErr) out += text + "\n" },
            onExit: code => {
                if (code === 127 || !Files.read(script)) { statusError = "yubikey.sh not found: " + script; status = null; return }
                try { status = JSON.parse(out); statusError = "" }
                catch (e) { statusError = "yubikey.sh --status --json gave no status (exit " + code + ")"; status = null }
            }
        })
    }

    // the script in a terminal (like the settings app's other terminal tools: a fixed
    // script, the path as an argument); read everything again when it's closed
    function setup() {
        if (settingUp) return
        Jobs.start("yubikey-setup", ["kitty", "--title", "YubiKey login", "bash", "-c",
            'bash "$1"\necho; read -r -p "Done. Press Enter to close." _', "bash", script], {
            store: false,
            onExit: () => { refresh(); loadStatus() }
        })
    }
}
