import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// New group / rename a group: its name and icon.
//   GroupDialog { id: gd }   gd.start(null) = new, gd.start(group) = edit
//   addTo: a server that goes into the new group right away (from its menu)
Modal {
    id: root

    cardWidth: 440
    property var group: null
    property string addTo: ""
    property string fName: ""
    property string fIcon: "󰒍"

    function start(g, server) {
        group = g
        addTo = server ?? ""
        fName = g?.name ?? ""
        fIcon = g?.icon ?? ServerStore.groupIcons[ServerStore.groups.length % ServerStore.groupIcons.length]
        open()
        nameField.forceActiveFocus()
    }
    function save() {
        const n = fName.trim()
        if (n === "") return
        if (group) ServerStore.updateGroup(group.id, { name: n, icon: fIcon })
        else {
            const id = ServerStore.addGroup(n, fIcon)
            if (addTo && id) ServerStore.toggleGroup(addTo, id)
        }
        close()
    }

    ColumnLayout {
        width: parent.width
        spacing: Tokens.space.s14

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s12
            Rectangle {
                implicitWidth: 38; implicitHeight: 38; radius: Tokens.radius.xl
                color: Colors.alpha(Colors.accent, 0.14)
                Text {
                    id: gicon
                    anchors.centerIn: parent
                    text: root.fIcon
                    color: Colors.accent
                    font.pixelSize: Tokens.font.title
                    font.family: Properties.fontFamily
                    Behavior on text { SequentialAnimation {
                        NumberAnimation { target: gicon; property: "scale"; to: 0.6; duration: Anim.instant }
                        PropertyAction {}
                        NumberAnimation { target: gicon; property: "scale"; to: 1; duration: Anim.normal; easing.type: Anim.pop }
                    } }
                }
            }
            Text {
                Layout.fillWidth: true
                text: root.group ? "Edit group" : "New group"
                color: Colors.ink
                font.pixelSize: Tokens.font.subtitle
                font.bold: true
                font.family: Properties.fontFamily
            }
            IconButton { implicitWidth: 30; implicitHeight: 30; icon: "󰅖"; tooltip: "Close"; onClicked: root.close() }
        }

        SearchField {
            id: nameField
            Layout.fillWidth: true
            icon: ""
            clearable: false
            placeholderText: "Group name, e.g. Media"
            text: root.fName
            onTextChanged: root.fName = text
            onAccepted: root.save()
        }

        Flow {
            Layout.fillWidth: true
            spacing: Tokens.space.s4
            Repeater {
                model: ServerStore.groupIcons
                IconButton {
                    required property string modelData
                    implicitWidth: 34; implicitHeight: 34
                    icon: modelData
                    tooltip: "Icon"
                    active: root.fIcon === modelData
                    onClicked: root.fIcon = modelData
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            ActionButton { text: "Cancel"; variant: "ghost"; onClicked: root.close() }
            ActionButton { icon: "󰆓"; text: root.group ? "Save" : "Create"; variant: "primary"; interactive: root.fName.trim() !== ""; onClicked: root.save() }
        }
    }
}
