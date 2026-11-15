pragma Singleton
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.services
import qs.services.lib

// Desktop pets (modules/pets): small pixel animals that live on the bar (or at
// the bottom of the screen). They mostly lie around and nap, get up for a
// short walk now and then, come when called (each in its own way), and look
// up when a notification comes in. Off until switched on in the settings.
//
//   Settings.pets: { enabled, animals: [ids], coats: { id: coat }, place: bar | screen,
//                    monitors: [ids] ([] = every monitor), size, layer (both for "screen"),
//                    sleepAfter (minutes), react, game, runner }
//   (game / runner: the offline game, services/OfflineGame.qml)
//
// A new animal: a definition like services/lib/PetCat.js (frames, animations,
// coats, nature; PixelArt.js describes the format, PetBrain.needs lists the
// animations it must have), a line for it in services/lib/qmldir, and its `def`
// in `animals` below. Settings, the import check and the game pick it up from there.
Singleton {
    id: root

    readonly property var animals: [PetCat.def, PetDog.def, PetBunny.def, PetHamster.def, PetDino.def]
    readonly property var animalIds: animals.map(a => a.id)
    function animal(id) { return animals.find(a => a.id === id) ?? animals[0] }

    readonly property var conf: Settings.pets
    readonly property bool enabled: conf.enabled === true
    // (a hand-edited settings.json can hold anything: wrong types mean the default)
    readonly property var chosenIds: (Array.isArray(conf.animals) ? conf.animals : ["cat", "dog"]).filter(id => animalIds.includes(id))
    // the list the pets are built from only changes when the choice does (not with
    // every other setting: they'd all be made again and start over)
    readonly property string chosenKey: chosenIds.join(",")
    property var chosen: []
    onChosenKeyChanged: chosen = animals.filter(a => chosenIds.includes(a.id))
    Component.onCompleted: chosen = animals.filter(a => chosenIds.includes(a.id))
    readonly property var coats: conf.coats !== null && typeof conf.coats === "object" && !Array.isArray(conf.coats) ? conf.coats : ({})
    function coatOf(def) { return def.coats.some(c => c.id === coats[def.id]) ? coats[def.id] : def.coats[0].id }
    function paletteOf(def) { return PixelArt.coatPalette(def, coatOf(def)) }
    readonly property string place: conf.place === "screen" ? "screen" : "bar"
    // on the bar: only a top / bottom bar has a row to walk along
    readonly property bool onBar: place === "bar" && !PanelGeometry.barVertical
    readonly property var monitors: Array.isArray(conf.monitors) ? conf.monitors.filter(m => typeof m === "string") : []
    readonly property string size: PetBrain.sizes[conf.size] !== undefined ? conf.size : "medium"
    readonly property int px: PetBrain.sizes[size]                 // at the bottom of the screen: screen pixels per art pixel
    readonly property string layer: conf.layer === "bottom" ? "bottom" : "top"
    readonly property int sleepAfter: Number.isInteger(conf.sleepAfter) ? Math.max(1, Math.min(120, conf.sleepAfter)) : 3     // minutes
    readonly property bool react: conf.react !== false

    readonly property bool active: enabled && chosen.length > 0

    function showsOn(screenName) { return DeskWidgets.showsOn(monitors, screenName, Monitors.outputs) }
    // the same for a ShellScreen. It knows its own model and serial number, so a
    // monitor chosen in the settings ("make model serial") is recognised at once,
    // without waiting for the compositor's monitor list (Monitors.outputs, a scan)
    function showsOnScreen(s) {
        if (!s) return false
        if (monitors.length === 0) return true
        const own = s.model && s.serialNumber ? s.model + " " + s.serialNumber : ""
        return monitors.some(id => id === s.name || (own !== "" && id.endsWith(own))) || showsOn(s.name)
    }

    function setEnabled(on) { Settings.set("pets", "enabled", on) }
    function setCoat(id, coat) { Settings.set("pets", "coats", Object.assign({}, coats, { [id]: coat })) }
    function setAnimal(id, on) {
        const l = chosenIds.filter(x => x !== id)
        Settings.set("pets", "animals", on ? animalIds.filter(x => x === id || l.includes(x)) : l)
    }

    // ── away / back ──
    // no key or pointer for `sleepAfter` minutes (a playing video doesn't count
    // as being there: the pets can't see it)
    readonly property bool idle: idleMonitor.isIdle
    IdleMonitor {
        id: idleMonitor
        enabled: root.active
        timeout: root.sleepAfter * 60
        respectInhibitors: false
    }

    // ── something happened: the pets look up ──
    signal poke()
    Connections {
        target: Notifs
        function onArrived() { if (root.active && root.react) root.poke() }
    }
}
