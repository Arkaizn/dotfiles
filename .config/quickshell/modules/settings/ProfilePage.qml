import Quickshell
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.components
import qs.services

// Profile page of the settings app: the picture (~/.face, shown on the
// dashboard and the lockscreen) and the display name.
// A picked image is cropped to a centered square and scaled to 512 px with
// ImageMagick, so a huge photo doesn't get loaded everywhere.
// Settings.profile: { name, faceRev } — faceRev changes with every new
// picture, so the dashboard / lockscreen reload it (images are cached).
ColumnLayout {
    id: page
    spacing: Tokens.space.s14

    readonly property string facePath: Quickshell.env("HOME") + "/.face"
    readonly property string faceUrl: "file://" + facePath + "?r=" + (Settings.profile.faceRev ?? 0)
    property string info: ""             // "2480×3496 · 7.5 MB"
    property bool big: false             // worth shrinking
    property bool busy: false
    property string error: ""

    function bumpRev() { Settings.set("profile", "faceRev", Date.now()) }

    function readInfo() {
        Jobs.run(["sh", "-c", 'f="$1"; [ -f "$f" ] || exit 1; '
                  + 'printf "%s %s\\n" "$(magick identify -format "%w %h" "$f[0]" 2>/dev/null)" "$(stat -c %s "$f")"', "sh", page.facePath],
                 (code, out) => {
            const p = (out ?? "").trim().split(/\s+/).map(Number)
            if (code !== 0 || p.length < 3 || p.some(isNaN)) { page.info = ""; page.big = false; return }
            const mb = p[2] / 1048576
            page.info = p[0] + "×" + p[1] + "  ·  " + (mb >= 1 ? mb.toFixed(1) + " MB" : Math.round(p[2] / 1024) + " KB")
            page.big = p[0] > 600 || p[1] > 600 || p[0] !== p[1]
        })
    }
    Component.onCompleted: readInfo()


    // crop to a centered square, 512 px, into ~/.face ($1 = source image)
    readonly property string convertScript:
        'tmp=$(mktemp -p "${XDG_RUNTIME_DIR:?}" --suffix=.png) || exit 1\n'
        + 'if magick "$1[0]" -auto-orient -gravity center -resize "512x512^" -extent 512x512 -strip "$tmp" 2>&1; then\n'
        + '  mv -f "$tmp" "$2"\n'
        + 'else rm -f "$tmp"; exit 1; fi'

    function setFrom(file) {
        page.busy = true
        page.error = ""
        Jobs.run(["sh", "-c", convertScript, "sh", file, facePath], (code, out) => {
            page.busy = false
            if (code !== 0) { page.error = "Couldn't use that image: " + ((out ?? "").trim().split("\n").pop() || "ImageMagick failed"); return }
            page.bumpRev()
            page.readInfo()
        })
    }
    function pickPicture() {
        Jobs.pickFile({ title: "Choose a profile picture", start: Quickshell.env("HOME") + "/Pictures/",
                         filters: ["Images | *.png *.jpg *.jpeg *.webp *.gif *.bmp *.tif *.tiff *.heic *.avif *.PNG *.JPG *.JPEG"] },
                       f => { if (f !== "") page.setFrom(f) })
    }
    function removePicture() { Jobs.run(["rm", "-f", page.facePath], () => { page.bumpRev(); page.readInfo() }) }




    // ── Picture ─────────────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: picRow.implicitHeight + 40
        radius: Tokens.radius.card
        color: Colors.card
        border.width: Properties.panelBorderWidth
        border.color: Properties.cardBorder

        RowLayout {
            id: picRow
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: Tokens.space.s24; rightMargin: Tokens.space.s20 }
            spacing: Tokens.space.s24

            // the picture: round, "Change" on hover, click to pick
            Item {
                id: avatar
                implicitWidth: 132
                implicitHeight: 132
                scale: avMouse.pressed ? 0.96 : avMouse.containsMouse ? 1.03 : 1
                Behavior on scale { NumberAnimation { duration: Anim.normal; easing.type: Anim.standard } }

                Image {
                    id: face
                    anchors.fill: parent
                    source: page.faceUrl
                    sourceSize: Qt.size(264, 264)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    visible: false
                }
                OpacityMask {
                    anchors.fill: parent
                    source: face
                    maskSource: Rectangle { width: avatar.width; height: avatar.height; radius: width / 2 }
                    visible: face.status === Image.Ready
                    opacity: face.status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Anim.slow } }
                }
                // no picture yet
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    visible: face.status !== Image.Ready
                    color: Colors.alpha(Colors.color6, 0.15)
                    Text {
                        anchors.centerIn: parent
                        text: (Settings.profile.name || Quickshell.env("USER") || "?").charAt(0).toUpperCase()
                        color: Colors.color6
                        font.pixelSize: 52
                        font.bold: true
                        font.family: Properties.fontFamily
                    }
                }
                // hover overlay
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Colors.dim(0.5)
                    opacity: avMouse.containsMouse || page.busy ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Anim.normal } }
                    Column {
                        anchors.centerIn: parent
                        spacing: Tokens.space.s2
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: page.busy ? "󰔟" : "󰄀"
                            color: Colors.ink
                            font.pixelSize: Tokens.font.headline
                            font.family: Properties.fontFamily
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: page.busy ? "Working…" : "Change"
                            color: Colors.ink
                            font.pixelSize: Tokens.font.caption
                            font.bold: true
                            font.family: Properties.fontFamily
                        }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: avMouse.containsMouse ? Colors.color6 : Colors.fade(0.18)
                    Behavior on border.color { ColorAnimation { duration: Anim.normal } }
                }
                MouseArea {
                    id: avMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !page.busy
                    onClicked: page.pickPicture()
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.space.s6
                Text {
                    text: Settings.profile.name || Quickshell.env("USER") || ""
                    color: Colors.ink
                    font.pixelSize: Tokens.font.titleLarge
                    font.bold: true
                    font.family: Properties.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    text: page.info !== "" ? "~/.face  ·  " + page.info : "No picture set (~/.face)"
                    color: Colors.fade(0.5)
                    font.pixelSize: Tokens.font.caption
                    font.family: Properties.fontFamily
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    visible: page.error !== ""
                    text: "󰀦  " + page.error
                    color: Colors.red
                    font.pixelSize: Tokens.font.caption
                    font.family: Properties.fontFamily
                    wrapMode: Text.WordWrap
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.space.s6
                    spacing: Tokens.space.s6
                    ActionButton {
                        icon: "󰋩"
                        text: "Choose picture"
                        primary: true
                        interactive: !page.busy
                        onClicked: page.pickPicture()
                    }
                    ActionButton {
                        visible: page.big
                        icon: "󰩨"
                        text: "Crop & shrink to 512 px"
                        interactive: !page.busy
                        onClicked: page.setFrom(page.facePath)
                    }
                    ActionButton {
                        id: removeBtn
                        visible: page.info !== ""
                        ConfirmArm { id: removeArm }
                        readonly property bool armed: removeArm.armed !== ""
                        icon: "󰆴"
                        text: armed ? "Click again to remove" : "Remove"
                        textColor: armed ? Colors.red : Colors.ink
                        interactive: !page.busy
                        onClicked: if (removeArm.confirm("remove")) page.removePicture()
                    }
                }
            }
        }
    }

    Text {
        Layout.leftMargin: Tokens.space.s6
        text: "Shown on the dashboard and the lockscreen. Pictures are cropped to a centered square."
        color: Colors.fade(0.4)
        font.pixelSize: Tokens.font.caption
        font.family: Properties.fontFamily
    }

    // ── Name ────────────────────────────────────────────────────────────────
    Text {
        Layout.leftMargin: Tokens.space.s6
        Layout.topMargin: Tokens.space.s4
        text: "Name"
        color: Colors.fade(0.55)
        font.pixelSize: Tokens.font.small
        font.bold: true
        font.family: Properties.fontFamily
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: nameRow.implicitHeight
        radius: Tokens.radius.card
        color: Colors.card
        border.width: Properties.panelBorderWidth
        border.color: Properties.cardBorder
        PlainRow {
            id: nameRow
            width: parent.width
            label: "Display name"
            desc: "Dashboard and lockscreen (\"Hello, …\"). Empty: your user name"
            SearchField {
                implicitWidth: 240
                implicitHeight: Properties.buttonHeight
                icon: ""
                placeholderText: Quickshell.env("USER") ?? ""
                text: Settings.profile.name ?? ""
                onEditingFinished: {
                    if (text.trim() === "") Settings.reset("profile", "name")
                    else if (text.trim() !== (Settings.profile.name ?? "")) Settings.set("profile", "name", text.trim())
                }
            }
        }
    }
}
