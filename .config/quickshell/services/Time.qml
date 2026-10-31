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
    // the same date, but changing only once a minute: for views that show
    // minutes or days (a binding on `date` re-runs every second)
    property date minuteDate: new Date()

    function format(fmt: string): string {
        return Qt.formatDateTime(date, fmt);
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
        onDateChanged: {
            if (!date) return
            root.date = date
            if (Math.floor(date.getTime() / 60000) !== Math.floor(root.minuteDate.getTime() / 60000)) root.minuteDate = date
        }
    }
}
