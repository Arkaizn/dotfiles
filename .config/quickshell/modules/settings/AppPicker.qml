import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import "../controlcenter"

// Pick an installed app: type to search (name, generic name, command), or
// open the whole list with the chevron. ↑ / ↓ / Enter work while typing.
//   AppPicker { value: cmd; onPicked: (cmd, name) => … }
// value / picked: the app's command line (shell-quoted, field codes removed).
Item {
    id: root

    property string value: ""
    signal picked(string value, string name)

    implicitWidth: 300
    implicitHeight: Properties.buttonHeight

    // [{ label, value, hint, icon, search }]
    readonly property var apps: Array.from(DesktopEntries.applications.values)
        .filter(e => !e.noDisplay && (e.command ?? []).length > 0)
        .sort((a, b) => a.name.localeCompare(b.name))
        .map(e => {
            const cmd = e.command.map(c => /^[\w@%+=:,./-]+$/.test(c) ? c : "'" + c.replace(/'/g, "'\\''") + "'").join(" ")
            return { label: e.name, value: cmd, hint: e.genericName ?? "", icon: e.icon ?? "",
                     search: (e.name + " " + (e.genericName ?? "") + " " + cmd + " " + (e.keywords ?? []).join(" ")).toLowerCase() }
        })
    readonly property var current: apps.find(a => a.value === value) ?? null

    // while the field has focus its text is the search; otherwise the picked app
    property string query: ""
    readonly property var matches: {
        const q = query.trim().toLowerCase()
        return q === "" ? apps : apps.filter(a => a.search.includes(q))
    }

    function choose(a) {
        list.close()
        field.focus = false
        query = ""
        if (a) root.picked(a.value, a.label)
    }

    SearchField {
        id: field
        anchors.fill: parent
        icon: ""
        clearable: false
        leftPadding: 38
        rightPadding: 34
        placeholderText: "Search apps…"
        text: activeFocus ? root.query : (root.current?.label ?? "")
        onTextEdited: { root.query = text; view.currentIndex = 0; if (!list.visible) list.open() }
        onActiveFocusChanged: if (activeFocus) { root.query = ""; list.open() }
        Keys.onDownPressed: { if (!list.visible) list.open(); view.incrementCurrentIndex() }
        Keys.onUpPressed: view.decrementCurrentIndex()
        Keys.onReturnPressed: root.choose(root.matches[Math.max(0, view.currentIndex)])
        Keys.onEscapePressed: { list.close(); focus = false }

        // the picked app's icon (search icon while typing)
        Image {
            anchors { left: parent.left; leftMargin: 11; verticalCenter: parent.verticalCenter }
            width: 18; height: 18
            sourceSize: Qt.size(36, 36)
            visible: !field.activeFocus && root.current !== null
            source: root.current ? Quickshell.iconPath(root.current.icon, true) : ""
        }
        Text {
            anchors { left: parent.left; leftMargin: 13; verticalCenter: parent.verticalCenter }
            visible: field.activeFocus || root.current === null
            text: "󰍉"
            color: Colors.fade(0.45)
            font.pixelSize: 15
            font.family: Properties.fontFamily
        }
        // the whole list
        Item {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: 32
            Chevron { anchors.centerIn: parent; open: list.visible }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (list.visible) { list.close(); field.focus = false }
                    else { root.query = ""; list.open(); view.positionViewAtIndex(Math.max(0, root.apps.indexOf(root.current)), ListView.Center) }
                }
            }
        }
    }

    Popup {
        id: list
        // the app window's zoom (Ctrl +/−): popups are drawn above it, not inside
        scale: AppZoom.at(parent)
        transformOrigin: Popup.TopLeft
        y: root.height + 4
        width: root.width
        height: Math.min(Math.max(view.contentHeight, 30) + 12, 300)
        padding: 6
        closePolicy: Popup.CloseOnPressOutsideParent | Popup.CloseOnEscape
        onClosed: if (!field.activeFocus) root.query = ""

        // drops open
        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 }
                NumberAnimation { property: "y"; from: root.height - 4; to: root.height + 4; duration: 180; easing.type: Easing.OutCubic }
            }
        }
        exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 100 } }

        background: Rectangle {
            radius: Properties.radius + 2
            color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.97)
            border.width: Properties.panelBorderWidth
            border.color: Properties.panelBorder
        }

        Text {
            anchors.centerIn: parent
            visible: root.matches.length === 0
            text: "No app matches \"" + root.query + "\""
            color: Colors.fade(0.45)
            font.pixelSize: 12
            font.family: Properties.fontFamily
        }

        ListView {
            id: view
            anchors.fill: parent
            clip: true
            model: root.matches
            currentIndex: -1
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 0
            delegate: Rectangle {
                id: entry
                required property var modelData
                required property int index
                readonly property bool selected: modelData.value === root.value
                width: ListView.view.width
                height: 32
                radius: Properties.radius
                color: entry.index === view.currentIndex || hover.hovered ? Colors.fade(0.08)
                     : selected ? Colors.fade(0.05) : "transparent"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 10
                    spacing: 9
                    Image {
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        sourceSize: Qt.size(40, 40)
                        source: Quickshell.iconPath(entry.modelData.icon, true)
                        asynchronous: true
                    }
                    Text {
                        Layout.fillWidth: true
                        text: entry.modelData.label
                        color: entry.selected ? Colors.color6 : Colors.ink
                        font.pixelSize: 12
                        font.bold: entry.selected
                        font.family: Properties.fontFamily
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: text !== ""
                        Layout.maximumWidth: 120
                        text: entry.modelData.hint
                        color: Colors.fade(0.4)
                        font.pixelSize: 10
                        font.family: Properties.fontFamily
                        elide: Text.ElideRight
                    }
                }
                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.choose(entry.modelData) }
            }
        }
    }
}
