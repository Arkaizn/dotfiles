import QtQuick
import QtQuick.Layouts
import qs.services

// Slider + exact value field. `step` decides the rounding (1 = whole numbers).
//   NumberField { from: 0; to: 600; step: 10; value: v; accessibleName: "Animation length"; onEdited: x => v = x }
RowLayout {
    id: root

    property real value: 0
    property real from: 0
    property real to: 100
    property real step: 1
    property string accessibleName: ""
    signal edited(real value)

    spacing: Tokens.space.s10

    readonly property int decimals: step >= 1 ? 0 : Math.max(0, Math.ceil(-Math.log10(step) - 1e-9))

    function snap(v) {
        v = Math.round(v / step) * step
        return Number(v.toFixed(decimals))
    }

    LevelSlider {
        id: slider
        // gives way first when the row is tight (long label, narrow window)
        Layout.fillWidth: true
        Layout.preferredWidth: 200
        Layout.maximumWidth: 200
        Layout.minimumWidth: 80
        from: root.from
        to: root.to
        stepSize: root.step
        value: root.value
        accessibleName: root.accessibleName
        onMoved: root.edited(root.snap(value))
    }

    SearchField {
        id: field
        Layout.preferredWidth: 72
        implicitHeight: Properties.buttonHeight
        icon: ""
        clearable: false
        horizontalAlignment: TextInput.AlignHCenter
        leftPadding: Tokens.space.s8
        rightPadding: Tokens.space.s8
        text: root.value.toFixed(root.decimals)
        validator: DoubleValidator { notation: DoubleValidator.StandardNotation }
        // typed values may go past the slider range; the slider just pins at its end
        onEditingFinished: {
            const v = parseFloat(text.replace(",", "."))
            if (!isNaN(v)) root.edited(root.snap(v))
            text = Qt.binding(() => root.value.toFixed(root.decimals))
        }
    }
}
