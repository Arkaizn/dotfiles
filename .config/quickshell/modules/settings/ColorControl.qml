import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import "../controlcenter"

// Color value: swatch + hex field. The swatch opens a picker with the
// pywal palette (Colors) and an opacity slider.
// Hex is #rrggbb or #aarrggbb (Qt order, alpha first).
RowLayout {
    id: root

    property color value: "white"
    signal edited(color value)

    spacing: 8

    function hex2(x) { return Math.round(x * 255).toString(16).padStart(2, "0") }
    function toHex(c) { return "#" + (c.a < 1 ? hex2(c.a) : "") + hex2(c.r) + hex2(c.g) + hex2(c.b) }
    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    // swatch
    Item {
        id: swatch
        implicitWidth: Properties.buttonHeight
        implicitHeight: Properties.buttonHeight

        Rectangle {
            id: frame
            anchors.fill: parent
            radius: Properties.radius
            clip: true
            color: "#808080"
            border.width: 1.5
            border.color: Qt.rgba(1, 1, 1, swatchMouse.containsMouse || picker.visible ? 0.4 : 0.2)

            // checkerboard so transparency shows
            Grid {
                anchors.fill: parent
                columns: 4
                Repeater {
                    model: 16
                    Rectangle {
                        required property int index
                        width: frame.width / 4
                        height: frame.height / 4
                        color: (Math.floor(index / 4) + index) % 2 ? "#9a9a9a" : "#5a5a5a"
                    }
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: root.value
                border.width: 1.5
                border.color: parent.border.color
            }
        }
        scale: swatchMouse.pressed ? Properties.onPressedButtonScale
             : swatchMouse.containsMouse ? Properties.onEnteredButtonScale : 1
        Behavior on scale { NumberAnimation { duration: Properties.bDuration; easing.type: Easing.OutCubic } }

        MouseArea {
            id: swatchMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: picker.visible ? picker.close() : picker.open()
        }

        Popup {
            id: picker
            y: swatch.height + 6
            x: Math.min(0, -(width - swatch.width) / 2)
            padding: 12
            closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape

            background: Rectangle {
                radius: Properties.popupRadius
                color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.97)
                border.width: Properties.panelBorderWidth
                border.color: Properties.panelBorder
            }

            contentItem: ColumnLayout {
                spacing: 10

                Text {
                    text: "Palette"
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font.pixelSize: 11
                    font.bold: true
                    font.family: Properties.fontFamily
                }

                Grid {
                    columns: 10
                    spacing: 6
                    Repeater {
                        model: [Colors.foreground, Colors.background, "#ffffff", "#000000",
                                Colors.color1, Colors.color2, Colors.color3, Colors.color4, Colors.color5, Colors.color6,
                                Colors.color7, Colors.color8, Colors.color9, Colors.color10, Colors.color11, Colors.color12,
                                Colors.color13, Colors.color14, Colors.color15, Colors.color0]
                        Rectangle {
                            id: chip
                            required property color modelData
                            width: 22
                            height: 22
                            radius: 6
                            color: modelData
                            border.width: 1.5
                            border.color: Qt.rgba(1, 1, 1, chipMouse.containsMouse ? 0.6 : 0.18)
                            scale: chipMouse.containsMouse ? 1.12 : 1
                            Behavior on scale { NumberAnimation { duration: 100 } }
                            MouseArea {
                                id: chipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                // keep the current opacity
                                onClicked: root.edited(root.withAlpha(chip.modelData, root.value.a))
                            }
                        }
                    }
                }

                RowLayout {
                    spacing: 10
                    Text {
                        text: "Opacity"
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.pixelSize: 11
                        font.bold: true
                        font.family: Properties.fontFamily
                    }
                    CCSlider {
                        Layout.fillWidth: true
                        value: root.value.a
                        onMoved: root.edited(root.withAlpha(root.value, Math.round(value * 100) / 100))
                    }
                    Text {
                        Layout.preferredWidth: 34
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(root.value.a * 100) + "%"
                        color: "white"
                        font.pixelSize: 11
                        font.family: Properties.fontFamily
                    }
                }
            }
        }
    }

    SearchField {
        id: field
        Layout.preferredWidth: 120
        implicitHeight: Properties.buttonHeight
        icon: ""
        clearable: false
        leftPadding: 10
        rightPadding: 10
        font.capitalization: Font.AllUppercase
        text: root.toHex(root.value)
        onEditingFinished: {
            if (/^#([0-9a-f]{6}|[0-9a-f]{8})$/i.test(text)) root.edited(text)
            text = Qt.binding(() => root.toHex(root.value))
        }
    }
}
