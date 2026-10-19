pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services.lib

// SSH and GPG overview (settings app → Developer → SSH & GPG). Read-only,
// plus: copy a *public* key, remove a host from known_hosts (ssh-keygen -R,
// which keeps known_hosts.old), and make a new SSH key in a terminal.
// Private keys are never shown or copied; for "has a passphrase" only the exit
// code of `ssh-keygen -y -P ""` is used (its output is thrown away).
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string sshDir: home + "/.ssh"
    readonly property string agentSock: Quickshell.env("SSH_AUTH_SOCK") ?? ""

    // [{ name, pub, type, bits, fingerprint, comment, hasPrivate, mode, passphrase: true|false|null (unknown) }]
    property var sshKeys: []
    property string sshDirMode: ""
    property var agentKeys: []             // fingerprints loaded in the agent
    property bool agentUp: false
    property int knownHosts: 0
    property var sshHosts: []
    // [{ keyid, fpr, uid, created, expires, expired, soon, secret, caps }]
    property var gpgKeys: []
    property string gitSigningKey: ""
    property bool gitSign: false
    property bool loading: false

    function refresh() {
        loading = true
        // .pub files: fingerprint line + mode of the private key next to it (if any)
        Jobs.run(["sh", "-c",
                  'd=$1; printf "DIR %s\\n" "$(stat -c %a "$d" 2>/dev/null)"\n'
                + 'for p in "$d"/*.pub; do [ -f "$p" ] || continue; k=${p%.pub}\n'
                + '  m=-; [ -f "$k" ] && m=$(stat -c %a "$k")\n'
                // too-open permissions: ssh-keygen refuses to read it at all → unknown
                + '  pp=-; [ -f "$k" ] && { if e=$(ssh-keygen -y -P "" -f "$k" 2>&1 >/dev/null); then pp=no; else case $e in *UNPROTECTED*|*"bad permissions"*) pp=unknown ;; *) pp=yes ;; esac; fi; }\n'
                + '  printf "KEY %s\\t%s\\t%s\\t%s\\n" "$p" "$m" "$pp" "$(ssh-keygen -lf "$p" 2>/dev/null)"\n'
                + 'done\n'
                + '[ -f "$d/known_hosts" ] && printf "KNOWN %s\\n" "$(grep -cv "^#" "$d/known_hosts")"', "sh", sshDir], (code, out) => {
            const keys = []
            for (const l of out.split("\n")) {
                let m
                if ((m = /^DIR (\d*)$/.exec(l))) sshDirMode = m[1]
                else if ((m = /^KNOWN (\d+)$/.exec(l))) knownHosts = Number(m[1])
                else if ((m = /^KEY ([^\t]+)\t(\S+)\t(\S+)\t(\d+) (\S+) (.*) \((\S+)\)$/.exec(l)))
                    keys.push({ pub: m[1], name: m[1].replace(/.*\//, "").replace(/\.pub$/, ""), hasPrivate: m[2] !== "-", mode: m[2],
                                passphrase: m[3] === "yes" ? true : m[3] === "no" ? false : null, bits: Number(m[4]), fingerprint: m[5], comment: m[6], type: m[7] })
            }
            sshKeys = keys
            loading = false
        })
        if (agentSock !== "")
            Jobs.run(["ssh-add", "-l"], (code, out) => {
                agentUp = code === 0 || code === 1          // 1 = agent up, no keys
                agentKeys = code === 0 ? out.split("\n").map(l => l.split(" ")[1]).filter(x => x) : []
            })
        else { agentUp = false; agentKeys = [] }
        sshHosts = RemoteConnections.parseSshConfig(Files.read(sshDir + "/config")).map(r => r.conn.host)

        Jobs.run(["gpg", "--list-keys", "--with-colons", "--fixed-list-mode"], (code, out) => {
            Jobs.run(["gpg", "--list-secret-keys", "--with-colons", "--fixed-list-mode"], (code2, out2) => {
                const secret = out2.split("\n").filter(l => l.startsWith("fpr:")).map(l => l.split(":")[9])
                gpgKeys = parseGpg(out, secret)
            })
        })
        Jobs.run(["git", "config", "--global", "user.signingkey"], (c, out) => gitSigningKey = out.trim())
        Jobs.run(["git", "config", "--global", "--bool", "commit.gpgsign"], (c, out) => gitSign = out.trim() === "true")
    }

    function parseGpg(text, secretFprs) {
        const keys = []
        let cur = null
        const now = Date.now() / 1000
        for (const l of text.split("\n")) {
            const f = l.split(":")
            if (f[0] === "pub") {
                const exp = Number(f[6]) || 0
                cur = { keyid: f[4], created: Number(f[5]) || 0, expires: exp, expired: f[1] === "e" || (exp > 0 && exp < now),
                        revoked: f[1] === "r", soon: exp > 0 && exp > now && exp - now < 30 * 86400, caps: f[11] ?? "", uid: "", fpr: "", secret: false }
                keys.push(cur)
            } else if (cur && f[0] === "fpr" && cur.fpr === "") {
                cur.fpr = f[9]
                cur.secret = secretFprs.includes(cur.fpr)
            } else if (cur && f[0] === "uid" && cur.uid === "") cur.uid = f[9].replace(/\\x3a/g, ":")
        }
        return keys.sort((a, b) => (b.secret - a.secret) || (a.expired - b.expired) || a.uid.localeCompare(b.uid))
    }

    function copyPublicSsh(key) {
        if (!key.pub.endsWith(".pub")) return
        Jobs.run(["sh", "-c", 'wl-copy < "$1"', "sh", key.pub], () => {})
    }
    function copyPublicGpg(fpr) {
        if (!/^[0-9A-F]{16,40}$/.test(fpr)) return
        Jobs.run(["sh", "-c", 'gpg --export --armor -- "$1" | wl-copy', "sh", fpr], () => {})
    }

    // host as written in known_hosts (name, IP, or [name]:port)
    function forgetHost(host, cb) {
        const m = /^\[(.+)\]:(\d+)$/.exec(host.trim())
        const e = m ? (Valid.host(m[1]) || Valid.port(m[2])) : Valid.host(host)
        if (e) return cb(false, e)
        Jobs.run(["ssh-keygen", "-R", host.trim(), "-f", sshDir + "/known_hosts"], (code, out, err) => {
            refresh()
            cb(code === 0 && /updated/.test(out + err), code === 0 ? (/updated/.test(out + err) ? "removed (old file: known_hosts.old)" : "not in known_hosts") : err.trim())
        })
    }

    // file name under ~/.ssh and a comment; ssh-keygen asks for the passphrase itself
    function newKey(name, comment) {
        if (!/^[A-Za-z0-9._-]{1,40}$/.test(name) || name.startsWith(".")) return "file name: letters, digits, . _ - (max 40)"
        if (/[\n\r"]/.test(comment) || comment.length > 80) return "comment: one line, no quotes"
        if (sshKeys.some(k => k.name === name)) return name + " already exists"
        Quickshell.execDetached(["kitty", "--title", "New SSH key", "bash", "-c",
            'ssh-keygen -t ed25519 -C "$2" -f "$1"; echo; echo "Done. Press Enter to close."; read -r _',
            "bash", sshDir + "/" + name, comment])
        return ""
    }
}
