import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import "../controlcenter"

// Color value: swatch + hex field. The swatch opens a picker with the
// pywal palette (Colors) and an opacity slider.
// Hex is #rrggbb or #aarrggbb (Qt order, alpha first).
// With canLink, a pywal chip links the setting to that palette slot instead
// of copying its hex, so it follows every wallpaper change; typing a hex
// sets a fixed color again.
RowLayout {
    id: root

    property color value: Colors.ink
    property bool canLink: false
    property string link: ""     // pywal color name it follows ("color4"), "" = fixed
    signal edited(color value)
    signal linked(string name, real alpha)

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
            border.color: Colors.fade(swatchMouse.containsMouse || picker.visible ? 0.4 : 0.2)

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
        // follows the wallpaper
        Rectangle {
            visible: root.link !== ""
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: -3
            width: 14; height: 14; radius: 7
            color: Colors.background
            border.width: 1
            border.color: Colors.fade(0.3)
            Text {
                anchors.centerIn: parent
                text: "󰸉"
                color: Colors.ink
                font.pixelSize: 8
                font.family: Properties.fontFamily
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
            // the app window's zoom (Ctrl +/−): popups are drawn above it, not inside
            scale: AppZoom.at(parent)
            transformOrigin: Popup.TopLeft
            y: swatch.height + 6
            x: Math.min(0, -(width - swatch.width) / 2)
            padding: 12
            closePolicy: Popup.CloseOnPressOutsideParent | Popup.CloseOnEscape   // the button itself toggles it

            background: Rectangle {
                radius: Properties.popupRadius
                color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.97)
                border.width: Properties.panelBorderWidth
                border.color: Properties.panelBorder
            }

            contentItem: ColumnLayout {
                spacing: 10

                Text {
                    text: root.canLink ? "Wallpaper colors (follow wallpaper changes)" : "Palette"
                    color: Colors.fade(0.55)
                    font.pixelSize: 11
                    font.bold: true
                    font.family: Properties.fontFamily
                }

                Grid {
                    columns: 10
                    spacing: 6
                    Repeater {
                        // name = Colors property it links to; white/black are always fixed
                        model: ["foreground", "background", "#ffffff", "#000000",
                                "color1", "color2", "color3", "color4", "color5", "color6",
                                "color7", "color8", "color9", "color10", "color11", "color12",
                                "color13", "color14", "color15", "color0"]
                        Rectangle {
                            id: chip
                            required property string modelData
                            readonly property bool isWal: !modelData.startsWith("#")
                            readonly property bool selected: isWal && root.link === modelData
                            width: 22
                            height: 22
                            radius: 6
                            color: isWal ? Colors[modelData] : modelData
                            border.width: selected ? 2 : 1.5
                            border.color: selected ? Colors.ink : Colors.fade(chipMouse.containsMouse ? 0.6 : 0.18)
                            scale: chipMouse.containsMouse ? 1.12 : 1
                            Behavior on scale { NumberAnimation { duration: 100 } }
                            MouseArea {
                                id: chipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                // keep the current opacity
                                onClicked: {
                                    if (chip.isWal && root.canLink) root.linked(chip.modelData, root.value.a)
                                    else root.edited(root.withAlpha(chip.color, root.value.a))
                                }
                            }
                            ToolTip.visible: chip.isWal && chipMouse.containsMouse
                            ToolTip.text: chip.modelData
                            ToolTip.delay: 400
                        }
                    }
                }

                RowLayout {
                    spacing: 10
                    Text {
                        text: "Opacity"
                        color: Colors.fade(0.55)
                        font.pixelSize: 11
                        font.bold: true
                        font.family: Properties.fontFamily
                    }
                    CCSlider {
                        Layout.fillWidth: true
                        value: root.value.a
                        onMoved: {
                            const a = Math.round(value * 100) / 100
                            if (root.link !== "") root.linked(root.link, a)
                            else root.edited(root.withAlpha(root.value, a))
                        }
                    }
                    Text {
                        Layout.preferredWidth: 34
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(root.value.a * 100) + "%"
                        color: Colors.ink
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
        // a linked color shows its pywal name; typing a hex makes it fixed
        function shown() { return root.link !== "" ? root.link : root.toHex(root.value) }
        text: shown()
        onActiveFocusChanged: if (activeFocus && root.link !== "") text = root.toHex(root.value)
        onEditingFinished: {
            const hex = root.toHex(root.value)
            // leaving a linked color's field untouched keeps the link
            if (/^#([0-9a-f]{6}|[0-9a-f]{8})$/i.test(text)
                    && !(root.link !== "" && text.toLowerCase() === hex.toLowerCase()))
                root.edited(text)
            text = Qt.binding(() => field.shown())
        }
    }
}
