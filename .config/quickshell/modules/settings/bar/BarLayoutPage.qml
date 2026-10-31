import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Bar layout page: which modules sit where on the bar (services/BarLayout.qml).
// Drag chips between zones; × takes one off the bar, + puts it back. Changes
// apply to the bar right away. Optionally a monitor gets its own layout.
Item {
    id: page
    implicitHeight: col.implicitHeight

    property string screenName: ""          // "" = all monitors
    readonly property bool editable: screenName === "" || BarLayout.hasOwn(screenName)
    readonly property var layout: screenName === "" ? BarLayout.globalLayout : BarLayout.layoutFor(screenName)
    readonly property var screens: Quickshell.screens.map(s => s.name)

    // ── drag state (shared with BarZone / BarChip) ──────────────────────────
    property string dragId: ""
    property string dropZone: "-"           // "-" = not over a zone, "" = "not on the bar"
    property int dropIndex: 0
    property alias ghost: ghost

    function prepareDrag(chip) {
        const p = chip.mapToItem(page, 0, 0)
        ghost.x = p.x
        ghost.y = p.y
        ghost.modId = chip.modId
    }
    function startDrag(id, zone) { dragId = id; dropZone = "-" }
    function endDrag() {
        if (dragId === "") return
        ghost.Drag.drop()
        cancelDrag()
    }
    function cancelDrag() { dragId = ""; dropZone = "-" }
    function dropHere() {
        if (dragId !== "" && dropZone !== "-") place(dragId, dropZone, dropIndex)
    }
    function place(id, zone, index) { BarLayout.move(screenName, id, zone, index) }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: Tokens.space.s16

        // ── Monitor ─────────────────────────────────────────────────────────────
        Section {
            Layout.fillWidth: true
            visible: page.screens.length > 1
            title: "Monitor"
            SettingRow {
                first: true
                label: "Edit the layout of"
                desc: "Each monitor uses the shared layout unless it has its own"
                Segmented {
                    options: [{ label: "All monitors", value: "" }].concat(page.screens.map(n => ({ label: n, value: n })))
                    value: page.screenName
                    small: true
                    onEdited: v => page.screenName = v
                }
            }
            SettingRow {
                visible: page.screenName !== ""
                label: "Own layout for " + page.screenName
                desc: page.editable ? "Changes below only affect this monitor" : "Off: this monitor shows the shared layout"
                ToggleSwitch {
                    checked: page.editable
                    onToggled: v => BarLayout.setOwn(page.screenName, v)
                }
            }
        }

        // ── Preview ─────────────────────────────────────────────────────────────
        Section {
            Layout.fillWidth: true
            title: "Preview"
            header: [
                ActionButton {
                    icon: "󰏫"
                    text: "Edit live"
                    onClicked: EditMode.start("bar", page.screenName)
                },
                ActionButton {
                    icon: "󰑓"
                    text: "Reset"
                    interactive: page.editable
                    onClicked: BarLayout.reset(page.screenName)
                }
            ]

            Item {
                Layout.fillWidth: true
                implicitHeight: 58
                Rectangle {
                    anchors { fill: parent; margins: Tokens.space.s12 }
                    radius: Tokens.radius.lg
                    color: Properties.panelColor
                    border.width: 1
                    border.color: Properties.panelBorder

                    Row {
                        anchors { left: parent.left; leftMargin: Tokens.space.s10; verticalCenter: parent.verticalCenter }
                        spacing: Tokens.space.s8
                        Repeater {
                            model: page.layout.left
                            PreviewIcon { required property string modelData; modId: modelData }
                        }
                    }
                    Row {
                        id: pCenter
                        anchors.centerIn: parent
                        spacing: Tokens.space.s8
                        Repeater {
                            model: page.layout.center
                            PreviewIcon { required property string modelData; modId: modelData; strong: true }
                        }
                    }
                    Row {
                        anchors { right: pCenter.left; rightMargin: Tokens.space.s8; verticalCenter: parent.verticalCenter }
                        spacing: Tokens.space.s8
                        Repeater {
                            model: page.layout.centerLeft
                            PreviewIcon { required property string modelData; modId: modelData }
                        }
                    }
                    Row {
                        anchors { left: pCenter.right; leftMargin: Tokens.space.s8; verticalCenter: parent.verticalCenter }
                        spacing: Tokens.space.s8
                        Repeater {
                            model: page.layout.centerRight
                            PreviewIcon { required property string modelData; modId: modelData }
                        }
                    }
                    Row {
                        anchors { right: parent.right; rightMargin: Tokens.space.s10; verticalCenter: parent.verticalCenter }
                        spacing: Tokens.space.s8
                        Repeater {
                            model: page.layout.right
                            PreviewIcon { required property string modelData; modId: modelData }
                        }
                    }
                }
            }
        }

        // ── Zones ───────────────────────────────────────────────────────────────
        Section {
            Layout.fillWidth: true
            title: "Layout"
            header: Text {
                text: page.editable ? "drag to move  ·  × removes  ·  changes apply right away" : "turn on “Own layout” to edit"
                color: Colors.fade(0.4)
                font.pixelSize: Tokens.font.caption
                font.family: Properties.fontFamily
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: Tokens.space.s12
                spacing: Tokens.space.s10

                BarZone { zone: "left"; title: "Left"; hint: "from the left edge"; ids: page.layout.left; page: page }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space.s10
                    BarZone {
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        zone: "centerLeft"; title: "Beside centre"; hint: "left of it"
                        ids: page.layout.centerLeft; page: page
                    }
                    BarZone {
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        zone: "center"; title: "Centre"; hint: "always centred"
                        ids: page.layout.center; page: page
                    }
                    BarZone {
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        zone: "centerRight"; title: "Beside centre"; hint: "right of it"
                        ids: page.layout.centerRight; page: page
                    }
                }
                BarZone { zone: "right"; title: "Right"; hint: "to the right edge"; ids: page.layout.right; page: page }
                BarZone {
                    zone: ""; title: "Not on the bar"; hint: "+ adds to the right end, or drag into a zone"
                    ids: BarLayout.unused(page.layout); page: page
                }
            }
        }

    }

    // follows the pointer while a chip is dragged
    Rectangle {
        id: ghost
        property string modId: ""
        readonly property var mod: BarLayout.module(modId)
        z: 100
        visible: page.dragId !== ""
        width: gRow.implicitWidth + 20
        height: 34
        radius: 9
        color: Colors.alpha(Colors.color6, 0.30)
        border.width: 1
        border.color: Colors.color6
        Drag.active: page.dragId !== ""
        Drag.keys: ["barmod"]
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2
        Row {
            id: gRow
            anchors.centerIn: parent
            spacing: 7
            Text { text: ghost.mod.icon; color: Colors.ink; font.pixelSize: Tokens.font.label; font.family: Properties.fontFamily }
            Text { text: ghost.mod.name; color: Colors.ink; font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily }
        }
    }
}
