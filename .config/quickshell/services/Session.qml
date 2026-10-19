pragma Singleton
import Quickshell
import QtQuick
import qs.services

// Lock, suspend, log out, reboot, shut down — the one place that knows how
// (control center, lockscreen, updates). systemd first, logind's loginctl as
// the fallback; log out = the running compositor's quit.
Singleton {
    function lock() { Panels.open("lockscreen") }
    function suspend() { run("systemctl suspend || loginctl suspend") }
    function reboot() { run("systemctl reboot || loginctl reboot") }
    function poweroff() { run("systemctl poweroff || loginctl poweroff") }
    function logout() { run(Compositor.quitCommand) }

    function run(cmd) { Quickshell.execDetached(["sh", "-c", cmd]) }
}
