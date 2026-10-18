import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.services
import "../settings/Valid.js" as Valid

// Extra results of the app search (AppSearch.qml), above the app list:
//   2+2, 5 km to mi, =anything   calculator (qalc); Enter copies the result
//   g <words>                    web search (Settings.launcher.searchUrl)
//   > <program> <args>           run in a terminal; split into arguments like a
//                                shell would, but NOT run by a shell (no pipes,
//                                $VARS or globs), so nothing in it is interpreted
//   ssh <name | user@host>       saved connections / ~/.ssh/config hosts / a new host
// `prefixMode`: g / > / ssh hide the app results.
ColumnLayout {
    id: root
    property string query: ""
    property int currentIndex: 0
    signal closeRequested()

    readonly property var cfg: Settings.launcher
    readonly property string q: query.trim()
    readonly property string prefix: /^g\s/.test(q) ? "g" : /^>/.test(q) ? ">" : /^ssh(\s|$)/.test(q) ? "ssh" : ""
    readonly property bool prefixMode: (cfg.prefixes ?? true) && prefix !== ""

    // ── calculator ──────────────────────────────────────────────────────────
    // only for things that clearly are math, so app names never go to qalc
    readonly property string calcExpr: {
        if (!(cfg.calculator ?? true) || prefixMode) return ""
        if (q.startsWith("=")) return q.slice(1).trim()
        if (/^[-+(\d.,\s√π]/.test(q) && /^[\d\s.,+\-*/^()%√π!]+$/.test(q) && /\d\s*[-+*/^%!]|[-+*/^]\s*\(?\d|\)\s*[-+*/^]/.test(q)) return q
        if (/^-?[\d.,]+\s*[^\s\d]+\s+(to|in)\s+\S+$/i.test(q)) return q
        return ""
    }
    property string calcResult: ""
    property string calcError: ""
    property int calcSeq: 0
    property bool hasQalc: true
    Component.onCompleted: Jobs.which(["qalc"], h => root.hasQalc = h.qalc)
    onCalcExprChanged: { calcResult = ""; calcError = ""; if (calcExpr !== "") calcTimer.restart() }
    Timer {
        id: calcTimer
        interval: 180
        onTriggered: {
            const seq = ++root.calcSeq, expr = root.calcExpr
            if (!root.hasQalc) { root.calcError = "calculator: " + Jobs.installHint("qalc"); return }
            Jobs.run(["qalc", "-t", "--", expr], (code, out, err) => {
                if (seq !== root.calcSeq) return
                const r = out.trim().split("\n").pop() ?? ""
                if (code !== 0 || r === "" || r === expr) root.calcError = "can't calculate that"
                else root.calcResult = r
            })
        }
    }

    // ── > command ───────────────────────────────────────────────────────────
    // shell-like word splitting with quotes and backslashes; null = unbalanced quote
    function splitArgs(s) {
        const out = []
        let cur = "", quote = "", has = false
        for (let i = 0; i < s.length; i++) {
            const c = s[i]
            if (quote) {
                if (c === quote) quote = ""
                else if (c === "\\" && quote === '"' && i + 1 < s.length) cur += s[++i]
                else cur += c
            } else if (c === "'" || c === '"') { quote = c; has = true }
            else if (c === "\\" && i + 1 < s.length) { cur += s[++i]; has = true }
            else if (/\s/.test(c)) { if (cur !== "" || has) out.push(cur); cur = ""; has = false }
            else { cur += c; has = true }
        }
        if (quote) return null
        if (cur !== "" || has) out.push(cur)
        return out
    }
    readonly property var cmdArgs: prefix === ">" ? splitArgs(q.slice(1).trim()) : null

    // ── ssh ─────────────────────────────────────────────────────────────────
    readonly property string sshQuery: prefix === "ssh" ? q.slice(3).trim() : ""
    readonly property var sshHosts: prefix === "ssh" ? RemoteConnections.parseSshConfig(NiriSettings.readFile(Quickshell.env("HOME") + "/.ssh/config")).map(r => r.conn.host) : []

    // ── what to show ────────────────────────────────────────────────────────
    // [{ icon, title, subtitle, run: fn, disabled }]
    readonly property var actions: {
        const a = []
        if (calcExpr !== "")
            a.push({ icon: "󰃬", title: calcResult !== "" ? "= " + calcResult : calcError !== "" ? calcError : "calculating…",
                     subtitle: calcExpr + (calcResult !== "" ? "   ·   Enter copies the result" : ""), disabled: calcResult === "",
                     run: () => Quickshell.execDetached(["wl-copy", "--", root.calcResult.replace(/−/g, "-")]) })
        if (!prefixMode) return a
        if (prefix === "g") {
            const words = q.slice(1).trim()
            const url = (cfg.searchUrl ?? "https://duckduckgo.com/?q=%s").replace("%s", encodeURIComponent(words))
            a.push({ icon: "󰖟", title: words === "" ? "Type what to search for" : "Search the web for “" + words + "”", subtitle: url,
                     disabled: words === "", run: () => Quickshell.execDetached(["xdg-open", url]) })
        } else if (prefix === ">") {
            const args = cmdArgs
            a.push({ icon: "󰆍", disabled: !args || args.length === 0,
                     title: args === null ? "Unbalanced quote" : args.length === 0 ? "Type a command to run in a terminal" : "Run " + args[0] + " in a terminal",
                     subtitle: args && args.length ? args.map(x => /[\s'"]/.test(x) || x === "" ? JSON.stringify(x) : x).join(" ") + "   ·   no shell: pipes, $VARS and * don't work"
                                                   : "e.g. > htop  ·  > journalctl -f -u NetworkManager",
                     run: () => runInTerminal(args) })
        } else if (prefix === "ssh") {
            const s = sshQuery.toLowerCase()
            for (const c of RemoteConnections.list)
                if (s === "" || c.name.toLowerCase().includes(s) || c.host.toLowerCase().includes(s))
                    a.push({ icon: RemoteConnections.types[c.type].icon, title: c.name, subtitle: RemoteConnections.types[c.type].name + "  ·  " + (c.user ? c.user + "@" : "") + c.host,
                             run: () => RemoteConnections.connect(c.id) })
            for (const h of sshHosts)
                if ((s === "" || h.toLowerCase().includes(s)) && !RemoteConnections.list.some(c => c.type === "ssh" && c.host === h))
                    a.push({ icon: "󰣀", title: h, subtitle: "~/.ssh/config", run: () => runSsh(h) })
            if (sshQuery !== "" && !a.some(x => x.title === sshQuery)) {
                const e = Valid.sshTarget(sshQuery)
                a.push({ icon: "󰣀", title: "ssh " + sshQuery, subtitle: e ? e : "new connection in a terminal", disabled: e !== "", run: () => runSsh(sshQuery) })
            }
            if (a.length === 0) a.push({ icon: "󰣀", title: "No saved connections", subtitle: "type ssh user@host, or add some in Settings → Connections", disabled: true, run: () => {} })
        }
        return a.slice(0, 6)
    }
    onActionsChanged: if (currentIndex >= actions.length) currentIndex = 0
    onQueryChanged: currentIndex = 0

    function runInTerminal(args) {
        if (!args || args.length === 0) return
        Jobs.which([args[0]], have => {
            if (!have[args[0]]) Jobs.run(["notify-send", "-a", "Launcher", "Not found: " + args[0], Jobs.installHint(args[0])], () => {})
            else Quickshell.execDetached(["kitty", "--hold", "--title", args.join(" "), "--"].concat(args))
        })
    }
    function runSsh(target) {
        if (Valid.sshTarget(target)) return
        Quickshell.execDetached(["kitty", "--title", "ssh " + target, "ssh", "--", target])
    }

    // Enter: run the current action (false if there is none to run)
    function activate() {
        const a = actions[currentIndex]
        if (!a || a.disabled) return false
        a.run()
        closeRequested()
        return true
    }
    function moveDown() { if (currentIndex < actions.length - 1) currentIndex++ }
    function moveUp() { if (currentIndex > 0) currentIndex-- }

    visible: actions.length > 0
    spacing: 2

    Repeater {
        model: root.actions
        Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool isCurrent: root.currentIndex === index
            Layout.fillWidth: true
            implicitHeight: 48
            radius: 8
            color: isCurrent ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.16) : hover.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
            border.width: isCurrent ? 1 : 0
            border.color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.4)
            opacity: modelData.disabled ? 0.65 : 1
            HoverHandler { id: hover; cursorShape: row.modelData.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor }
            TapHandler { onTapped: { root.currentIndex = row.index; root.activate() } }
            RowLayout {
                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                spacing: 12
                Text { text: row.modelData.icon; color: Colors.color6; font.pixelSize: 20; font.family: Properties.fontFamily }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text { Layout.fillWidth: true; text: row.modelData.title; color: "white"; font.pixelSize: 14; font.weight: Font.Medium; elide: Text.ElideRight }
                    Text { Layout.fillWidth: true; text: row.modelData.subtitle; color: Qt.rgba(1, 1, 1, 0.45); font.pixelSize: 11; font.family: Properties.fontFamily; elide: Text.ElideMiddle }
                }
                Text { visible: row.isCurrent && !row.modelData.disabled; text: "↵"; color: Qt.rgba(1, 1, 1, 0.5); font.pixelSize: 14 }
            }
        }
    }
}
