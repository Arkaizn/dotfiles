// Test for components/ConfirmArm.qml — run with: qsr test
// (copied next to the component into a temp folder and run as a shell)
import Quickshell
import QtQuick
ShellRoot {
    ConfirmArm { id: arm; timeout: 300 }
    property var log: []
    function check(name, ok) { log.push((ok ? "PASS " : "FAIL ") + name) }
    Component.onCompleted: {
        check("first confirm arms, returns false", arm.confirm("a") === false && arm.armed === "a")
        check("second confirm returns true, disarms", arm.confirm("a") === true && arm.armed === "")
        arm.confirm("a")
        check("other id moves the arm", arm.confirm("b") === false && arm.armed === "b")
        arm.disarm()
        check("disarm", arm.armed === "")
        arm.confirm("c")
        later.start()
    }
    Timer { id: later; interval: 450; onTriggered: {
        check("times out", arm.armed === "")
        check("after timeout first click arms again", arm.confirm("c") === false)
        for (const l of log) console.info(l)
        Qt.quit()
    } }
}
