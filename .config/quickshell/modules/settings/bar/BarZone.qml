import QtQuick
import QtQuick.Layouts
import qs.services

// One zone on the bar layout page: its modules as chips, and a drop target.
// While a chip is dragged over it, a marker shows where it will land.
Rectangle {
    id: zoneBox
    required property string zone            // "" = not on the bar
    required property string title
    property string hint: ""
    required property var ids
    required property Item page

    objectName: "zone-" + zone
    readonly property bool target: page.dropZone === zone && page.dragId !== ""

    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + 24
    radius: 12
    color: target ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.08) : "#1a000000"
    border.width: 1
    border.color: target ? Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.6) : Qt.rgba(1, 1, 1, 0.06)
    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 8

        RowLayout {
            spacing: 8
            Text {
                text: zoneBox.title
                color: Qt.rgba(1, 1, 1, 0.75)
                font.pixelSize: 12
                font.bold: true
                font.family: Properties.fontFamily
            }
            Text {
                Layout.fillWidth: true
                text: zoneBox.hint
                color: Qt.rgba(1, 1, 1, 0.4)
                font.pixelSize: 11
                font.family: Properties.fontFamily
                elide: Text.ElideRight
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: Math.max(34, flow.implicitHeight)

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: zoneBox.ids.length === 0
                text: zoneBox.page.editable ? "Drop modules here" : "empty"
                color: Qt.rgba(1, 1, 1, 0.3)
                font.pixelSize: 11
                font.italic: true
                font.family: Properties.fontFamily
            }

            Flow {
                id: flow
                width: parent.width
                spacing: 6
                Repeater {
                    id: rep
                    model: zoneBox.ids
                    BarChip {
                        required property string modelData
                        modId: modelData
                        zone: zoneBox.zone
                        page: zoneBox.page
                    }
                }
            }

            // where the dragged chip will land
            Rectangle {
                id: marker
                visible: zoneBox.target && zoneBox.zone !== ""
                width: 3
                radius: 1.5
                color: Colors.color6
                property var at: zoneBox.markerAt(zoneBox.page.dropIndex)
                x: at.x
                y: at.y
                height: 34
            }

            DropArea {
                anchors.fill: parent
                anchors.margins: -12
                keys: ["barmod"]
                onEntered: drag => zoneBox.track(drag.x - 12, drag.y - 12)
                onPositionChanged: drag => zoneBox.track(drag.x - 12, drag.y - 12)
                onExited: if (zoneBox.page.dropZone === zoneBox.zone) zoneBox.page.dropZone = "-"
                onDropped: zoneBox.page.dropHere()
            }
        }
    }

    // chips other than the dragged one, in order
    function others() {
        const out = []
        for (let i = 0; i < rep.count; i++) {
            const c = rep.itemAt(i)
            if (c && c.modId !== page.dragId) out.push(c)
        }
        return out
    }

    // index (without the dragged chip) for a point in the flow
    function track(px, py) {
        const list = others()
        let idx = list.length
        for (let i = 0; i < list.length; i++) {
            const c = list[i]
            const rowBelow = py < c.y
            const sameRow = py >= c.y && py < c.y + c.height + flow.spacing
            if (rowBelow || (sameRow && px < c.x + c.width / 2)) { idx = i; break }
        }
        page.dropZone = zone
        page.dropIndex = idx
    }

    function markerAt(idx) {
        const list = others()
        if (list.length === 0) return { x: 0, y: 0 }
        if (idx < list.length) return { x: list[idx].x - 4.5, y: list[idx].y }
        const l = list[list.length - 1]
        return { x: l.x + l.width + 1.5, y: l.y }
    }
}
