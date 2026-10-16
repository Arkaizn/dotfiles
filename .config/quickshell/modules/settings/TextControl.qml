import QtQuick
import QtQuick.Controls
import qs.components
import qs.services

// Text value, saved on Enter / leaving the field.
// With `suggestions` (e.g. installed fonts) a filtered list drops down while typing.
SearchField {
    id: root

    property string value: ""
    property var suggestions: []
    signal edited(string value)

    implicitWidth: 260
    implicitHeight: Properties.buttonHeight
    icon: ""
    clearable: false
    text: value

    function commit(v) {
        list.close()
        if (v !== root.value) root.edited(v)
        root.text = Qt.binding(() => root.value)
    }

    onAccepted: commit(text)
    onEditingFinished: if (!list.visible) commit(text)
    onTextEdited: if (suggestions.length > 0) list.open()

    Keys.onDownPressed: if (list.visible) view.incrementCurrentIndex()
    Keys.onUpPressed: if (list.visible) view.decrementCurrentIndex()
    Keys.onReturnPressed: commit(list.visible && view.currentIndex >= 0 ? matches[view.currentIndex] : text)
    Keys.onEscapePressed: { list.close(); root.text = Qt.binding(() => root.value) }

    readonly property var matches: {
        const q = text.toLowerCase()
        return suggestions.filter(s => s.toLowerCase().includes(q)).slice(0, 40)
    }

    Popup {
        id: list
        y: root.height + 4
        width: root.width
        height: Math.min(view.contentHeight + 12, 220)
        padding: 6
        visible: false
        closePolicy: Popup.CloseOnPressOutside
        onOpened: view.currentIndex = -1

        background: Rectangle {
            radius: Properties.radius + 2
            color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.97)
            border.width: Properties.panelBorderWidth
            border.color: Properties.panelBorder
        }

        ListView {
            id: view
            anchors.fill: parent
            clip: true
            model: root.matches
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                id: entry
                required property string modelData
                required property int index
                width: ListView.view.width
                height: 28
                radius: Properties.radius
                color: entry.index === view.currentIndex || hover.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                Text {
                    anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    text: entry.modelData
                    color: entry.modelData === root.value ? Colors.color6 : "white"
                    font.pixelSize: 12
                    font.family: entry.modelData
                    elide: Text.ElideRight
                }
                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.commit(entry.modelData) }
            }
        }
    }
}
