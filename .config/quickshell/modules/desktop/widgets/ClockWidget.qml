import QtQuick
import QtQuick.Layouts
import qs.services

// Clock: digital, analog or in words ("quarter past ten"), date below.
ColumnLayout {
    id: root
    property var opts: ({})
    property bool interactive: true
    property bool active: true

    readonly property real size: opts.size ?? 96
    spacing: size * 0.06

    function words(h, m) {
        const n = ["twelve", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven"]
        const r = Math.round(m / 5) * 5
        const hr = r > 30 ? h + 1 : h
        const name = n[hr % 12]
        const part = { 0: "", 5: "five past", 10: "ten past", 15: "quarter past", 20: "twenty past", 25: "twenty-five past",
                       30: "half past", 35: "twenty-five to", 40: "twenty to", 45: "quarter to", 50: "ten to", 55: "five to", 60: "" }[r]
        return part === "" ? name + "\no'clock" : part + "\n" + name
    }

    // ── digital / words ──
    Text {
        visible: root.opts.style !== "analog"
        Layout.alignment: Qt.AlignHCenter
        horizontalAlignment: Text.AlignHCenter
        text: root.opts.style === "words" ? root.words(Time.hours, Time.minutes)
            : Time.format(root.opts.h12 ? (root.opts.seconds ? "h:mm:ss" : "h:mm") : (root.opts.seconds ? "HH:mm:ss" : "HH:mm"))
        color: Colors.ink
        font.pixelSize: root.opts.style === "words" ? root.size * 0.5 : root.size
        font.family: Properties.fontFamily
        font.weight: Font.Light
        lineHeight: 0.9
        // AM / PM, small, top right
        Text {
            visible: root.opts.h12 === true && root.opts.style !== "words"
            anchors { left: parent.right; top: parent.top; leftMargin: root.size * 0.06; topMargin: root.size * 0.12 }
            text: Time.hours < 12 ? "AM" : "PM"
            color: Colors.fade(0.6)
            font.pixelSize: root.size * 0.2
            font.family: Properties.fontFamily
        }
    }

    // ── analog ──
    Item {
        id: face
        visible: root.opts.style === "analog"
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: root.size * 2
        implicitHeight: root.size * 2
        readonly property real r: width / 2

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: Math.max(1, face.r * 0.025)
            border.color: Colors.fade(0.25)
        }
        Repeater {
            model: 12
            Rectangle {
                required property int index
                readonly property bool major: index % 3 === 0
                width: Math.max(1.5, face.r * (major ? 0.04 : 0.022))
                height: face.r * (major ? 0.14 : 0.08)
                radius: width / 2
                color: major ? Colors.ink : Colors.fade(0.5)
                x: face.r - width / 2
                y: face.r * 0.06
                transform: Rotation { origin.x: width / 2; origin.y: face.r - face.r * 0.06; angle: index * 30 }
            }
        }
        // a hand from the centre outwards: len and thick are parts of the radius
        component Hand: Rectangle {
            id: hand
            property real angle: 0
            property real len: 0.6
            property real thick: 0.05
            width: Math.max(1.5, face.r * thick)
            height: face.r * len
            radius: width / 2
            color: Colors.ink
            x: face.r - width / 2
            y: face.r - height + width / 2
            transform: Rotation { origin.x: hand.width / 2; origin.y: hand.height - hand.width / 2; angle: hand.angle }
        }
        Hand { len: 0.52; thick: 0.065; angle: (Time.hours % 12) * 30 + Time.minutes * 0.5 }
        Hand { len: 0.78; thick: 0.04; angle: Time.minutes * 6 + Time.seconds * 0.1 }
        Hand { visible: root.opts.seconds === true; len: 0.86; thick: 0.018; color: Colors.color6; angle: Time.seconds * 6 }
        Rectangle {
            width: face.r * 0.09; height: width; radius: width / 2
            anchors.centerIn: parent
            color: root.opts.seconds === true ? Colors.color6 : Colors.ink
        }
    }

    Text {
        visible: root.opts.date !== false
        Layout.alignment: Qt.AlignHCenter
        text: Time.format("dddd, d MMMM")
        color: Colors.fade(0.7)
        font.pixelSize: Math.max(11, root.size * (root.opts.style === "analog" ? 0.16 : 0.2))
        font.family: Properties.fontFamily
    }
}
