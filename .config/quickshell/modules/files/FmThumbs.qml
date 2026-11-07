import QtQuick
import qs.services

// Thumbnails for the views (the backend's "thumb": the shared ~/.cache/thumbnails).
// get() answers from what's known and asks the backend for the rest; the views
// bind to `version` and call get again when answers came. Newest asks first (what
// is on screen now), at most three at a time; images, videos, PDFs and office
// documents up to Settings.files.thumbMax MB.
//   get(path, type, mtime, size, px) → URL or ""   ·   version
Item {
    id: root

    required property var backend
    property int version: 0
    property var _known: ({})            // "path|mtime|large" → URL, or "" (none)
    property var _queue: []              // keys waiting, newest last
    property var _args: ({})
    property int _busy: 0
    readonly property real maxBytes: (Settings.files.thumbMax ?? 50) * 1048576

    function wanted(type) {
        return type.startsWith("image/") || type.startsWith("video/") || type === "application/pdf"
            || type.startsWith("application/vnd.oasis.opendocument") || type.startsWith("application/vnd.openxmlformats")
            || type === "application/epub+zip"
    }
    function url(p) {
        try { return "file://" + p.split("/").map(encodeURIComponent).join("/") } catch (e) { return "" }
    }
    // a bound function: the views call it as thumbFor(…)
    readonly property var get: (path, type, mtime, size, px) => {
        if (!wanted(type) || size > maxBytes || size === 0) return ""
        const large = px > 96
        const key = path + "|" + mtime + "|" + (large ? "L" : "N")
        const k = _known[key]
        if (k !== undefined) return k
        if (!_args[key]) {
            _args[key] = { path: path, type: type, mtime: mtime, large: large }
            _queue.push(key)
            // scrolled past long ago: not wanted any more
            if (_queue.length > 400) delete _args[_queue.shift()]
            Qt.callLater(_pump)
        }
        return ""
    }
    function _pump() {
        while (_busy < 3 && _queue.length) {
            const key = _queue.pop()
            const a = _args[key]
            _busy++
            backend.request("thumb", a, {
                done: res => { root._got(key, res.thumb ? root.url(res.thumb) : "") },
                error: () => root._got(key, "")
            })
        }
    }
    function _got(key, u) {
        _busy--
        _known[key] = u
        delete _args[key]
        if (u !== "") bump.restart()
        _pump()
    }
    // many arrive at once: one re-evaluation for them
    Timer { id: bump; interval: Anim.instant; onTriggered: root.version++ }
}
