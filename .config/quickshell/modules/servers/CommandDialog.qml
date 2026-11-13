import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services

// "Run command": a shell snippet on some servers over SSH (as the SSH user;
// sudo needs a NOPASSWD rule, it can't ask). Saved commands live in servers.json.
// The output streams into the activity panel (ServerRuns "command").
//   CommandDialog { id: c }   c.start(["svs-docker01", …])
Modal {
    id: root

    cardWidth: 680
    property string cmdId: ""               // the saved command being edited ("" = new)
    property string fName: ""
    property string fScript: ""
    property var targets: []

    function start(names) {
        targets = (names ?? []).slice()
        if (cmdId && !ServerStore.commands.some(c => c.id === cmdId)) cmdId = ""
        open()
    }
    function pick(c) { cmdId = c ? c.id : ""; fName = c ? c.name : ""; fScript = c ? c.script : "" }
    function toggle(n) { targets = targets.includes(n) ? targets.filter(x => x !== n) : targets.concat([n]) }
    function saveCmd() { if (fScript.trim()) cmdId = ServerStore.saveCommand({ id: cmdId, name: fName || "Command", script: fScript }) }

    ColumnLayout {
        width: parent.width
        spacing: Tokens.space.s12

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s12
            Rectangle {
                implicitWidth: 38; implicitHeight: 38; radius: Tokens.radius.xl
                color: Colors.alpha(Colors.accent, 0.14)
                Text { anchors.centerIn: parent; text: "󰆍"; color: Colors.accent; font.pixelSize: Tokens.font.title; font.family: Properties.fontFamily }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.space.s1
                Text { text: "Run a command"; color: Colors.ink; font.pixelSize: Tokens.font.subtitle; font.bold: true; font.family: Properties.fontFamily }
                Text { Layout.fillWidth: true; text: "Runs with bash as your SSH user, up to 4 servers at once; the output shows below the servers"
                       color: Colors.fade(0.5); font.pixelSize: Tokens.font.caption; font.family: Properties.fontFamily; wrapMode: Text.Wrap }
            }
            IconButton { implicitWidth: 30; implicitHeight: 30; icon: "󰅖"; tooltip: "Close"; onClicked: root.close() }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s12

            // saved commands
            ColumnLayout {
                Layout.preferredWidth: 190
                Layout.alignment: Qt.AlignTop
                spacing: Tokens.space.s2
                Text { text: "Saved"; color: Colors.textSecondary; font.pixelSize: Tokens.font.caption; font.bold: true; font.family: Properties.fontFamily }
                Repeater {
                    model: [{ id: "", name: "New command", icon: "󰐕" }].concat(ServerStore.commands)
                    Pressable {
                        id: ci
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 28
                        onClicked: root.pick(modelData.id ? modelData : null)
                        Rectangle {
                            anchors.fill: parent
                            radius: Tokens.radius.md
                            color: root.cmdId === ci.modelData.id ? Colors.fade(0.12) : ci.hovered ? Colors.fade(0.06) : "transparent"
                            Behavior on color { ColorAnimation { duration: Anim.fast } }
                        }
                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.space.s8
                            verticalAlignment: Text.AlignVCenter
                            text: (ci.modelData.icon ?? "󰆍") + "  " + ci.modelData.name
                            color: Colors.ink; font.pixelSize: Tokens.font.small; font.family: Properties.fontFamily; elide: Text.ElideRight
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.space.s8
                SearchField {
                    Layout.fillWidth: true
                    icon: ""; clearable: false
                    placeholderText: "Name, e.g. Disk space"
                    text: root.fName
                    onTextChanged: root.fName = text
                }
                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 130
                    TextArea {
                        id: area
                        placeholderText: "df -h /\n# docker ps --format '{{.Names}}: {{.Status}}'"
                        text: root.fScript
                        onTextChanged: if (text !== root.fScript) root.fScript = text
                        wrapMode: TextEdit.NoWrap
                        color: Properties.color
                        placeholderTextColor: Colors.fade(0.35)
                        selectionColor: Colors.fade(0.28)
                        font.pixelSize: Tokens.font.small
                        font.family: Properties.fontFamily
                        leftPadding: Tokens.space.s14; rightPadding: Tokens.space.s14; topPadding: Tokens.space.s10
                        background: FieldBackground { focused: area.activeFocus }
                    }
                }
                RowLayout {
                    ActionButton { icon: "󰆓"; text: root.cmdId ? "Save" : "Save as command"; interactive: root.fScript.trim() !== ""; onClicked: root.saveCmd() }
                    ActionButton { visible: root.cmdId !== ""; icon: "󰆴"; text: "Delete"; variant: "ghost"
                                   onClicked: { ServerStore.deleteCommand(root.cmdId); root.pick(null) } }
                }
            }
        }

        // on which servers (group chips pick a whole group)
        RowLayout {
            Layout.fillWidth: true
            Text { text: "On"; color: Colors.textSecondary; font.pixelSize: Tokens.font.caption; font.bold: true; font.family: Properties.fontFamily }
            Flow {
                Layout.fillWidth: true
                spacing: Tokens.space.s4
                Repeater {
                    model: ServerStore.groups
                    FilterChip {
                        required property var modelData
                        readonly property var members: ServerStore.active.filter(s => s.groups.includes(modelData.id)).map(s => s.name)
                        icon: modelData.icon; text: modelData.name
                        checked: members.length > 0 && members.every(n => root.targets.includes(n))
                        onToggled: root.targets = checked ? root.targets.filter(n => !members.includes(n))
                                                          : root.targets.concat(members.filter(n => !root.targets.includes(n)))
                    }
                }
            }
        }
        Flow {
            Layout.fillWidth: true
            spacing: Tokens.space.s4
            Repeater {
                model: ServerStore.active
                FilterChip {
                    required property var modelData
                    text: modelData.name
                    dim: ServerStore.info[modelData.name]?.reachable === false
                    checked: root.targets.includes(modelData.name)
                    onToggled: root.toggle(modelData.name)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            ActionButton { text: "Cancel"; variant: "ghost"; onClicked: root.close() }
            ActionButton {
                icon: "󰐊"
                text: "Run on " + root.targets.length + (root.targets.length === 1 ? " server" : " servers")
                variant: "primary"
                interactive: root.targets.length > 0 && root.fScript.trim() !== ""
                onClicked: {
                    ServerRuns.start("command", root.targets, { title: root.fName || "Command", script: root.fScript })
                    root.close()
                }
            }
        }
    }
}
