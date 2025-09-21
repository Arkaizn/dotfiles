// ~/.config/quickshell/shell.qml
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../wal/templates/Colors.qml"


// Single bar at the top of the focused screen
PanelWindow {
    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: 36

    // simple background; style later once it's working
    Rectangle {
        anchors.fill: parent
        radius: 12
        color: '#6e3b2e0e'
        border.color: Colors.color1
        border.width: 1
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 16

        // ================= LEFT =================
        RowLayout {
            Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
            spacing: 10

            // notifications
            Text {
                text: "󰣇"
                font.pixelSize: 15
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        // run one-shot command
                        Qt.createQmlObject('import Quickshell.Io; QtObject { Process { command: ["bash","-lc","swaync-client -t -sw"]; running: true } }',
                                           parent, "NotifyClick");
                    }
                }
            }

            // clock
            Row {
                spacing: 6
                SystemClock { id: sysclock; precision: SystemClock.Seconds }
                Text {
                    id: clockText
                    font.pixelSize: 15
                    text: Qt.formatDateTime(sysclock.date, "dd.MM.yyyy hh:mm:ss ap")
                }
            }

            // pacman updates
            Text {
                id: pacmanText
                font.pixelSize: 15
                text: "󰅢 …"
                Process {
                    id: pacmanProc
                    command: ["bash","-lc","checkupdates 2>/dev/null | wc -l"]
                    running: true
                    stdout: StdioCollector {
                        onStreamFinished: pacmanText.text = "󰅢 " + this.text.trim()
                    }
                }
                Timer {
                    interval: 600000; running: true; repeat: true
                    onTriggered: pacmanProc.running = true
                }
            }

            // dotfiles pull/push
            Text {
                text: "󰇚"; font.pixelSize: 15
                MouseArea {
                    anchors.fill: parent
                    onClicked: Qt.createQmlObject('import Quickshell.Io; QtObject { Process { command: ["bash","-lc","kitty -e bash ~/git/dotfiles/scripts/config/update.sh"]; running: true } }', parent, "Pull")
                }
            }
            Text {
                text: "󰕒"; font.pixelSize: 15
                MouseArea {
                    anchors.fill: parent
                    onClicked: Qt.createQmlObject('import Quickshell.Io; QtObject { Process { command: ["bash","-lc","kitty -e bash ~/git/dotfiles/scripts/config/push.sh"]; running: true } }', parent, "Push")
                }
            }
        }

        // spacer
        Item { Layout.fillWidth: true }

        // ================= CENTER =================
        RowLayout {
            Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
            spacing: 12

            // GPU usage
            Text {
                id: gpuUsageText; font.pixelSize: 15; text: "󰢮 …%"
                Process {
                    id: gpuUsageProc
                    command: ["bash","-lc","nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits"]
                    running: true
                    stdout: StdioCollector { onStreamFinished: gpuUsageText.text = "󰢮 " + this.text.trim() + "%" }
                }
                Timer { interval: 2000; running: true; repeat: true; onTriggered: gpuUsageProc.running = true }
            }

            // CPU usage
            Text {
                id: cpuUsageText; font.pixelSize: 15; text: " …%"
                Process {
                    id: cpuUsageProc
                    // NOTE: use bash -lc; escape $ in QML string
                    command: ["bash","-lc","top -bn1 | awk '/^%?Cpu\\(s\\):/ {print 100 - \\$8}' | xargs printf '%.0f'"]
                    running: true
                    stdout: StdioCollector { onStreamFinished: cpuUsageText.text = " " + this.text.trim() + "%" }
                }
                Timer { interval: 2000; running: true; repeat: true; onTriggered: cpuUsageProc.running = true }
            }

            // Memory %
            Text {
                id: memText; font.pixelSize: 15; text: " …%"
                Process {
                    id: memProc
                    command: ["bash","-lc","free -h | awk '/Mem:/ {print int($3/$2*100)}'"]
                    running: true
                    stdout: StdioCollector { onStreamFinished: memText.text = " " + this.text.trim() + "%" }
                }
                Timer { interval: 2000; running: true; repeat: true; onTriggered: memProc.running = true }
            }

            // separator
            Text { text: "|"; font.pixelSize: 15; opacity: 0.6 }

            // Hyprland workspaces
            Row {
                spacing: 6
                Repeater {
                    model: Hyprland.workspaces
                    delegate: Text {
                        required property HyprlandWorkspace modelData
                        font.pixelSize: 15
                        text: ""
                        color: modelData.active ? "#88aaff" : "#fafbfc"
                        opacity: modelData.active ? 1.0 : 0.6
                        MouseArea {
                            anchors.fill: parent
                            onClicked: modelData.activate()
                        }
                    }
                }
            }

            // separator
            Text { text: "|"; font.pixelSize: 15; opacity: 0.6 }

            // GPU temp
            Text {
                id: gpuTempText; font.pixelSize: 15; text: "󰢮 …°C"
                Process {
                    id: gpuTempProc
                    command: ["bash","-lc","nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader"]
                    running: true
                    stdout: StdioCollector { onStreamFinished: gpuTempText.text = "󰢮 " + this.text.trim() + "°C" }
                }
                Timer { interval: 5000; running: true; repeat: true; onTriggered: gpuTempProc.running = true }
            }

            // CPU temp
            Text {
                id: cpuTempText; font.pixelSize: 15; text: " …"
                Process {
                    id: cpuTempProc
                    command: ["bash","-lc","sensors | grep 'Tctl' | awk '{print $2}' | sed 's/+//'"]
                    running: true
                    stdout: StdioCollector { onStreamFinished: cpuTempText.text = " " + this.text.trim() }
                }
                Timer { interval: 5000; running: true; repeat: true; onTriggered: cpuTempProc.running = true }
            }
        }

        // spacer
        Item { Layout.fillWidth: true }

        // ================= RIGHT =================
        RowLayout {
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            spacing: 10

            // headset (placeholder or your curl endpoint)
            Text {
                id: headsetText; font.pixelSize: 15; text: ""
                Process {
                    id: headsetProc
                    command: ["bash","-lc","curl -s http://127.0.0.1:27003/api/batteryStats | jq -r --arg k 1786e76c000400da '.data[$k].Level'"]
                    running: false // only run if service exists; set to true if you use this
                    stdout: StdioCollector { onStreamFinished: headsetText.text = " " + this.text.trim() + "%" }
                }
                //Timer { interval: 5000; running: false; repeat: true; onTriggered: headsetProc.running = true }
            }

            // volume
            Text {
                id: volText; font.pixelSize: 15; text: " …%"
                MouseArea {
                    anchors.fill: parent
                    onClicked: Qt.createQmlObject('import Quickshell.Io; QtObject { Process { command: ["bash","-lc","pavucontrol"]; running: true } }', parent, "VolClick")
                }
                Process {
                    id: volProc
                    command: ["bash","-lc","pamixer --get-volume"]
                    running: true
                    stdout: StdioCollector { onStreamFinished: volText.text = " " + this.text.trim() + "%" }
                }
                Timer { interval: 1000; running: true; repeat: true; onTriggered: volProc.running = true }
            }

            // network device (nmcli)
            Text {
                id: netText; font.pixelSize: 15; text: " …"
                Process {
                    id: netProc
                    command: ["bash","-lc","nmcli -t -f DEVICE,STATE d | grep -E ':connected' | cut -d: -f1 | head -n1"]
                    running: true
                    stdout: StdioCollector { onStreamFinished: netText.text = " " + (this.text.trim() === '' ? 'down' : this.text.trim()) }
                }
                Timer { interval: 5000; running: true; repeat: true; onTriggered: netProc.running = true }
            }

            // battery via UPower
            Text {
                id: batText; font.pixelSize: 15; text: "󰁹 …"
                Process {
                    id: batProc
                    command: ["bash","-lc","upower -i $(upower -e | grep BAT | head -n1) | awk '/percentage:/ {print $2}'"]
                    running: true
                    stdout: StdioCollector { onStreamFinished: batText.text = "󰁹 " + this.text.trim() }
                }
                Timer { interval: 60000; running: true; repeat: true; onTriggered: batProc.running = true }
            }

            // power menu
            Text {
                text: ""; font.pixelSize: 15
                MouseArea {
                    anchors.fill: parent
                    onClicked: Qt.createQmlObject('import Quickshell.Io; QtObject { Process { command: ["bash","-lc","wlogout"]; running: true } }', parent, "Power")
                }
            }
        }
    }
}
