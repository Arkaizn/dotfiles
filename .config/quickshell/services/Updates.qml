pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Single shared update checker. checkupdates locks a shared temp db, so
// running one instance per bar makes all but one fail (and report 0).
Singleton {
    id: root

    property int count: 0

    function refresh() {
        if (!checkProc.running)
            checkProc.running = true;
    }

    // Runs the system upgrade in a terminal, then re-checks once it closes
    function upgrade() {
        if (!upgradeProc.running)
            upgradeProc.running = true;
    }

    Process {
        id: checkProc
        // exit codes: 0 = updates available, 2 = no updates, anything else = error
        command: ["checkupdates", "--nocolor"]
        running: true
        stdout: StdioCollector { id: collector }
        onExited: exitCode => {
            if (exitCode === 0) {
                root.count = collector.text.split("\n").filter(l => l.trim() !== "").length;
                retryTimer.stop();
            } else if (exitCode === 2) {
                root.count = 0;
                retryTimer.stop();
            } else {
                // network down / db locked: keep the last known count, try again soon
                retryTimer.restart();
            }
        }
    }

    Process {
        id: upgradeProc
        command: ["kitty", "--class", "custom_hover", "-e", "bash", "-c",
            "sudo ls >/dev/null 2>&1 && sudo pacman -Syu --noconfirm && yay -Quq --aur | xargs -n 1 yay -S --noconfirm"]
        onExited: root.refresh()
    }

    Timer {
        interval: 30 * 60 * 1000  // regular re-check every 30 minutes
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        id: retryTimer
        interval: 60 * 1000  // retry a failed check after 1 minute
        onTriggered: root.refresh()
    }
}
