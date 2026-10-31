import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// Editable list of values (addresses, DNS servers, search domains): chips
// with × plus a field to add more. Pasting "1.1.1.1, 8.8.8.8" adds both.
// `validate(value)` returns "" or what's wrong; invalid values aren't added.
//   ListField { values: [...]; validate: Net.isIPv4; onEdited: list => … }
ColumnLayout {
    id: root
    property var values: []
    property string placeholder: "Add…"
    property var validate: null
    property var presets: []              // [{ label, values: [] }] quick-fill buttons
    property var separators: /[\s,;]+/    // routes contain spaces: /[,;]+/
    property var normalize: null          // value → stored value (e.g. add a /24)
    signal edited(var values)

    property string problem: ""
    spacing: Tokens.space.s8

    function addFrom(text) {
        const parts = text.split(root.separators).map(x => x.trim()).filter(x => x !== "")
        if (parts.length === 0) return true
        const out = root.values.slice()
        for (const p of parts) {
            const err = root.validate ? root.validate(p) : ""
            if (err) { root.problem = "\"" + p + "\": " + err; return false }
            const v = root.normalize ? root.normalize(p) : p
            if (!out.includes(v)) out.push(v)
        }
        root.problem = ""
        root.edited(out)
        return true
    }

    Flow {
        Layout.fillWidth: true
        spacing: Tokens.space.s6
        visible: root.values.length > 0
        Repeater {
            model: root.values
            ValueChip {
                required property string modelData
                required property int index
                text: modelData
                removable: true
                invalid: root.validate ? root.validate(modelData) !== "" : false
                onRemoved: {
                    const out = root.values.slice()
                    out.splice(index, 1)
                    root.edited(out)
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.space.s6
        SearchField {
            id: input
            Layout.fillWidth: true
            implicitHeight: Properties.buttonHeight
            icon: "󰐕"
            clearable: false
            placeholderText: root.placeholder
            error: root.problem !== ""
            onTextEdited: root.problem = ""
            onAccepted: if (root.addFrom(text)) text = ""
            // leaving the field adds what's typed, like pressing Enter
            onActiveFocusChanged: if (!activeFocus && text !== "" && root.addFrom(text)) text = ""
        }
        Repeater {
            model: root.presets
            Rectangle {
                required property var modelData
                implicitWidth: pl.implicitWidth + 16
                implicitHeight: Properties.buttonHeight - 4
                radius: Tokens.radius.md
                color: Colors.fade(pm.containsMouse ? 0.12 : 0.06)
                border.width: 1
                border.color: Colors.fade(0.1)
                Behavior on color { ColorAnimation { duration: Anim.fast } }
                Text {
                    id: pl
                    anchors.centerIn: parent
                    text: parent.modelData.label
                    color: Colors.fade(0.75)
                    font.pixelSize: Tokens.font.caption
                    font.family: Properties.fontFamily
                }
                MouseArea {
                    id: pm
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.problem = ""; root.edited(parent.modelData.values.slice()) }
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        visible: root.problem !== ""
        text: root.problem
        color: Colors.red
        font.pixelSize: Tokens.font.caption
        font.family: Properties.fontFamily
        wrapMode: Text.WordWrap
    }
}
