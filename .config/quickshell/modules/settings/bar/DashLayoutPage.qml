import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.services
import ".."
import "../network"

// Dashboard layout page: which cards sit in which column (services/PanelLayout.qml).
// Cards move as a whole; what's inside them stays. "Edit live" opens the
// dashboard in its wiggle mode instead.
Item {
    id: page
    implicitHeight: col.implicitHeight

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 16

        NetCard {
            Layout.fillWidth: true
            title: "Cards"
            header: [
                ActionButton {
                    icon: "󰏫"
                    text: "Edit live"
                    onClicked: EditMode.start("dashboard")
                },
                ActionButton {
                    icon: "󰑓"
                    text: "Reset"
                    interactive: PanelLayout.dashChanged
                    onClicked: PanelLayout.dashReset()
                }
            ]

            ChipBoard {
                id: board
                Layout.fillWidth: true
                Layout.margins: 12
                info: id => PanelLayout.dashCard(id)
                place: (id, zone, index) => zone === "add" ? PanelLayout.dashAdd(id)
                                                           : PanelLayout.dashMove(id, zone === "" ? -1 : Number(zone), index)

                Text {
                    Layout.fillWidth: true
                    text: "Drag cards between the columns  ·  × hides one  ·  a column with the media player or the calendar takes the free width; one with more than fits makes the dashboard taller"
                    wrapMode: Text.Wrap
                    color: Colors.fade(0.45)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Repeater {
                        model: PanelLayout.dashColumnCount
                        BarZone {
                            required property int index
                            Layout.preferredWidth: 1
                            Layout.alignment: Qt.AlignTop
                            zone: String(index)
                            title: ["Left", "Middle", "Right"][index] ?? "Column " + (index + 1)
                            hint: "top to bottom"
                            ids: PanelLayout.dashColumns[index] ?? []
                            page: board
                        }
                    }
                }
                BarZone {
                    zone: ""; title: "Hidden"; hint: "+ puts a card back, or drag it into a column"
                    ids: PanelLayout.dashHidden; page: board
                }
            }
        }
    }
}
