pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Screenshots (grim / slurp / satty), text recognition (tesseract) and screen
// recording (wf-recorder). Menu: modules/capture/CaptureMenu.qml; options:
// settings app → Apps → Screenshots. Regions are picked with niri's own
// screenshot UI on niri (slurp elsewhere); windows by clicking them.
// Recording: scripts/record.sh.
//
//   screenshot(what, after, delay, screen)
//                                    what: "region" | "screen" | "window" (click the window)
//                                    after: "save" | "copy" | "edit"   (default: settings)
//                                    screen: "" = the focused one | "all" | an output name
//   ocr()                            pick a region, its text goes to the clipboard
//   record(what, audio, screen)      what: "screen" | "window" (picked in the screen-share dialog)
//                                    audio: "both" | "desktop" | "mic" | "none"
//                                    screen: as above; "all" records every monitor and merges them
//   stop()                           stop the recording (file is finished cleanly)
//
// A recording runs detached (it survives a shell restart); its pid / file /
// start time are in $XDG_RUNTIME_DIR/quickshell-recording, which is how the bar
// indicator finds it again.
//
//   qs ipc call capture menu
//   qs ipc call capture screenshot region|screen|window
//   qs ipc call capture ocr
//   qs ipc call capture record screen|window
//   qs ipc call capture stop
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string runtime: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string stateFile: runtime + "/quickshell-recording"

    // options (Settings.capture, edited on the Screenshots page)
    function opt(k, def) { return Settings.capture[k] ?? def }
    function expand(p) { return p.replace(/^~(?=\/|$)/, home) }
    readonly property string shotDir: expand(opt("dir", "~/Pictures/Screenshots"))
    readonly property string videoDir: expand(opt("videoDir", "~/Videos/Recordings"))

    property bool menuOpen: false
    property bool busy: false               // a screenshot is being taken
    property int countdown: 0               // seconds left of the delay

    // ── recording state ─────────────────────────────────────────────────────
    property bool recording: false
    property var recPids: []
    property string recFile: ""
    property real recStart: 0               // unix seconds
    property real now: Date.now() / 1000
    readonly property int elapsed: recording ? Math.max(0, Math.floor(now - recStart)) : 0

    signal message(string text)             // shown by the menu (errors, "copied", …)

    function stamp() {
        return Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss")
    }

    // ── Screenshots ─────────────────────────────────────────────────────────
    function screenshot(what, after, delay, screen) {
        if (busy) return
        after = after || opt("after", "save")
        delay = Number(delay ?? opt("delay", "0")) || 0
        menuOpen = false
        Jobs.which(["grim", "slurp", "wl-copy", "satty"], have => {
            const need = what === "region" ? (Compositor.isNiri ? [] : ["grim", "slurp"])
                       : what === "window" && Compositor.isNiri ? [] : ["grim"]
            if (after !== "edit") need.push("wl-copy"); else need.push("satty")
            const miss = need.filter(b => !have[b])
            if (miss.length > 0) return notify("Screenshot", "missing: " + miss.map(b => Jobs.installHint(b)).join(", "))
            const dir = after === "copy" ? runtime : shotDir
            const file = dir + "/Screenshot_" + stamp() + ".png"
            // niri's screenshot UI: it captures when you confirm (Enter / Space)
            if (what === "region" && Compositor.isNiri)
                return Jobs.run(["mkdir", "-p", "--", dir], () => wait(delay, () => niriRegion(file, ok => { if (ok) finish(file, after) })))
            busy = true
            Jobs.run(["mkdir", "-p", "--", dir], () => {
                // the menu must be gone from the screen before grim runs
                pick(what, (args, err) => {
                    if (args === null) { busy = false; if (err) notify("Screenshot", err); return }
                    wait(delay, () => shoot(what, args, file, after))
                }, screen)
            })
        })
    }

    // what to capture → grim arguments (null = cancelled)
    // screen: "" = focused output, "all" = the whole layout, else an output name
    function pick(what, cb, screen) {
        later(250, () => {
            if (what === "region")
                Jobs.run(["slurp"], (code, out) => cb(code === 0 && out.trim() ? ["-g", out.trim()] : null))
            else if (what === "screen") {
                if (screen === "all") cb([])
                else if (screen) cb(["-o", screen])
                else focusedOutput(name => cb(name ? ["-o", name] : [], ""))
            }
            // window: click the one you want
            else if (Compositor.isNiri)
                Jobs.run(["niri", "msg", "-j", "pick-window"], (code, out) => {
                    try { const w = JSON.parse(out); cb(w && w.id !== undefined ? ["niri", String(w.id)] : null) }
                    catch (e) { cb(null) }
                })
            else if (Compositor.isHyprland)
                // slurp only offers the windows of the visible workspaces
                Jobs.run(["sh", "-c", 'ws=$(hyprctl -j monitors | jq "[.[].activeWorkspace.id]")\n'
                        + 'hyprctl -j clients | jq -r --argjson ws "$ws" \'.[] | select(.mapped and (.workspace.id as $w | $ws | index($w))) | "\\(.at[0]),\\(.at[1]) \\(.size[0])x\\(.size[1])"\' | slurp -r'],
                        (code, out) => cb(code === 0 && out.trim() ? ["-g", out.trim()] : null))
            else cb(null, "window screenshots need niri or Hyprland")
        })
    }

    function shoot(what, args, file, after) {
        const done = code => {
            busy = false
            if (code !== 0) return notify("Screenshot", "capturing failed (exit " + code + ")")
            finish(file, after)
        }
        if (args[0] === "niri") {
            // niri's own window screenshot (works for windows partly off-screen)
            Jobs.run(["niri", "msg", "action", "screenshot-window", "--id", args[1], "--write-to-disk", "true",
                      "--show-pointer", opt("pointer", false) ? "true" : "false", "--path", file], code => {
                if (code !== 0) return done(code)
                // niri writes the file in the background
                Jobs.run(["sh", "-c", 'i=0; while [ ! -s "$1" ] && [ $i -lt 30 ]; do sleep 0.1; i=$((i+1)); done; [ -s "$1" ]', "sh", file], done)
            })
        } else {
            Jobs.run(["grim"].concat(opt("pointer", false) ? ["-c"] : []).concat(args).concat([file]), done)
        }
    }

    function finish(file, after) {
        if (after === "edit") {
            Jobs.run(["satty", "--filename", file, "--output-filename", file, "--copy-command", "wl-copy"], () => {})
            return
        }
        Jobs.run(["sh", "-c", 'wl-copy --type image/png < "$1"', "sh", file], () => {
            if (after === "copy") {
                Jobs.run(["rm", "-f", "--", file], () => {})
                if (opt("notify", true)) notify("Screenshot copied", "in the clipboard")
                return
            }
            if (!opt("notify", true)) return
            Jobs.run(["notify-send", "-a", "Screenshot", "-i", file, "-A", "default=Open", "-A", "edit=Edit", "-A", "folder=Open folder",
                      "Screenshot saved", file.replace(home, "~") + "\n(also in the clipboard)"], (code, out) => {
                const a = out.trim()
                if (a === "default") Quickshell.execDetached(["xdg-open", file])
                else if (a === "edit") Jobs.run(["satty", "--filename", file, "--output-filename", file, "--copy-command", "wl-copy"], () => {})
                else if (a === "folder") Quickshell.execDetached(["xdg-open", file.replace(/\/[^/]*$/, "")])
            })
        })
    }

    // niri's screenshot UI, saved to `file`. niri gives no signal when it's
    // cancelled, so wait (up to 2 min) for the file; a newer request supersedes.
    property int regionToken: 0
    function niriRegion(file, cb) {
        const token = ++regionToken
        later(250, () => Jobs.run(["niri", "msg", "action", "screenshot", "--show-pointer", opt("pointer", false) ? "true" : "false", "--path", file], code => {
            if (code !== 0) { notify("Screenshot", "niri's screenshot UI failed (exit " + code + ")"); return cb(false) }
            Jobs.run(["sh", "-c", 'i=0; while [ ! -s "$1" ] && [ $i -lt 1200 ]; do sleep 0.1; i=$((i+1)); done; [ -s "$1" ] && sleep 0.2', "sh", file],
                     c => { if (token === regionToken) cb(c === 0) })
        }))
    }

    // a picked region as a PNG in `file` (niri UI, else slurp + grim)
    function regionTo(file, cb) {
        if (Compositor.isNiri) return niriRegion(file, cb)
        pick("region", (args, err) => {
            if (args === null) { if (err) notify("Screenshot", err); return cb(false) }
            Jobs.run(["grim", "-g", args[1], file], code => cb(code === 0))
        })
    }

    // ── Text recognition (OCR) ──────────────────────────────────────────────
    function ocr() {
        menuOpen = false
        Jobs.which(["tesseract", "wl-copy", "grim", "slurp"], have => {
            const need = ["tesseract", "wl-copy"].concat(Compositor.isNiri ? [] : ["grim", "slurp"])
            const miss = need.filter(b => !have[b])
            if (miss.length > 0) return notify("Text recognition", "missing: " + miss.map(b => Jobs.installHint(b)).join(", "))
            const file = runtime + "/ocr_" + stamp() + ".png"
            regionTo(file, ok => {
                if (!ok) return
                Jobs.run(["tesseract", file, "-", "-l", opt("ocrLangs", "eng+deu")], (code, out, err) => {
                    Jobs.run(["rm", "-f", "--", file], () => {})
                    const text = out.trim()
                    if (code !== 0) return notify("Text recognition", err.trim().split("\n").pop() || "tesseract failed")
                    if (text === "") return notify("Text recognition", "no text found in the region")
                    Jobs.runInput(["wl-copy"], text, () => {
                        const preview = text.length > 160 ? text.slice(0, 160) + "…" : text
                        Jobs.run(["notify-send", "-a", "Screenshot", "-i", "edit-copy", "Text copied", preview])
                    })
                })
            })
        })
    }

    function focusedOutput(cb) {
        if (Compositor.isNiri)
            Jobs.run(["niri", "msg", "-j", "focused-output"], (c, out) => { try { cb(JSON.parse(out).name) } catch (e) { cb("") } })
        else if (Compositor.isHyprland)
            Jobs.run(["hyprctl", "-j", "monitors"], (c, out) => { try { cb(JSON.parse(out).find(m => m.focused)?.name ?? "") } catch (e) { cb("") } })
        else cb("")
    }

    // ── Recording ───────────────────────────────────────────────────────────
    function record(what, audio, screen) {
        if (recording) return stop()
        audio = audio || opt("audio", "both")
        menuOpen = false
        const bin = what === "window" ? "gpu-screen-recorder" : "wf-recorder"
        Jobs.which([bin], have => {
            if (!have[bin]) return notify("Recording", bin + " isn't installed: " + Jobs.installHint(bin))
            const file = videoDir + "/Recording_" + stamp() + "." + opt("format", "mp4")
            Jobs.run(["mkdir", "-p", "--", videoDir], () => {
                if (what === "window") return startRecording(file, audio, "window", [])
                const out = s => s.name + "@" + s.x + "," + s.y + "," + s.width + "," + s.height
                if (screen === "all") return startRecording(file, audio, "outputs", Quickshell.screens.map(out))
                const go = name => {
                    const s = Quickshell.screens.find(x => x.name === name) ?? Quickshell.screens[0]
                    startRecording(file, audio, "outputs", [out(s)])
                }
                if (screen) go(screen); else focusedOutput(go)
            })
        })
    }

    Component { id: detachedProc; Process {} }

    // scripts/record.sh does the recording (and the sound mix / merging)
    function startRecording(file, audio, mode, targets) {
        const p = detachedProc.createObject(root, { command: [Quickshell.shellDir + "/scripts/record.sh", stateFile, file, audio, mode].concat(targets) })
        p.startDetached()
        p.destroy()
        later(400, refresh)
        if (mode === "window") later(3000, refresh)    // after the share dialog
    }

    function stop() {
        refresh()
        if (!recording || recPids.length === 0) return
        // only signal pids that are still recorders
        Jobs.run(["sh", "-c", 'for p; do case $(cat /proc/"$p"/comm 2>/dev/null) in wf-recorder|gpu-screen-reco) kill -INT "$p" ;; esac; done', "sh"].concat(recPids.map(String)),
                 () => later(300, refresh))
    }

    // read the state file (synchronously); its pid must still be a wf-recorder
    function refresh() {
        const l = readText(stateFile).split("\n")
        const pids = (l[0] ?? "").trim().split(/\s+/).map(Number).filter(p => p > 0)
        const alive = pids.filter(p => ["wf-recorder", "gpu-screen-reco"].includes(readText("/proc/" + p + "/comm").trim()))
        if (alive.length === 0) return setIdle()
        recPids = alive
        recFile = l[1] ?? ""
        recStart = Number(l[2]) || Date.now() / 1000
        now = Date.now() / 1000
        recording = true
    }
    FileView { id: reader; blockLoading: true; printErrors: false }
    function readText(p) {
        reader.path = ""
        reader.path = p
        return reader.text() ?? ""
    }
    function setIdle() { recording = false; recPids = []; recFile = "" }

    // ticks only while recording (elapsed time + noticing it ended)
    Timer {
        running: root.recording
        interval: 1000
        repeat: true
        onTriggered: { root.now = Date.now() / 1000; root.refresh() }
    }
    Component.onCompleted: refresh()

    // ── helpers ─────────────────────────────────────────────────────────────
    function wait(seconds, fn) {
        if (seconds <= 0) return fn()
        countdown = seconds
        tick.fn = fn
        tick.start()
    }
    Timer {
        id: tick
        property var fn
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown--
            if (root.countdown <= 0) { stop(); const f = fn; fn = null; if (f) f() }
        }
    }

    Component {
        id: timerComp
        Timer { property var fn; onTriggered: { fn(); destroy() } }
    }
    function later(ms, fn) { timerComp.createObject(root, { interval: ms, fn: fn, running: true }) }

    function notify(title, body) {
        message(title + ": " + body)
        Jobs.run(["notify-send", "-a", "Screenshot", title, body])
    }

    IpcHandler {
        target: "capture"
        function menu(): void { root.menuOpen = !root.menuOpen }
        function screenshot(what: string): void { root.screenshot(what || "region") }
        function ocr(): void { root.ocr() }
        function record(what: string): void { root.record(what || "screen") }
        function recordAll(): void { root.record("screen", "", "all") }
        function stop(): void { root.stop() }
        function status(): string {
            return root.recording ? "recording " + root.elapsed + "s → " + root.recFile : "idle"
        }
    }
}
