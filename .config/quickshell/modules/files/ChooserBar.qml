import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import "lib/FmChooser.js" as FmChooser
import "lib/FmIcons.js" as FmIcons

// The bar under the folder while the window is another app's Open / Save
// dialog (FilesWindow.chooser, a request from filesd/portal.py): the name to
// save as, the app's file type filters and extra options, Cancel and the one
// button that answers. What it would take is said in words next to it.
//   ChooserBar { req; filterIndex; choiceValues: { id: value }; hint; canAccept
//                onAccept · onCancel · onFilterPicked: i => … · onChoicePicked: (id, value) => … }
//   name (the typed file name) · focusName() (the stem selected, like every save dialog)
Rectangle {
    id: root

    required property var req
    property alias name: field.text
    property int filterIndex: -1
    property var choiceValues: ({})
    property string hint: ""
    property bool canAccept: true
    signal accept()
    signal cancel()
    signal filterPicked(int index)
    signal choicePicked(string id, string value)

    readonly property bool saving: req.mode === "save"
    readonly property var filters: req.filters ?? []
    readonly property var choices: req.choices ?? []

    function focusName() {
        field.forceActiveFocus()
        const dot = field.text.lastIndexOf(".")
        if (dot > 0) field.select(0, dot)
        else field.selectAll()
    }

    implicitHeight: col.implicitHeight + 2 * Tokens.space.s10
    radius: Math.max(6, Compositor.appRadius - 2)
    color: Colors.card
    border.width: Properties.panelBorderWidth
    border.color: Properties.cardBorder

    // rises in with the window
    opacity: 0
    transform: Translate { id: rise; y: Tokens.space.s12 }
    Component.onCompleted: appear.start()
    ParallelAnimation {
        id: appear
        NumberAnimation { target: root; property: "opacity"; to: 1; duration: Anim.normal; easing.type: Anim.standard }
        NumberAnimation { target: rise; property: "y"; to: 0; duration: Anim.medium; easing.type: Anim.emphasized }
    }

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: Tokens.space.s10
        spacing: Tokens.space.s8

        // which files show (the app's type filters), and the app's own options (an encoding, "read only" …)
        Flow {
            visible: root.filters.length > 0 || root.choices.length > 0
            Layout.fillWidth: true
            spacing: Tokens.space.s10
            Dropdown {
                visible: root.filters.length > 0
                width: Math.min(Tokens.size.row * 7, root.width - 2 * Tokens.space.s10)
                listWidth: Tokens.size.row * 8
                options: root.filters.map((f, i) => ({ label: FmChooser.label(f), value: i }))
                value: root.filterIndex
                onEdited: v => root.filterPicked(v)
            }
            Repeater {
                model: root.choices
                Row {
                    id: choice
                    required property var modelData
                    readonly property bool flag: (modelData.options ?? []).length === 0
                    readonly property string value: root.choiceValues[modelData.id] ?? modelData.value ?? ""
                    spacing: Tokens.space.s8
                    height: Properties.buttonHeight
                    Checkbox {
                        visible: choice.flag
                        anchors.verticalCenter: parent.verticalCenter
                        // (a Checkbox cuts its label to its own width: give it the label's)
                        width: Math.min(flagWidth.width + Tokens.space.s24 * 2, root.width - 2 * Tokens.space.s10)
                        label: choice.modelData.label
                        checked: choice.value === "true"
                        onClicked: root.choicePicked(choice.modelData.id, checked ? "false" : "true")
                        TextMetrics { id: flagWidth; text: choice.modelData.label; font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily }
                    }
                    Text {
                        visible: !choice.flag
                        anchors.verticalCenter: parent.verticalCenter
                        text: choice.modelData.label
                        color: Colors.fade(0.6)
                        font.pixelSize: Tokens.font.small
                        font.family: Properties.fontFamily
                        textFormat: Text.PlainText
                    }
                    Dropdown {
                        visible: !choice.flag
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: Tokens.size.row * 4
                        options: (choice.modelData.options ?? []).map(o => ({ label: o.label, value: o.id }))
                        value: choice.value
                        onEdited: v => root.choicePicked(choice.modelData.id, v)
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s8

            SearchField {
                id: field
                visible: root.saving
                Layout.fillWidth: true
                Layout.minimumWidth: Tokens.size.row * 3
                icon: FmIcons.g.file
                placeholderText: "File name"
                Accessible.name: "File name"
                onAccepted: root.accept()
                Keys.onEscapePressed: root.cancel()
            }
            // open / select: what the button would take
            Text {
                visible: !root.saving
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.space.s4
                text: root.hint
                color: Colors.fade(root.canAccept ? 0.75 : 0.45)
                font.pixelSize: Tokens.font.small
                font.family: Properties.fontFamily
                elide: Text.ElideMiddle
                textFormat: Text.PlainText
            }
            ActionButton { text: "Cancel"; variant: "ghost"; onClicked: root.cancel() }
            ActionButton {
                text: FmChooser.verb(root.req)
                variant: "primary"
                interactive: root.canAccept
                onClicked: root.accept()
            }
        }
    }
}
