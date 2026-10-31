import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
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
        spacing: Tokens.space.s16

        Section {
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
                Layout.margins: Tokens.space.s12
                info: id => PanelLayout.dashCard(id)
                place: (id, zone, index) => zone === "add" ? PanelLayout.dashAdd(id)
                                                           : PanelLayout.dashMove(id, zone === "" ? -1 : Number(zone), index)

                Text {
                    Layout.fillWidth: true
                    text: "Drag cards between the columns  ·  × hides one  ·  a column with the media player or the calendar takes the free width; one with more than fits makes the dashboard taller"
                    wrapMode: Text.Wrap
                    color: Colors.fade(0.45)
                    font.pixelSize: Tokens.font.caption
                    font.family: Properties.fontFamily
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space.s10
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
