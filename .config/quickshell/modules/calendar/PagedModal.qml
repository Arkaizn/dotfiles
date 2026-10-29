import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services

// A settings dialog with its pages listed on the left (like the settings app)
// and the picked one on the right — no long scrolling through everything.
//   PagedModal {
//       id: m
//       title: "Mail settings"; icon: "󰒓"
//       pages: [{ id: "new", icon: "󰂚", label: "New mail" },
//               { id: "a1", label: "Work", color: "#88f", group: "Accounts" },     // group: a heading above it
//               { id: "add", icon: "󰐕", label: "Add account", action: true }]      // action: emits actionPicked
//       ColumnLayout { visible: m.page === "new"; Layout.fillWidth: true; … }     // one per page
//   }
//   m.openPage(id)
Modal {
    id: root

    cardWidth: 900
    property string icon: "󰒓"
    property string title: ""
    property string subtitle: "Changes apply right away"
    property var pages: []
    property string page: ""
    default property alias pageContent: pageCol.data
    signal actionPicked(string id)

    function openPage(id) { page = id; open() }
    onShownChanged: if (shown && !pages.some(p => p.id === page && !p.action)) page = pages.find(p => !p.action)?.id ?? ""
    onPageChanged: pageFlick.contentY = 0
    // a page that went away (an account removed): the first one
    onPagesChanged: if (page && !pages.some(p => p.id === page)) page = pages.find(p => !p.action)?.id ?? ""

    readonly property var current: pages.find(p => p.id === page) ?? null

    ColumnLayout {
        width: parent.width
        // one height for every page: switching doesn't make the card jump
        height: Math.max(360, Math.min(640, root.height - 90))
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text { text: root.icon; color: Colors.color6; font.pixelSize: 20; font.family: Properties.fontFamily }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text { Layout.fillWidth: true; text: root.title; color: Colors.ink; font.pixelSize: 17; font.bold: true; font.family: Properties.fontFamily }
                Text { text: root.subtitle; color: Colors.fade(0.5); font.pixelSize: 11; font.family: Properties.fontFamily }
            }
            IconButton { implicitWidth: 30; implicitHeight: 30; icon: "󰅖"; onClicked: root.close() }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 14

            // ── the pages ──
            Flickable {
                id: navFlick
                Layout.preferredWidth: 200
                Layout.fillHeight: true
                contentHeight: nav.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                ColumnLayout {
                    id: nav
                    width: navFlick.width
                    spacing: 2
                    Repeater {
                        model: root.pages
                        ColumnLayout {
                            id: navRow
                            required property var modelData
                            required property int index
                            readonly property bool selected: root.page === modelData.id
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                visible: !!navRow.modelData.group
                                Layout.leftMargin: 10
                                Layout.topMargin: navRow.index > 0 ? 12 : 0
                                Layout.bottomMargin: 2
                                text: (navRow.modelData.group ?? "").toUpperCase()
                                color: Colors.fade(0.4)
                                font.pixelSize: 10
                                font.bold: true
                                font.letterSpacing: 1.1
                                font.family: Properties.fontFamily
                            }
                            Item {
                                Layout.fillWidth: true
                                implicitHeight: 34
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Properties.radius + 2
                                    border.width: navRow.selected || navMouse.containsMouse ? 1.5 : 0
                                    border.color: Colors.fade(navRow.selected ? 0.24 : 0.14)
                                    gradient: ButtonGradient { hovered: navRow.selected }
                                    opacity: navRow.selected ? 1 : navMouse.containsMouse ? 0.6 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10
                                    Item {
                                        implicitWidth: 18
                                        implicitHeight: 18
                                        // an account: its color with its first letter
                                        Rectangle {
                                            visible: !!navRow.modelData.color
                                            anchors.centerIn: parent
                                            width: 18; height: 18; radius: 9
                                            color: navRow.modelData.color || "transparent"
                                            opacity: navRow.modelData.dim ? 0.4 : 1
                                            Text {
                                                anchors.centerIn: parent
                                                text: (navRow.modelData.label ?? "").charAt(0).toUpperCase()
                                                color: Colors.background
                                                font.pixelSize: 9
                                                font.bold: true
                                                font.family: Properties.fontFamily
                                            }
                                        }
                                        Text {
                                            visible: !navRow.modelData.color
                                            anchors.centerIn: parent
                                            text: navRow.modelData.icon ?? ""
                                            color: navRow.selected || (navRow.modelData.action && navMouse.containsMouse) ? Colors.color6 : Colors.fade(0.55)
                                            font.pixelSize: 15
                                            font.family: Properties.fontFamily
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: navRow.modelData.label ?? ""
                                        color: navRow.selected ? Colors.ink : Colors.fade(navRow.modelData.action ? 0.55 : 0.78)
                                        font.pixelSize: 12
                                        font.bold: navRow.selected
                                        font.family: Properties.fontFamily
                                        elide: Text.ElideRight
                                    }
                                }
                                MouseArea {
                                    id: navMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: navRow.modelData.action ? root.actionPicked(navRow.modelData.id) : root.page = navRow.modelData.id
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Colors.fade(0.07) }

            // ── the picked page ──
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    text: root.current?.heading ?? root.current?.label ?? ""
                    color: Colors.ink
                    font.pixelSize: 15
                    font.bold: true
                    font.family: Properties.fontFamily
                    elide: Text.ElideRight
                }
                Flickable {
                    id: pageFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: pageCol.implicitHeight + 4
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height
                    ScrollBar.vertical: CalScrollBar { id: pageBar }
                    SmoothWheel { flick: pageFlick; step: 140 }
                    ColumnLayout {
                        id: pageCol
                        width: pageFlick.width - (pageBar.visible ? 12 : 2)
                        spacing: 8
                    }
                }
            }
        }
    }
}
