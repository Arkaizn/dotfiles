//@ pragma UseQApplication

import Quickshell
import QtQuick
import "modules/lockscreen"
// not for a type here: Quickshell only registers the directory imports of
// files it reaches through imports, and this makes it reach ShellRest.qml's
import "modules"

ShellRoot {
    id: root

    // First, so at login (locking at start) it isn't held up by the rest.
    // Not lazy: Quickshell 0.3.2 can't hand a locked WlSessionLock over to a
    // new config generation (D11, LockScreen.qml).
    LockScreen { id: lockScreen }
    readonly property int timingCreated: lockScreen.timing.mark("shell.qml objects created")   // TEMPORARY (LockTiming.qml)

    // The rest of the shell: right away, except at login, where it loads once
    // the lockscreen is up (LockScreen.startPending). Through `source`, so
    // shell.qml doesn't compile all of it before the lockscreen can lock; and
    // only set then: LazyLoader compiles its source as soon as it's set. Active
    // follows the source (both following startPending, active could switch on
    // first, with nothing to load, and the rest never got created).
    LazyLoader {
        active: source !== ""
        source: lockScreen.startPending ? "" : "modules/ShellRest.qml"
        onLoadingChanged: if (!loading) lockScreen.timing.mark("rest of the shell loaded")   // TEMPORARY (LockTiming.qml)
    }
}
