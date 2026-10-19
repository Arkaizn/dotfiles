import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."
import "../network"

// Control center layout page (services/PanelLayout.qml), the same two levels
// as its live editors: the order of the cards, and which button sits in which
// card (the clock card, Wi-Fi & Bluetooth, tools, own cards). Plus own cards:
// name, shown / hidden, delete.
Item {
    id: page
    implicitHeight: col.implicitHeight

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 16

        // ── cards ───────────────────────────────────────────────────────────
        NetCard {
            Layout.fillWidth: true
            title: "Cards"
            header: [
                ActionButton {
                    icon: "󰏫"
                    text: "Edit live"
                    onClicked: EditMode.start("controlCenter")
                },
                ActionButton {
                    icon: "󰑓"
                    text: "Reset"
                    interactive: PanelLayout.ccChanged
                    onClicked: PanelLayout.ccReset()
                }
            ]

            ChipBoard {
                id: cards
                Layout.fillWidth: true
                Layout.margins: 12
                info: id => PanelLayout.ccCard(id)
                place: (id, zone, index) => zone === "add" ? PanelLayout.ccAdd(id)
                                          : zone === "" ? PanelLayout.ccRemove(id)
                                          : PanelLayout.ccMove(id, index)

                Text {
                    Layout.fillWidth: true
                    text: "Drag to reorder  ·  × hides a card  ·  Reset brings the default order back (own cards stay, hidden)"
                    wrapMode: Text.Wrap
                    color: Colors.fade(0.45)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                }
                BarZone {
                    zone: "order"; title: "Shown"; hint: "first = top"
                    ids: PanelLayout.ccOrder; page: cards
                }
                BarZone {
                    zone: ""; title: "Hidden"; hint: "+ adds at the bottom, or drag it in"
                    ids: PanelLayout.ccHidden; page: cards
                }
            }
        }

        // ── buttons ─────────────────────────────────────────────────────────
        NetCard {
            Layout.fillWidth: true
            title: "Buttons"
            header: [
                ActionButton {
                    icon: "󰏫"
                    text: "Edit live"
                    onClicked: EditMode.start("controlCenterButtons")
                },
                ActionButton {
                    icon: "󰑓"
                    text: "Reset"
                    interactive: PanelLayout.ccItemsChanged
                    onClicked: PanelLayout.ccResetItems()
                }
            ]

            ChipBoard {
                id: buttons
                Layout.fillWidth: true
                Layout.margins: 12
                info: id => PanelLayout.item(id)
                addZone: "connectivity"
                addIndex: 999
                place: (id, zone, index) => PanelLayout.ccMoveItem(id, zone, index)

                Text {
                    Layout.fillWidth: true
                    text: "Drag buttons between cards  ·  × hides one  ·  the clock card shows them as small icon buttons, the others as tiles"
                    wrapMode: Text.Wrap
                    color: Colors.fade(0.45)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                }
                Repeater {
                    model: PanelLayout.ccHolders
                    BarZone {
                        required property string modelData
                        zone: modelData
                        title: PanelLayout.ccCard(modelData).name
                        hint: PanelLayout.ccOrder.includes(modelData) ? "" : "card is hidden"
                        ids: PanelLayout.ccItems[modelData] ?? []
                        page: buttons
                    }
                }
                BarZone {
                    zone: ""; title: "Not shown"; hint: "+ adds to Wi-Fi & Bluetooth, or drag it into a card"
                    ids: PanelLayout.ccHiddenItems; page: buttons
                }
            }
        }

        // ── own cards ───────────────────────────────────────────────────────
        NetCard {
            Layout.fillWidth: true
            title: "Own cards"
            header: ActionButton {
                icon: "󰐕"
                text: "New card"
                onClicked: PanelLayout.ccNewCard()
            }

            Text {
                visible: PanelLayout.ccCustomIds.length === 0
                Layout.fillWidth: true
                Layout.margins: 16
                text: "None yet. A new card goes to the bottom of the control center; drag buttons into it above, or live there."
                wrapMode: Text.Wrap
                color: Colors.fade(0.45)
                font.pixelSize: 12
                font.family: Properties.fontFamily
            }

            Repeater {
                model: PanelLayout.ccCustomIds
                NetRow {
                    id: own
                    required property string modelData
                    required property int index
                    readonly property int count: (PanelLayout.ccItems[modelData] ?? []).length
                    first: index === 0
                    label: PanelLayout.ccCard(modelData).name
                    desc: count + (count === 1 ? " button" : " buttons")
                          + (PanelLayout.ccOrder.includes(modelData) ? "" : "  ·  hidden")
                    RowLayout {
                        spacing: 8
                        TextControl {
                            implicitWidth: 200
                            value: PanelLayout.ccCustom[own.modelData]?.title ?? ""
                            placeholderText: "Name (optional)"
                            onEdited: v => PanelLayout.ccRename(own.modelData, v)
                        }
                        ToggleSwitch {
                            checked: PanelLayout.ccOrder.includes(own.modelData)
                            onToggled: v => v ? PanelLayout.ccAdd(own.modelData) : PanelLayout.ccRemove(own.modelData)
                        }
                        ActionButton {
                            icon: "󰆴"
                            text: "Delete"
                            textColor: Colors.red
                            onClicked: PanelLayout.ccDelete(own.modelData)
                        }
                    }
                }
            }
        }
    }
}
