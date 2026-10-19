import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// Floats under the bar while it's edited live (lives in the bar's own surface,
// so modules can be dragged between the two): modules that aren't on the bar
// and ones that are placed but not showing right now — drag them onto the bar;
// drag a module from the bar onto this to take it off. Reset, settings, Done.
Rectangle {
    id: root

    required property Item editor       // BarEditLayer of this bar
    readonly property var unused: BarLayout.unused(BarLayout.layoutFor(editor.screenName))
    readonly property bool target: editor.dropZone === "hide"

    visible: editor.editing
    width: Math.min(920, col.implicitWidth + 28)
    height: col.implicitHeight + 24
    radius: Properties.panelRadius
    color: Properties.panelColor
    border.width: Properties.panelBorderWidth
    border.color: Properties.panelBorder

    // swallow clicks so they don't fall through to the windows below
    MouseArea { anchors.fill: parent }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12; leftMargin: 14; rightMargin: 14 }
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                text: "󰏫"
                color: Colors.color6
                font.pixelSize: 18
                font.family: Properties.fontFamily
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    text: "Editing the bar"
                    color: Colors.ink
                    font.pixelSize: 13
                    font.bold: true
                    font.family: Properties.fontFamily
                }
                Text {
                    text: (root.editor.editScreen === "" ? (Quickshell.screens.length > 1 ? "All monitors" : "Shared layout")
                                                         : "Only " + root.editor.editScreen)
                          + "  ·  drag to move  ·  drop here or − to remove"
                    color: Colors.fade(0.5)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                }
            }
            Item { Layout.preferredWidth: 20 }
            IconButton {
                icon: "󰒓"
                tooltip: "Bar layout settings"
                onClicked: { EditMode.stop(); Quickshell.execDetached(["qs", "ipc", "call", "settings", "openPage", "barlayout"]) }
            }
            IconButton {
                icon: "󰑓"
                tooltip: "Reset to the default layout"
                onClicked: BarLayout.reset(root.editor.editScreen)
            }
            IconButton {
                icon: "󰄬"
                active: true
                tooltip: "Done"
                onClicked: EditMode.stop()
            }
        }

        Text {
            text: root.unused.length > 0 ? "Not on the bar — drag one onto the bar" : "Every module is on the bar"
            color: Colors.fade(0.45)
            font.pixelSize: 11
            font.family: Properties.fontFamily
        }
        Flow {
            Layout.fillWidth: true
            Layout.preferredWidth: 660
            visible: root.unused.length > 0
            spacing: 6
            Repeater {
                model: root.unused
                ModuleChip { editor: root.editor; modId: modelData }
            }
        }

        Text {
            visible: root.editor.stateHidden.length > 0
            text: "On the bar, but not showing right now"
            color: Colors.fade(0.45)
            font.pixelSize: 11
            font.family: Properties.fontFamily
        }
        Flow {
            Layout.fillWidth: true
            Layout.preferredWidth: 660
            visible: root.editor.stateHidden.length > 0
            spacing: 6
            Repeater {
                model: root.editor.stateHidden
                ModuleChip { editor: root.editor; modId: modelData; placed: true }
            }
        }
    }

    DropZone {
        anchors.fill: parent
        radius: parent.radius
        shown: root.editor.dragId !== ""
        hot: root.target
    }
}
