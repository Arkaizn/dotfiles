pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick

// Media players for the bar, dashboard and lockscreen (each view keeps its own
// selected player), and the bar's 3-bar visualizer from cava.
//
//   players                MPRIS players, without playerctld (it only mirrors
//                          the active player, so that one would show up twice)
//   visualizer             [3 heights] while cava runs, else [3, 3, 3]
//   acquireVisualizer() / releaseVisualizer()   cava runs while someone uses
//                          it and a player is playing (one cava for all bars)
Singleton {
    id: root

    readonly property var players: Mpris.players.values.filter(p => !(p.dbusName || "").includes("playerctld"))
    readonly property bool anyPlaying: players.some(p => p.isPlaying)

    property int _visualizerUsers: 0
    function acquireVisualizer() { _visualizerUsers++ }
    function releaseVisualizer() { _visualizerUsers = Math.max(0, _visualizerUsers - 1) }

    property var visualizer: [3, 3, 3]

    Process {
        command: ["cava", "-p", Quickshell.env("HOME") + "/.config/cava/quickshell.ini"]
        running: root._visualizerUsers > 0 && root.anyPlaying
        stdout: SplitParser {
            onRead: line => {
                const parts = line.trim().split(" ")
                if (parts.length !== 3) return
                root.visualizer = parts.map(v => { const n = parseInt(v); return isNaN(n) ? 3 : Math.max(3, n) })
            }
        }
        onRunningChanged: if (!running) root.visualizer = [3, 3, 3]
    }
}
