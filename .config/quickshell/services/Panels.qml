pragma Singleton
import Quickshell
import QtQuick

// Opens and closes the shell's surfaces, so features don't need each other's
// ids or a `qs ipc call` subprocess to reach one another. Each surface
// registers its functions when it's created:
//   Panels.register("dashboard", { toggle: scr => …, open: scr => …, close: () => … })
// and anyone can then:
//   Panels.toggle("dashboard", screen)        screen: a ShellScreen (e.g. the bar's),
//   Panels.open("settings")                   or nothing = the focused monitor
//   Panels.close("launcher")
//   Panels.call("settings", "openPage", "barlayout")   any other function a surface registered
// The IPC targets (qs ipc call dashboard toggle, …) call the same functions.
//
// Names: dashboard, controlCenter, launcher, clipboard, wallpapers, keybinds,
//        connections, settings, calendar, perfmon, capture, lockscreen
Singleton {
    id: root

    property var _panels: ({})

    function register(name, api) { _panels[name] = api }
    // only if it's still that surface's registration (a reload registers the new one first)
    function unregister(name, api) { if (_panels[name] === api) delete _panels[name] }
    function has(name) { return _panels[name] !== undefined }

    function call(name, fn, ...args) {
        const p = _panels[name]
        if (!p || typeof p[fn] !== "function") {
            console.warn("Panels: " + name + "." + fn + " isn't registered")
            return undefined
        }
        return p[fn](...args)
    }
    function toggle(name, screen) { return call(name, "toggle", screen) }
    function open(name, screen) { return call(name, "open", screen) }
    function close(name) { return call(name, "close") }
}
