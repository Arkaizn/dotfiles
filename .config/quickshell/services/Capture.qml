pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Screenshots (grim / slurp / satty) and screen recording (wf-recorder).
// Menu: modules/capture/CaptureMenu.qml; options: settings app → Apps → Screenshots.
//
//   screenshot(what, after, delay)   what: "region" | "screen" | "window"
//                                    after: "save" | "copy" | "edit"   (default: settings)
//   record(what, audio)              what: "region" | "screen";  audio: "none" | "desktop" | "mic"
//   stop()                           stop the recording (file is finished cleanly)
//
// A recording runs detached (it survives a shell restart); its pid / file /
// start time are in $XDG_RUNTIME_DIR/quickshell-recording, which is how the bar
// indicator finds it again.
//
//   qs ipc call capture menu
//   qs ipc call capture screenshot region|screen|window
//   qs ipc call capture record region|screen
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
    property int recPid: 0
    property string recFile: ""
    property real recStart: 0               // unix seconds
    property real now: Date.now() / 1000
    readonly property int elapsed: recording ? Math.max(0, Math.floor(now - recStart)) : 0

    signal message(string text)             // shown by the menu (errors, "copied", …)

    function stamp() {
        return Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss")
    }

    // ── Screenshots ─────────────────────────────────────────────────────────
    function screenshot(what, after, delay) {
        if (busy) return
        after = after || opt("after", "save")
        delay = Number(delay ?? opt("delay", "0")) || 0
        menuOpen = false
        Jobs.which(["grim", "slurp", "wl-copy", "satty"], have => {
            const need = what === "region" ? ["grim", "slurp"] : what === "window" && Compositor.isNiri ? [] : ["grim"]
            if (after !== "edit") need.push("wl-copy"); else need.push("satty")
            const miss = need.filter(b => !have[b])
            if (miss.length > 0) return notify("Screenshot", "missing: " + miss.map(b => Jobs.installHint(b)).join(", "))
            busy = true
            const dir = after === "copy" ? runtime : shotDir
            const file = dir + "/Screenshot_" + stamp() + ".png"
            Jobs.run(["mkdir", "-p", "--", dir], () => {
                // the menu must be gone from the screen before grim runs
                pick(what, (args, err) => {
                    if (args === null) { busy = false; if (err) notify("Screenshot", err); return }
                    wait(delay, () => shoot(what, args, file, after))
                })
            })
        })
    }

    // what to capture → grim arguments (null = cancelled)
    function pick(what, cb) {
        later(250, () => {
            if (what === "region")
                Jobs.run(["slurp"], (code, out) => cb(code === 0 && out.trim() ? ["-g", out.trim()] : null))
            else if (what === "screen")
                focusedOutput(name => cb(name ? ["-o", name] : [], ""))
            else if (Compositor.isNiri) cb(["niri"])
            else if (Compositor.isHyprland)
                Jobs.run(["hyprctl", "-j", "activewindow"], (code, out) => {
                    try {
                        const w = JSON.parse(out)
                        if (!w.at) return cb(null, "no focused window")
                        cb(["-g", w.at[0] + "," + w.at[1] + " " + w.size[0] + "x" + w.size[1]])
                    } catch (e) { cb(null, "no focused window") }
                })
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
            Jobs.run(["niri", "msg", "action", "screenshot-window", "--write-to-disk", "true",
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

    function focusedOutput(cb) {
        if (Compositor.isNiri)
            Jobs.run(["niri", "msg", "-j", "focused-output"], (c, out) => { try { cb(JSON.parse(out).name) } catch (e) { cb("") } })
        else if (Compositor.isHyprland)
            Jobs.run(["hyprctl", "-j", "monitors"], (c, out) => { try { cb(JSON.parse(out).find(m => m.focused)?.name ?? "") } catch (e) { cb("") } })
        else cb("")
    }

    // ── Recording ───────────────────────────────────────────────────────────
    function record(what, audio) {
        if (recording) return stop()
        audio = audio || opt("audio", "none")
        menuOpen = false
        Jobs.which(["wf-recorder", "slurp", "pactl"], have => {
            if (!have["wf-recorder"]) return notify("Recording", "wf-recorder isn't installed: " + Jobs.installHint("wf-recorder"))
            if (what === "region" && !have.slurp) return notify("Recording", Jobs.installHint("slurp"))
            const ext = opt("format", "mp4")
            const file = videoDir + "/Recording_" + stamp() + "." + ext
            Jobs.run(["mkdir", "-p", "--", videoDir], () => pick(what, (args, err) => {
                if (args === null) { if (err) notify("Recording", err); return }
                audioArgs(audio, have.pactl, a => startRecording(file, args.concat(a)))
            }))
        })
    }

    function audioArgs(audio, havePactl, cb) {
        if (audio === "mic") return cb(["--audio"])
        if (audio !== "desktop") return cb([])
        if (!havePactl) return cb(["--audio"])
        // desktop sound = the monitor of the default output
        Jobs.run(["pactl", "get-default-sink"], (code, out) => cb(code === 0 && out.trim() ? ["--audio=" + out.trim() + ".monitor"] : ["--audio"]))
    }

    Component { id: detachedProc; Process {} }

    function startRecording(file, args) {
        // fixed script; the file and arguments are passed as data ($1, $2, "$@")
        const p = detachedProc.createObject(root, { command: ["sh", "-c",
            'f=$1; st=$2; shift 2\n'
          + 'wf-recorder -y -f "$f" "$@" >/dev/null 2>"$st.log" &\n'
          + 'pid=$!\n'
          + 'printf "%s\\n%s\\n%s\\n" "$pid" "$f" "$(date +%s)" > "$st"\n'
          + 'wait "$pid"; code=$?\n'
          + 'rm -f "$st"\n'
          + 'if [ -s "$f" ]; then\n'
          + '  a=$(notify-send -a Recording -i video-x-generic -A default=Open -A folder="Open folder" "Recording saved" "$f")\n'
          + '  case $a in default) xdg-open "$f" ;; folder) xdg-open "${f%/*}" ;; esac\n'
          + 'else\n'
          + '  notify-send -a Recording -i dialog-error "Recording failed" "$(tail -n 3 "$st.log") (exit $code)"\n'
          + 'fi\n'
          + 'rm -f "$st.log"',
            "sh", file, stateFile].concat(args) })
        p.startDetached()
        p.destroy()
        later(400, refresh)
    }

    function stop() {
        refresh()
        if (!recording || recPid <= 0) return
        // only signal it if that pid is still wf-recorder
        Jobs.run(["sh", "-c", '[ "$(cat /proc/"$1"/comm 2>/dev/null)" = wf-recorder ] && kill -INT "$1"', "sh", String(recPid)], () => later(300, refresh))
    }

    // read the state file (synchronously); its pid must still be a wf-recorder
    function refresh() {
        const l = readText(stateFile).split("\n")
        const pid = parseInt(l[0])
        if (!(pid > 0) || readText("/proc/" + pid + "/comm").trim() !== "wf-recorder") return setIdle()
        recPid = pid
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
    function setIdle() { recording = false; recPid = 0; recFile = "" }

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
        function record(what: string): void { root.record(what || "screen") }
        function stop(): void { root.stop() }
        function status(): string {
            return root.recording ? "recording " + root.elapsed + "s → " + root.recFile : "idle"
        }
    }
}
