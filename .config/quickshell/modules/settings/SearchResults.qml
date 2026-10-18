import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// Search results of the settings app: one ranked list. Settings can be
// changed right here (with "Page › Section ›" to jump to them); everything
// else (pages, places on a page, keybinds, network profiles, …) is a row
// that goes there. ↑ / ↓ move the selection (kept in view), Enter opens.
ColumnLayout {
    id: root

    property var results: []           // [{ entry, score }], best first
    property string query: ""
    property int selected: 0
    property Flickable flick
    property string suggestion: ""     // "did you mean"
    property var pages: []             // for the empty state
    signal activate(var entry)
    signal suggestionPicked(string text)

    spacing: 14

    function ensureVisible(i) {
        const it = rep.itemAt(i)
        if (!it || !flick) return
        const y = it.mapToItem(flick.contentItem, 0, 0).y
        const h = it.height
        if (y < flick.contentY + 10) flick.contentY = Math.max(0, y - 20)
        else if (y + h > flick.contentY + flick.height - 10) flick.contentY = Math.min(flick.contentHeight - flick.height, y + h - flick.height + 20)
    }
    onSelectedChanged: Qt.callLater(() => ensureVisible(selected))

    // ── Count + keys ────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        visible: root.results.length > 0
        spacing: 10
        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            text: root.results.length + (root.results.length === 1 ? " result" : " results")
            color: Colors.fade(0.55)
            font.pixelSize: 12
            font.bold: true
            font.family: Properties.fontFamily
        }
        Repeater {
            model: [["↑↓", "move"], ["Enter", "open"], ["Esc", "clear"]]
            RowLayout {
                required property var modelData
                spacing: 5
                Rectangle {
                    implicitWidth: kt.implicitWidth + 10
                    implicitHeight: 18
                    radius: 5
                    color: Colors.fade(0.08)
                    border.width: 1
                    border.color: Colors.fade(0.14)
                    Text { id: kt; anchors.centerIn: parent; text: modelData[0]; color: Colors.ink; font.pixelSize: 10; font.bold: true; font.family: Properties.fontFamily }
                }
                Text { text: modelData[1]; color: Colors.fade(0.45); font.pixelSize: 10; font.family: Properties.fontFamily }
            }
        }
    }

    // ── The list ────────────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        visible: root.results.length > 0
        implicitHeight: list.implicitHeight + 8
        radius: 14
        color: Colors.card
        border.width: Properties.panelBorderWidth
        border.color: Properties.cardBorder

        ColumnLayout {
            id: list
            y: 4
            width: parent.width
            spacing: 0

            Repeater {
                id: rep
                model: root.results
                ColumnLayout {
                    id: res
                    required property var modelData
                    required property int index
                    readonly property var e: modelData.entry
                    Layout.fillWidth: true
                    spacing: 0

                    // a little rise-in, staggered by rank
                    opacity: 0
                    property real lift: 6
                    transform: Translate { y: res.lift }
                    Component.onCompleted: inAnim.start()
                    SequentialAnimation {
                        id: inAnim
                        PauseAnimation { duration: Math.min(res.index, 10) * 18 }
                        ParallelAnimation {
                            NumberAnimation { target: res; property: "opacity"; to: 1; duration: 160 }
                            NumberAnimation { target: res; property: "lift"; to: 0; duration: 220; easing.type: Easing.OutCubic }
                        }
                    }

                    Rectangle {
                        visible: res.index > 0
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        implicitHeight: 1
                        color: Colors.fade(0.06)
                    }

                    // a setting: change it right here
                    Loader {
                        Layout.fillWidth: true
                        active: res.e.kind === "setting"
                        visible: active
                        sourceComponent: SettingItem {
                            store: res.e.store
                            spec: res.e.spec
                            query: root.query
                            crumb: res.e.crumb
                            selected: res.index === root.selected
                            sub: false
                            parentOn: res.e.parentOn ?? true
                            onOpenRequested: root.activate(res.e)
                        }
                    }
                    // anything else: go there
                    Loader {
                        Layout.fillWidth: true
                        Layout.leftMargin: 3
                        Layout.rightMargin: 3
                        active: res.e.kind !== "setting"
                        visible: active
                        sourceComponent: SearchRow {
                            entry: res.e
                            query: root.query
                            selected: res.index === root.selected
                            onActivated: root.activate(res.e)
                        }
                    }
                }
            }
        }
    }

    // ── Nothing found ───────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: 30
        visible: root.results.length === 0
        spacing: 14

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "󰍉"
            color: Colors.fade(0.25)
            font.pixelSize: 40
            font.family: Properties.fontFamily
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Nothing for \"" + root.query + "\""
            color: Colors.ink
            font.pixelSize: 15
            font.bold: true
            font.family: Properties.fontFamily
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            visible: root.suggestion !== ""
            spacing: 8
            Text { text: "Did you mean"; color: Colors.fade(0.55); font.pixelSize: 12; font.family: Properties.fontFamily }
            ActionButton {
                icon: "󰍉"
                text: root.suggestion
                primary: true
                onClicked: root.suggestionPicked(root.suggestion)
            }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 10
            text: "Or go to a page"
            color: Colors.fade(0.45)
            font.pixelSize: 11
            font.family: Properties.fontFamily
        }
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 40
            Layout.rightMargin: 40
            spacing: 6
            Repeater {
                model: root.pages
                ActionButton {
                    required property var modelData
                    icon: modelData.icon
                    text: modelData.title
                    onClicked: root.activate({ kind: "page", pageId: modelData.id })
                }
            }
        }
    }
}
