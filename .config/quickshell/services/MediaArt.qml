pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Album art of remote media sessions (MediaSync), cached on disk:
//   MediaArt.get(url)  → "file://…" once downloaded, "" until then / on failure
// Local players' file:// art is passed through. http(s) art is fetched by curl
// (TLS verified, ≤ 10 MB, ≤ 15 s, one at a time) into
// ~/.cache/quickshell/media-art/<md5 of the URL>, so QML's Image never loads
// from the network (MEDIASYNC_PLAN.md, D7). The bridge guarantees these URLs
// carry no credentials. Files older than 14 days are removed at start.
Singleton {
    id: root

    readonly property string dir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/quickshell/media-art"
    property var files: ({})            // url → "file://…" | "" (failed)
    property var _queue: []

    function get(url) {
        if (typeof url !== "string" || url === "") return ""
        if (url.startsWith("file://")) return url
        if (!/^https?:\/\//.test(url)) return ""
        const f = root.files[url]
        if (f !== undefined) return f
        if (!root._queue.includes(url) && root._queue.length < 20) {
            root._queue.push(url)
            Qt.callLater(root._next)
        }
        return ""
    }

    function _next() {
        if (fetch.running || root._queue.length === 0) return
        const url = root._queue[0]
        fetch.url = url
        fetch.file = root.dir + "/" + Qt.md5(url)
        fetch.running = true
    }

    Process {
        id: fetch
        property string url: ""
        property string file: ""
        // url and file are arguments, never part of the script
        command: ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && { [ -s \"$1\" ] || { curl -fsSL --proto =http,https --max-time 15 --max-filesize 10485760 -o \"$1.part\" -- \"$2\" && mv -f \"$1.part\" \"$1\"; }; } && [ -s \"$1\" ] && echo ok; rm -f \"$1.part\"",
                  "sh", file, url]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = Object.assign({}, root.files)
                m[fetch.url] = text.trim() === "ok" ? "file://" + fetch.file : ""
                root.files = m
                root._queue = root._queue.filter(u => u !== fetch.url)
                Qt.callLater(root._next)
            }
        }
        onExited: Qt.callLater(root._next)      // the stream can finish before the process is done
    }

    Process {
        running: true
        command: ["find", root.dir, "-maxdepth", "1", "-type", "f", "-mtime", "+14", "-delete"]
    }
}
