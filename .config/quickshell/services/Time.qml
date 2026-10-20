pragma Singleton

import Quickshell
import QtQuick

// The time, ticking every second. Plain properties updated from the clock
// (not bindings to it): bindings were re-evaluated while a config generation
// is torn down, which printed "Unable to assign [undefined]" at every reload.
Singleton {
    id: root
    property alias enabled: clock.enabled
    property date date: new Date()
    property int hours: date.getHours()
    property int minutes: date.getMinutes()
    property int seconds: date.getSeconds()

    function format(fmt: string): string {
        return Qt.formatDateTime(date, fmt);
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
        onDateChanged: if (date) root.date = date
    }
}
