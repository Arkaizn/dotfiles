pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services

// Which compositor the shell runs on (niri or Hyprland), and the few
// compositor actions the shell needs, so the rest of the code doesn't care:
//   focusWindow(title)        bring a window to the front (settings, calendar)
//   focusAppWindow(app, t)    a player's window: app id/class contains `app`,
//                             one whose title contains `t` first
//   focusedOutput(cb)         name of the focused monitor (popups opened by keybind)
//   quitCommand / screenshotCommand
//   settings                  NiriSettings or HyprSettings (settings app pages)
//
// Hyprland is driven through `hyprctl` with its Lua API (Hyprland 0.55+):
//   hyprctl dispatch 'hl.dsp.focus({ window = "title:…" })'
Singleton {
    id: root

    readonly property bool isNiri: (Quickshell.env("NIRI_SOCKET") ?? "") !== ""
    readonly property bool isHyprland: !isNiri && (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "") !== ""
    readonly property string name: isNiri ? "niri" : isHyprland ? "Hyprland" : ""

    // the settings service of the running compositor (niri when neither runs)
    readonly property var settings: isHyprland ? HyprSettings : NiriSettings

    // corner radius of the shell's own windows: the same as the compositor's window corners
    readonly property int appRadius: settings.appRadius

    readonly property string quitCommand: isHyprland ? "hyprctl dispatch 'hl.dsp.exit()'"
                                        : "niri msg action quit --skip-confirmation"
    readonly property string screenshotCommand: isNiri ? "niri msg action screenshot"
                                              : "grim -g \"$(slurp)\" - | satty -f -"

    // a string as a Lua literal, for `hyprctl dispatch` / `hyprctl eval`
    function luaString(s) {
        return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n") + '"'
    }

    function escapeRegex(s) { return String(s).replace(/[.*+?^${}()|[\]\\]/g, "\\$&") }

    function focusWindow(title) {
        if (isHyprland)
            Quickshell.execDetached(["hyprctl", "dispatch",
                "hl.dsp.focus({ window = " + luaString("title:^" + escapeRegex(title) + "$") + " })"])
        else if (isNiri)
            Quickshell.execDetached(["sh", "-c",
                'id=$(niri msg -j windows | jq -r --arg t "$1" \'first(.[] | select(.title == $t) | .id) // empty\'); '
                + '[ -n "$id" ] && niri msg action focus-window --id "$id"', "sh", title])
    }

    // `after`: shell command to run once it's done (or when nothing was found)
    // after: called once that's done (whether a window was found or not)
    function focusAppWindow(app, title, after) {
        // windows whose app id / class and `app` contain each other; one with `title` in its title first
        const pick = '[.[] | select((%APP% // "" | ascii_downcase) as $a | $a != "" and $k != "" and (($a | contains($k)) or ($k | contains($a))))]'
                   + ' | (map(select($t != "" and ((.title // "") | contains($t)))) + .) | first'
        const script = isHyprland
            ? 'addr=$(hyprctl -j clients | jq -r --arg k "$1" --arg t "$2" \'' + pick.replace("%APP%", ".class") + ' | .address // empty\'); '
              + '[ -n "$addr" ] && hyprctl dispatch "hl.dsp.focus({ window = \\"address:$addr\\" })"; '
            : 'id=$(niri msg -j windows | jq -r --arg k "$1" --arg t "$2" \'' + pick.replace("%APP%", ".app_id") + ' | .id // empty\'); '
              + '[ -n "$id" ] && niri msg action focus-window --id "$id"; '
        Jobs.run(["sh", "-c", 'sleep 0.3; ' + script, "sh", app, title ?? ""], () => { if (after) after() })
    }

    // ── Focused monitor ──────────────────────────────────────────────────────
    property var _outputCallbacks: []

    function focusedOutput(cb) {
        if (!isNiri && !isHyprland) { cb(""); return }
        _outputCallbacks.push(cb)
        if (!outputProc.running) {
            outputProc.command = isHyprland ? ["hyprctl", "-j", "monitors"] : ["niri", "msg", "-j", "focused-output"]
            outputProc.running = true
        }
    }

    Process {
        id: outputProc
        stdout: StdioCollector {
            onStreamFinished: {
                let name = ""
                try {
                    const j = JSON.parse(text)
                    name = root.isHyprland ? (j.find(m => m.focused)?.name ?? "") : (j?.name ?? "")
                } catch (e) {}
                const cbs = root._outputCallbacks
                root._outputCallbacks = []
                cbs.forEach(cb => cb(name))     // (forEach: qmllint 6.12 skips files with for…of)
            }
        }
    }
}
