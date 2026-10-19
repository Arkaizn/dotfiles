import QtQuick

// "Click again to confirm": the first confirm(id) arms `id` and returns false,
// a second confirm(id) within `timeout` ms returns true (and disarms). Arming
// another id moves the arm there. One button: use any fixed id.
//
//   ConfirmArm { id: arm }
//   onClicked: if (arm.confirm("reboot")) reboot()
//   textColor: arm.armed === "reboot" ? Colors.red : …
QtObject {
    id: root

    property int timeout: 3000
    property string armed: ""          // the armed id, "" = nothing armed

    function confirm(id) {
        if (armed === id) { disarm(); return true }
        armed = id
        _timer.restart()
        return false
    }
    function disarm() { _timer.stop(); armed = "" }

    property Timer _timer: Timer { interval: root.timeout; onTriggered: root.armed = "" }
}
