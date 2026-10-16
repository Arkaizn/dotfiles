import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import "../settings"

// Add a calendar account: pick the kind → sign in / paste a link → choose calendars.
Modal {
    id: root

    cardWidth: 540

    property int step: 0              // 0 kind, 1 details, 2 calendars
    property string kind: ""
    property string error: ""
    property var found: []            // discovered calendars (+ enabled flag)

    property string fName: ""
    property string fUrl: ""
    property string fUser: ""
    property string fPass: ""

    readonly property var kinds: [
        { id: "icloud", type: "caldav", icon: "󰀵", title: "iCloud",
          desc: "Apple Calendar. Needs an app-specific password." },
        { id: "caldav", type: "caldav", icon: "󰒍", title: "CalDAV server",
          desc: "Nextcloud, Fastmail, mailbox.org, Radicale, Baïkal, Synology, …" },
        { id: "google", type: "ics", icon: "󰊭", title: "Google / Outlook",
          desc: "Through the calendar's private iCal link (read-only)." },
        { id: "ics", type: "ics", icon: "󰑫", title: "Subscription",
          desc: "Any .ics or webcal:// link: holidays, sports, school, … (read-only)" },
        { id: "local", type: "local", icon: "󰋜", title: "Local calendar",
          desc: "An .ics file on this computer. Works offline." }
    ]
    readonly property var kindInfo: kinds.find(k => k.id === kind) ?? kinds[0]

    function start() {
        step = 0; kind = ""; error = ""; found = []
        fName = ""; fUrl = ""; fUser = ""; fPass = ""
        open()
    }

    function choose(k) {
        kind = k.id
        error = ""
        fName = k.id === "icloud" ? "iCloud" : k.id === "local" ? "Personal" : ""
        fUrl = k.id === "icloud" ? "https://caldav.icloud.com"
             : k.id === "local" ? "~/.local/share/calendars/personal.ics" : ""
        step = 1
    }

    function form() {
        return { type: kindInfo.type, name: fName.trim(), url: fUrl.trim(), username: fUser.trim(), password: fPass }
    }

    function check() {
        error = ""
        CalendarStore.discover(form(), res => {
            if (!res.ok) { root.error = res.error; return }
            root.found = res.calendars.map(c => Object.assign({ enabled: true }, c))
            if (!root.fName) root.fName = res.calendars.length === 1 ? res.calendars[0].name : (root.form().url.replace(/^[a-z]+:\/\//i, "").split(/[/:]/)[0] || "Calendar")
            root.step = 2
        })
    }

    function finish() {
        const chosen = found.filter(c => c.enabled)
        if (chosen.length === 0) { error = "Pick at least one calendar"; return }
        CalendarStore.addAccount(form(), chosen)
        close()
    }

    onClosed: fPass = ""      // don't keep the password around

    ColumnLayout {
        width: parent.width
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            IconButton {
                visible: root.step > 0
                implicitWidth: 30; implicitHeight: 30
                icon: "󰅁"
                onClicked: { root.step--; root.error = "" }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: root.step === 0 ? "Add calendars" : root.step === 1 ? root.kindInfo.title : "Choose calendars"
                    color: "white"
                    font.pixelSize: 17
                    font.bold: true
                    font.family: Properties.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.step === 0 ? "Where do your calendars live?" : root.step === 1 ? root.kindInfo.desc : "Found " + root.found.length + " — pick the ones to show"
                    color: Qt.rgba(1, 1, 1, 0.5)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                }
            }
            IconButton {
                implicitWidth: 30; implicitHeight: 30
                icon: "󰅖"
                onClicked: root.close()
            }
        }

        // ── Step 0: kind ─────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.step === 0
            spacing: 8
            Repeater {
                model: root.kinds
                Rectangle {
                    id: kindCard
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 58
                    radius: 14
                    color: kindMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "#27000000"
                    border.width: Properties.panelBorderWidth
                    border.color: kindMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.2) : Properties.cardBorder
                    scale: kindMouse.pressed ? 0.98 : 1
                    Behavior on scale { NumberAnimation { duration: 100 } }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 14
                        spacing: 14
                        Text {
                            Layout.preferredWidth: 24
                            horizontalAlignment: Text.AlignHCenter
                            text: kindCard.modelData.icon
                            color: Colors.color6
                            font.pixelSize: 20
                            font.family: Properties.fontFamily
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                text: kindCard.modelData.title
                                color: "white"
                                font.pixelSize: 13
                                font.bold: true
                                font.family: Properties.fontFamily
                            }
                            Text {
                                Layout.fillWidth: true
                                text: kindCard.modelData.desc
                                color: Qt.rgba(1, 1, 1, 0.5)
                                font.pixelSize: 11
                                font.family: Properties.fontFamily
                                elide: Text.ElideRight
                            }
                        }
                        Text {
                            text: "󰅂"
                            color: Qt.rgba(1, 1, 1, 0.4)
                            font.pixelSize: 13
                            font.family: Properties.fontFamily
                        }
                    }
                    MouseArea {
                        id: kindMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.choose(kindCard.modelData)
                    }
                }
            }
        }

        // ── Step 1: details ──────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.step === 1
            spacing: 10

            // how-to for the kinds that need a bit of setup
            Rectangle {
                Layout.fillWidth: true
                visible: hint.text !== ""
                implicitHeight: hint.implicitHeight + 20
                radius: 12
                color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.08)
                border.width: Properties.panelBorderWidth
                border.color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.25)
                Text {
                    id: hint
                    anchors.fill: parent
                    anchors.margins: 10
                    anchors.leftMargin: 14
                    text: root.kind === "icloud"
                        ? "1. Open <a href=\"https://account.apple.com\">account.apple.com</a> → Sign-In and Security → App-Specific Passwords<br>2. Create one (e.g. \"Quickshell\") and paste it below — not your normal Apple password."
                        : root.kind === "google"
                        ? "Google: calendar.google.com → ⚙ Settings → your calendar → \"Secret address in iCal format\".<br>Outlook: Settings → Calendar → Shared calendars → Publish a calendar → ICS link."
                        : root.kind === "caldav"
                        ? "Examples: Nextcloud https://cloud.example.com/remote.php/dav · Fastmail https://caldav.fastmail.com · mailbox.org https://dav.mailbox.org"
                        : root.kind === "local" ? "The file is created if it doesn't exist. Point it at an existing .ics to use that." : ""
                    textFormat: Text.StyledText
                    linkColor: Colors.color6
                    color: Qt.rgba(1, 1, 1, 0.75)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                    wrapMode: Text.WordWrap
                    lineHeight: 1.15
                    onLinkActivated: link => Qt.openUrlExternally(link)
                    HoverHandler { cursorShape: hint.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                }
            }

            SearchField {
                Layout.fillWidth: true
                visible: root.kind !== "icloud"
                icon: root.kind === "local" ? "󰈔" : "󰖟"
                placeholderText: root.kind === "local" ? "File path" : root.kindInfo.type === "ics" ? "Calendar link (https:// or webcal://)" : "Server address"
                text: root.fUrl
                onTextEdited: root.fUrl = text
            }
            SearchField {
                Layout.fillWidth: true
                visible: root.kindInfo.type === "caldav"
                icon: "󰀄"
                placeholderText: root.kind === "icloud" ? "Apple ID (email)" : "Username"
                text: root.fUser
                onTextEdited: root.fUser = text
            }
            SearchField {
                Layout.fillWidth: true
                visible: root.kindInfo.type === "caldav"
                icon: "󰌾"
                password: true
                placeholderText: root.kind === "icloud" ? "App-specific password" : "Password"
                text: root.fPass
                onTextEdited: root.fPass = text
                onAccepted: root.check()
            }
            SearchField {
                Layout.fillWidth: true
                icon: "󰑕"
                placeholderText: "Name (optional)"
                text: root.fName
                onTextEdited: root.fName = text
            }
        }

        // ── Step 2: calendars ────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            visible: root.step === 2
            implicitHeight: calList.implicitHeight
            radius: 14
            color: "#27000000"
            border.width: Properties.panelBorderWidth
            border.color: Properties.cardBorder
            ColumnLayout {
                id: calList
                width: parent.width
                spacing: 0
                Repeater {
                    model: root.found
                    Item {
                        id: calRow
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: 46
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 12
                            spacing: 12
                            Rectangle {
                                Layout.preferredWidth: 12
                                Layout.preferredHeight: 12
                                radius: 6
                                color: calRow.modelData.color || CalendarStore.palette[(CalendarStore.calendars.length + calRow.index) % CalendarStore.palette.length]
                            }
                            Text {
                                Layout.fillWidth: true
                                text: calRow.modelData.name + (calRow.modelData.readOnly ? "  󰌾" : "")
                                color: "white"
                                font.pixelSize: 13
                                font.family: Properties.fontFamily
                                elide: Text.ElideRight
                            }
                            ToggleSwitch {
                                checked: calRow.modelData.enabled
                                onToggled: v => {
                                    const f = root.found.slice()
                                    f[calRow.index] = Object.assign({}, f[calRow.index], { enabled: v })
                                    root.found = f
                                }
                            }
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.error !== ""
            text: root.error
            color: "#f38ba8"
            font.pixelSize: 11
            font.family: Properties.fontFamily
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.step > 0
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: root.kindInfo.type === "caldav" && root.step === 1 ? "󰌾  The password is stored in your keyring." : ""
                color: Qt.rgba(1, 1, 1, 0.4)
                font.pixelSize: 10
                font.family: Properties.fontFamily
            }
            ActionButton {
                visible: root.step === 1
                icon: CalendarStore.working ? "󰔟" : "󰅂"
                text: CalendarStore.working ? "Connecting…" : "Continue"
                primary: true
                interactive: !CalendarStore.working && root.fUrl.trim() !== ""
                             && (root.kindInfo.type !== "caldav" || (root.fUser.trim() !== "" && root.fPass !== ""))
                onClicked: root.check()
            }
            ActionButton {
                visible: root.step === 2
                icon: "󰄬"
                text: "Add"
                primary: true
                onClicked: root.finish()
            }
        }
    }
}
