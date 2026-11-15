pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import qs.services.lib

// The offline game (modules/controlcenter/RunnerCard.qml, logic in
// services/lib/Runner.js): a small runner in the control center while nothing
// is connected. This keeps what outlives the card: whether it's wanted, and
// the best score (Quickshell.stateDir/offline-game.json: per device, not a setting).
//
//   Settings.pets.game     show it (default on)
Singleton {
    id: root

    readonly property bool enabled: Settings.pets.game !== false
    // the dino runs (in its line-art colours; an older "runner" setting is ignored)
    readonly property var runner: PetDino.def
    // what the bar's network chip shows as the offline icon: no cable, no Wi-Fi
    readonly property bool offline: !NetLink.wiredConnected && !NetLink.wifiConnected

    // the offline icon was clicked: the control center opens with the game
    // (cleared when the card is closed or the control center goes away)
    property bool wanted: false
    function request() { if (enabled && offline) wanted = true }

    property int best: 0
    // → true when it's a new best
    function submit(score) {
        const n = Math.floor(Number(score))
        if (!(n > best) || n > 9999999) return false
        best = n
        file.setText(JSON.stringify({ best: best }) + "\n")
        return true
    }

    FileView { id: file; path: Quickshell.stateDir + "/offline-game.json"; blockLoading: true; printErrors: false }
    Component.onCompleted: {
        try {
            const b = JSON.parse(file.text() || "{}").best
            if (Number.isInteger(b) && b > 0 && b <= 9999999) root.best = b
        } catch (e) {}
    }
}
