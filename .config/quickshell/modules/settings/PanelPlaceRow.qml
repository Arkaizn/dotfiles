import QtQuick
import qs.services
import "network"

// Panel editor page: where a panel sits — start / middle / end of the bar, or
// floating. The live editor also sets places in between (then none is picked).
NetRow {
    id: row
    property string pid
    readonly property var p: PanelGeometry.panel(pid)
    readonly property var d: PanelGeometry.defaults[pid]
    readonly property string value: p.attach === "float" ? "float" : typeof p.along === "number" ? "" : p.along

    label: "Place"
    desc: p.attach === "float" ? "Floating, anywhere on the screen (move it in the live editor)"
        : typeof p.along === "number" ? "On the bar, at " + Math.round(p.along * 100) + " % of it (set in the live editor)"
        : "On the bar"
    changed: p.attach !== d.attach || p.along !== d.along

    Segmented {
        small: true
        options: [{ label: "Start", value: "start" }, { label: "Middle", value: "center" },
                  { label: "End", value: "end" }, { label: "Floating", value: "float" }]
        value: row.value
        onEdited: v => {
            if (v === "float") PanelGeometry.set(row.pid, "attach", "float")
            else { PanelGeometry.set(row.pid, "attach", "bar"); PanelGeometry.set(row.pid, "along", v) }
        }
    }
}
