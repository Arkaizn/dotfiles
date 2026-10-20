import QtQuick
import QtQuick.Effects
import qs.services
import "widgets"

// One desktop widget: its content (widgets/<Type>Widget.qml) on a card, glass
// or nothing (then with a soft shadow so it stays readable on any wallpaper).
// Scale and rotation are applied by whoever places it.
Item {
    id: frame
    property var inst: null
    property bool interactive: true      // clicks reach the widget (not in the editor)
    property bool active: true           // shown: widgets poll only then

    readonly property var opts: DesktopWidgets.optsOf(inst)
    readonly property string bg: opts.background ?? "card"
    readonly property real pad: bg === "none" ? 6 : 18
    // false: the widget asks to be hidden (`hidden`: media player without a player); the editor still shows it
    readonly property bool shown: loader.item !== null && (loader.item.hidden !== true || !interactive)

    implicitWidth: loader.item ? Math.ceil(loader.item.implicitWidth) + pad * 2 : 40
    implicitHeight: loader.item ? Math.ceil(loader.item.implicitHeight) + pad * 2 : 40
    opacity: opts.opacity ?? 1

    Rectangle {
        anchors.fill: parent
        visible: frame.bg !== "none"
        radius: 22
        color: frame.bg === "glass" ? Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.32) : Properties.panelColor
        border.width: 1
        border.color: Properties.cardBorder
    }

    Loader {
        id: loader
        x: frame.pad
        y: frame.pad
        width: item ? item.implicitWidth : 0
        height: item ? item.implicitHeight : 0
        sourceComponent: frame.inst ? kinds[frame.inst.type] ?? null : null
        // no background: a shadow under the content
        layer.enabled: frame.bg === "none"
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 0.5
            shadowColor: Qt.rgba(0, 0, 0, Colors.light ? 0.25 : 0.7)
            shadowVerticalOffset: 1
            autoPaddingEnabled: true
        }
    }
    // type → content (loaded as types, so their own folder's files resolve)
    readonly property var kinds: ({ clock: clockC, calendar: calendarC, media: mediaC, system: systemC, network: networkC,
                                    disk: diskC, battery: batteryC, events: eventsC, countdown: countdownC, note: noteC,
                                    apps: appsC, image: imageC })
    Component { id: clockC; ClockWidget {} }
    Component { id: calendarC; CalendarWidget {} }
    Component { id: mediaC; MediaWidget {} }
    Component { id: systemC; SystemWidget {} }
    Component { id: networkC; NetworkWidget {} }
    Component { id: diskC; DiskWidget {} }
    Component { id: batteryC; BatteryWidget {} }
    Component { id: eventsC; EventsWidget {} }
    Component { id: countdownC; CountdownWidget {} }
    Component { id: noteC; NoteWidget {} }
    Component { id: appsC; AppsWidget {} }
    Component { id: imageC; ImageWidget {} }

    Binding { target: loader.item; property: "opts"; value: frame.opts; when: loader.item !== null }
    Binding { target: loader.item; property: "interactive"; value: frame.interactive; when: loader.item !== null }
    Binding { target: loader.item; property: "active"; value: frame.active; when: loader.item !== null }
}
