import QtQuick
import QtQuick.Controls
import qs.components
import qs.services
import "lib/FmAddress.js" as FmAddress
import "lib/FmFormat.js" as FmFormat

// The typeable address (Ctrl+L, or "/" / "~" in the folder): a path, "~/…",
// a file:// address, a server (smb://, sftp://, …) or a path relative to the
// open folder. Suggestions while typing, best first: server address schemes
// ("ss" → ssh://, sftp://), saved servers, the subfolders of the folder being
// typed (the backend's "dirs", kept while you stay in it), files and folders
// below the open one with the text in their name (a short search). The top one
// shows greyed after the text and starts out picked (highlighted): Enter goes
// there (a file: its folder, it selected; a scheme: it's filled in), Tab fills
// it in. ↑/↓ pick another (↑ from the top: just what's typed); after a "/"
// nothing is picked, so Enter goes to the typed folder. Esc closes the list,
// then the bar.
//   AddressBar { backend; here; home; onGo: path => …; onConnectUri: uri => …; onFinished: … }   start(prefix)
// smb://, sftp://, ftp://, dav(s)://, nfs:// addresses connect to the server (onConnectUri).
SearchField {
    id: root

    property Item backdrop: null          // shown blurred behind its popover (the window's content)

    required property var backend
    property string here: "/"
    property string home: ""
    signal go(string path)
    signal connectUri(string uri)          // smb://, sftp://, …: a server
    signal reveal(string path)             // a file suggestion: its folder, it selected
    property var servers: []               // saved servers [{ uri, name }]
    signal finished()

    icon: ""
    placeholderText: "Type a path and press Enter"

    // [{ label, sub, value (the text it puts in), kind: scheme | server | folder | result, path?, dir? }]
    property var offers: []
    property var found: []                // search results for what's typed (no "/" in it)
    readonly property var schemes: ["ssh://", "sftp://", "smb://", "ftp://", "ftps://", "davs://", "dav://", "nfs://", "file://"]
    // the top suggestion, if it continues what's typed: shown greyed after it, Tab takes it
    readonly property string ghost: {
        const o = offers[0], t = text
        if (!o || t === "" || picked !== 0 || cursorPosition !== t.length) return ""
        return o.value.toLowerCase().startsWith(t.toLowerCase()) && o.value.length > t.length ? o.value.slice(t.length) : ""
    }
    property int picked: -1
    property var cache: ({ path: "", names: [] })
    property int _req: 0

    function start(prefix) {
        text = prefix && prefix !== "" ? (prefix === "~" ? "~/" : prefix) : (here === home ? "~/" : here + (here === "/" ? "" : "/"))
        visible = true
        forceActiveFocus()
        if (!prefix) selectAll()
        offers = []
        picked = -1
    }
    function finish() { visible = false; offers = []; finished() }

    // the folder part of what's typed, and its subfolders
    function refresh() {
        search()
        const sp = FmAddress.split(text)
        const dir = FmAddress.resolve(sp.dir === "" ? "." : sp.dir, here, home)
        // not a local folder (ssh://svs, smb://…): no subfolders, but the servers still match
        if (dir === "") { _offer(null); return }
        if (cache.path === dir) { _offer(sp.part); return }
        const req = ++_req
        backend.request("dirs", { path: dir }, {
            done: res => { if (req !== root._req) return; root.cache = { path: dir, names: res.names }; root._offer(FmAddress.split(root.text).part) },
            error: () => { if (req === root._req) { root.cache = { path: dir, names: [] }; root.offers = [] } }
        })
    }
    function _offer(part) {
        if (!activeFocus) { offers = []; return }
        const t = text, low = t.trim().toLowerCase(), plain = t !== "" && t.indexOf("/") < 0 && !t.startsWith("~")
        const out = []
        if (plain && !low.includes(":")) for (const sc of schemes) if (sc.startsWith(low)) out.push({ label: sc, sub: "server address", value: sc, kind: "scheme" })
        // servers: by address or name; "ssh://svs" also finds sftp://svs-… (GVfs names ssh that way)
        const bare = u => u.toLowerCase().replace(/^[a-z0-9+.-]+:\/\//, "")
        const q = bare(low)
        if (low.length >= 2 && (q !== "" || !low.includes("://")))
            for (const sv of servers) if (sv.uri.toLowerCase().includes(low) || (q !== "" && bare(sv.uri).includes(q)) || sv.name.toLowerCase().includes(q || low))
                out.push({ label: sv.name, sub: sv.uri, value: sv.uri, kind: "server" })
        const sp = FmAddress.split(t)
        if (part !== null) for (const n of FmAddress.matches(cache.names, part, 8)) out.push({ label: n, sub: "", value: sp.dir + n + "/", kind: "folder" })
        if (plain) for (const r of found) if (!out.some(o => o.kind === "folder" && o.label === r.name))
            out.push({ label: r.name, sub: "~/" + (r.path.startsWith(home + "/") ? r.path.slice(home.length + 1) : r.path).replace(/\/[^/]*$/, ""),
                       value: r.path, kind: "result", path: r.path, dir: r.dir })
        offers = out.slice(0, 10)
        picked = offers.length && !t.endsWith("/") ? 0 : -1
    }
    // files / folders below the open one with the text in their name (a short search, the last one stopped)
    property int _searchId: 0
    function search() {
        if (_searchId) backend.cancel(_searchId)
        _searchId = 0
        const t = text.trim()
        if (t.length < 2 || t.indexOf("/") >= 0 || t.includes(":") || t.startsWith("~")) { found = []; return }
        const got = []
        let id = 0
        id = backend.request("search", { path: here, query: t, depth: 3 }, {
            batch: items => { if (id === root._searchId) got.push(...items) },
            done: () => { if (id !== root._searchId) return; root._searchId = 0
                          root.found = got.sort((a, b) => b.score - a.score).slice(0, 6); root._offer(FmAddress.split(root.text).part) },
            error: () => {}
        })
        _searchId = id
    }
    onTextEdited: refreshTimer.restart()
    Timer { id: refreshTimer; interval: Anim.instant; onTriggered: root.refresh() }

    // a suggestion into the field (a result: its whole path)
    function takeOffer(o) {
        text = o.kind === "result" ? o.path + (o.dir ? "/" : "") : o.value
        cursorPosition = text.length
        refreshTimer.restart()
    }
    // put a folder name in place of what's typed after the last "/"
    function take(name, slash) {
        const sp = FmAddress.split(text)
        text = sp.dir + name + (slash ? "/" : "")
        cursorPosition = text.length
        refreshTimer.restart()
    }
    function complete() {
        if (picked >= 0) { takeOffer(offers[picked]); return }
        if (ghost !== "") { takeOffer(offers[0]); return }
        if (offers.length === 1) { takeOffer(offers[0]); return }
        const part = FmAddress.split(text).part
        const c = FmAddress.common(offers.filter(o => o.kind === "folder").map(o => o.label).filter(n => n.toLowerCase().startsWith(part.toLowerCase())))
        if (c.length > part.length) take(c, false)
    }

    onAccepted: {
        const o = picked >= 0 ? offers[picked] : null
        // a file found by name: its folder, it selected
        if (o && o.kind === "result" && !o.dir) { finish(); reveal(o.path); return }
        // a scheme alone isn't an address yet: it's filled in, the host comes next
        if (o && o.kind === "scheme") { takeOffer(o); return }
        const t = o ? (o.kind === "result" ? o.path : o.value) : text
        // a server address: connected to (GVfs), not resolved as a path
        if (/^[a-z][a-z0-9+.-]*:\/\//i.test(t.trim()) && !/^file:\/\//i.test(t.trim())) {
            finish()
            connectUri(t.trim())
            return
        }
        const p = FmAddress.resolve(t, here, home)
        if (p === "") {
            error = false
            error = true
            return
        }
        finish()
        go(p)
    }
    onTextChanged: error = false
    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Down: if (offers.length) picked = (picked + 1) % offers.length; break
        case Qt.Key_Up: if (offers.length) picked = picked === 0 ? -1 : picked < 0 ? offers.length - 1 : picked - 1; break
        case Qt.Key_Tab: complete(); break
        case Qt.Key_Escape: if (offers.length) offers = []; else finish(); break
        default: return
        }
        event.accepted = true
    }
    onActiveFocusChanged: if (!activeFocus && visible) finish()

    // the top suggestion's rest, greyed after the text (Tab takes it)
    Text {
        visible: root.ghost !== "" && root.activeFocus
        x: root.leftPadding + root.contentWidth
        anchors.verticalCenter: parent.verticalCenter
        text: root.ghost
        color: Colors.fade(0.35)
        font: root.font
        textFormat: Text.PlainText
    }

    ToolTip.visible: error && visible
    ToolTip.text: "Type an absolute path (/…, ~/…), a folder in this one, or a file:// address"

    Popup {
        id: list
        // the window's zoom (popups are drawn above it, like PopupMenu)
        scale: AppZoom.at(root)
        transformOrigin: Popup.TopLeft
        y: root.height + Tokens.space.s4
        width: root.width
        padding: Tokens.space.s4
        visible: root.visible && root.activeFocus && root.offers.length > 0
        closePolicy: Popup.NoAutoClose
        background: PopoverBackground { backdrop: root.backdrop }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Anim.fast; easing.type: Anim.standard }
            NumberAnimation { property: "scale"; from: 0.96 * AppZoom.at(root); to: AppZoom.at(root); duration: Anim.fast; easing.type: Anim.standard }
        }
        exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Anim.instant } }
        contentItem: Column {
            spacing: Tokens.space.s1
            Repeater {
                model: root.offers
                Pressable {
                    id: offer
                    required property var modelData
                    required property int index
                    width: parent.width
                    accessibleName: modelData.label
                    height: modelData.sub ? Tokens.size.control + Tokens.space.s6 : Tokens.size.controlSmall
                    onClicked: {
                        if (modelData.kind === "result" && !modelData.dir) { root.finish(); root.reveal(modelData.path); return }
                        root.takeOffer(modelData)
                        root.forceActiveFocus()
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: Tokens.radius.md
                        color: offer.index === root.picked ? Colors.fillPressed : offer.hovered ? Colors.fillHover : "transparent"
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        x: Tokens.space.s10
                        width: parent.width - 2 * Tokens.space.s10
                        Text {
                            width: parent.width
                            text: (({ scheme: "\u{F048B}", server: "\u{F048B}", folder: "\u{F024B}" })[offer.modelData.kind]
                                   ?? (offer.modelData.dir ? "\u{F024B}" : "\u{F0214}")) + "  " + FmFormat.shown(offer.modelData.label)
                            color: offer.index === root.picked ? Colors.ink : Colors.fade(0.8)
                            font.pixelSize: Tokens.font.small
                            font.family: Properties.fontFamily
                            elide: Text.ElideMiddle
                            textFormat: Text.PlainText
                        }
                        Text {
                            visible: offer.modelData.sub !== ""
                            width: parent.width
                            leftPadding: Tokens.space.s20
                            text: FmFormat.shown(offer.modelData.sub)
                            color: Colors.fade(0.45)
                            font.pixelSize: Tokens.font.caption
                            font.family: Properties.fontFamily
                            elide: Text.ElideLeft
                            textFormat: Text.PlainText
                        }
                    }
                }
            }
        }
    }
}
