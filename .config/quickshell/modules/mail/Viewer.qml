import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib
import "../calendar"
import "../settings"
import "MailIcons.js" as I

// Attachments viewed inside the app (like Thunderbird's PDF viewer): images,
// PDFs (pages rendered by poppler, see mailsync.py `view`) and text. Anything
// else: "Open with…" or save. ←/→ between the message's attachments,
// Ctrl +/-/0 or Ctrl + wheel zoom, Esc closes.
//   show(msg, attachments, index)
Item {
    id: root

    property bool shown: false
    property var msg: null
    property var list: []                    // the message's attachments [{ index, name, type, size }]
    property int at: 0
    property var item: null                  // mailsync's view answer
    property bool loading: false
    property string error: ""
    property string note: ""
    property real zoom: 1                    // 1 = fit the width (PDF / text) or the window (image)

    function show(m, atts, i) {
        msg = m; list = atts; shown = true
        go(i)
        forceActiveFocus()
    }
    function close() { shown = false; item = null }
    function go(i) {
        if (list.length === 0) return
        at = (i + list.length) % list.length
        item = null; error = ""; note = ""; zoom = 1; loading = true
        const want = at
        MailStore.view(msg, list[at].index, res => {
            if (want !== at) return
            loading = false
            if (res.ok) item = res
            else error = res.error
        })
    }
    // "Open with…": the apps registered for the file's type (gio mime), the default first
    property var apps: []
    function loadApps() {
        const type = list[at]?.type || item?.type || ""
        apps = []
        if (!type) return
        Jobs.run(["gio", "mime", type], (code, out) => {
            const ids = []
            for (const l of out.split("\n")) {
                const m = /([\w.+-]+\.desktop)\s*$/.exec(l)
                if (m && !ids.includes(m[1])) ids.push(m[1])
            }
            apps = ids.map(id => ({ id: id, entry: DesktopEntries.byId(id.replace(/\.desktop$/, "")) }))
                      .filter(a => a.entry && !a.entry.noDisplay)
        }, { LC_ALL: "C.UTF-8" })
    }
    function openWith(id) { Quickshell.execDetached(["gtk-launch", id, item.path]) }

    function zoomBy(f) { zoom = Math.max(0.25, Math.min(5, f === 0 ? 1 : zoom * f)) }

    anchors.fill: parent
    visible: opacity > 0
    opacity: shown ? 1 : 0
    z: 120
    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    // Ctrl +/−/0 zoom the attachment here, not the window (ZoomArea's shortcuts)
    Keys.onShortcutOverride: event => event.accepted = shown && (event.modifiers & Qt.ControlModifier)
        && [Qt.Key_Plus, Qt.Key_Equal, Qt.Key_Minus, Qt.Key_0].includes(event.key)
    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier
        if (event.key === Qt.Key_Escape) close()
        else if (event.key === Qt.Key_Left && !ctrl) go(at - 1)
        else if (event.key === Qt.Key_Right && !ctrl) go(at + 1)
        else if (ctrl && (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal)) zoomBy(1.25)
        else if (ctrl && event.key === Qt.Key_Minus) zoomBy(0.8)
        else if (ctrl && event.key === Qt.Key_0) zoomBy(0)
        else return
        event.accepted = true
    }

    Rectangle {
        anchors.fill: parent
        radius: Compositor.appRadius
        color: Colors.background
        // takes clicks, hover and the wheel (nothing underneath reacts)
        MouseArea { anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.AllButtons; onWheel: w => w.accepted = true }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // toolbar
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            IconButton { icon: I.left; tooltip: "Previous  (←)"; visible: root.list.length > 1; onClicked: root.go(root.at - 1) }
            IconButton { icon: I.right; tooltip: "Next  (→)"; visible: root.list.length > 1; onClicked: root.go(root.at + 1) }
            Text {
                text: root.item?.kind === "pdf" ? I.draft : I.clip
                color: Colors.color6
                font.pixelSize: 16
                font.family: Properties.fontFamily
                Layout.leftMargin: 6
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: root.list[root.at]?.name ?? ""
                    color: Colors.ink
                    font.pixelSize: 14
                    font.bold: true
                    font.family: Properties.fontFamily
                    elide: Text.ElideMiddle
                }
                Text {
                    Layout.fillWidth: true
                    text: root.note || [Format.bytes(root.list[root.at]?.size ?? 0),
                                        root.item?.kind === "pdf" ? root.item.pageCount + (root.item.pageCount === 1 ? " page" : " pages")
                                                                   + (root.item.pages.length < root.item.pageCount ? " (first " + root.item.pages.length + " shown)" : "") : "",
                                        root.list.length > 1 ? (root.at + 1) + " of " + root.list.length : ""].filter(x => x).join("  ·  ")
                    color: root.note ? Colors.color6 : Colors.fade(0.5)
                    font.pixelSize: 11
                    font.family: Properties.fontFamily
                    elide: Text.ElideRight
                }
            }
            IconButton { icon: "󰍴"; tooltip: "Zoom out  (Ctrl −)"; visible: root.item && root.item.kind !== "other"; onClicked: root.zoomBy(0.8) }
            Text {
                visible: root.item && root.item.kind !== "other"
                Layout.preferredWidth: 44
                horizontalAlignment: Text.AlignHCenter
                text: Math.round(root.zoom * 100) + "%"
                color: Colors.fade(0.6)
                font.pixelSize: 11
                font.family: Properties.fontFamily
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.zoomBy(0) }
            }
            IconButton { icon: I.plus; tooltip: "Zoom in  (Ctrl +)"; visible: root.item && root.item.kind !== "other"; onClicked: root.zoomBy(1.25) }
            Rectangle { implicitWidth: 1; implicitHeight: 18; color: Colors.fade(0.1); Layout.leftMargin: 6; Layout.rightMargin: 6 }
            // like Nautilus: the default app for this type (GNOME's default apps / mimeapps.list) …
            ActionButton {
                icon: I.open
                text: "Open"
                interactive: root.item !== null
                onClicked: Qt.openUrlExternally("file://" + root.item.path)
            }
            // … or one of the others that can open it
            ActionButton {
                id: withButton
                text: "Open with…"
                interactive: root.item !== null
                onClicked: { root.loadApps(); appMenu.open() }
                Popup {
                    id: appMenu
                    // the app window's zoom (Ctrl +/−): popups are drawn above it, not inside
                    scale: AppZoom.at(parent)
                    transformOrigin: Popup.TopLeft
                    y: withButton.height + 4
                    x: withButton.width - width
                    width: 260
                    padding: 6
                    height: Math.min(appCol.implicitHeight + 12, 320)
                    background: Rectangle {
                        radius: Properties.radius + 2
                        color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.97)
                        border.width: Properties.panelBorderWidth
                        border.color: Properties.panelBorder
                    }
                    enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140; easing.type: Easing.OutCubic } }
                    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 100 } }
                    Flickable {
                        anchors.fill: parent
                        contentHeight: appCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        Column {
                            id: appCol
                            width: parent.width
                            Text {
                                visible: root.apps.length === 0
                                width: parent.width
                                padding: 8
                                text: "No other app is registered for this kind of file"
                                color: Colors.fade(0.5)
                                font.pixelSize: 11
                                font.family: Properties.fontFamily
                                wrapMode: Text.Wrap
                            }
                            Repeater {
                                model: root.apps
                                Rectangle {
                                    id: appRow
                                    required property var modelData
                                    required property int index
                                    width: appCol.width
                                    height: 32
                                    radius: Properties.radius
                                    color: appHover.hovered ? Colors.fade(0.08) : "transparent"
                                    Behavior on color { ColorAnimation { duration: 90 } }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 8
                                        Image {
                                            Layout.preferredWidth: 18
                                            Layout.preferredHeight: 18
                                            sourceSize: Qt.size(36, 36)
                                            source: appRow.modelData.entry.icon ? Quickshell.iconPath(appRow.modelData.entry.icon, true) : ""
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: appRow.modelData.entry.name
                                            color: Colors.ink
                                            font.pixelSize: 12
                                            font.family: Properties.fontFamily
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            visible: appRow.index === 0
                                            text: "default"
                                            color: Colors.fade(0.4)
                                            font.pixelSize: 10
                                            font.family: Properties.fontFamily
                                        }
                                    }
                                    HoverHandler { id: appHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: { appMenu.close(); root.openWith(appRow.modelData.id) } }
                                }
                            }
                        }
                    }
                }
            }
            ActionButton {
                icon: I.download
                text: "Save"
                onClicked: MailStore.saveAttachment(root.msg, root.list[root.at].index, false, res => {
                    root.note = res.ok ? "Saved to " + res.path : res.error
                })
            }
            IconButton { icon: I.close; tooltip: "Close  (Esc)"; onClicked: root.close() }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 12
            color: Colors.card
            border.width: Properties.panelBorderWidth
            border.color: Properties.cardBorder
            clip: true

            // image
            Flickable {
                id: imgFlick
                anchors.fill: parent
                anchors.margins: 8
                visible: root.item?.kind === "image"
                contentWidth: Math.max(width, img.width)
                contentHeight: Math.max(height, img.height)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: CalScrollBar {}
                SmoothWheel { flick: imgFlick; step: 140; acceptedModifiers: Qt.NoModifier }
                Image {
                    id: img
                    x: Math.max(0, (imgFlick.width - width) / 2)
                    y: Math.max(0, (imgFlick.height - height) / 2)
                    source: root.item?.kind === "image" ? "file://" + root.item.path : ""
                    asynchronous: true
                    readonly property real fit: implicitWidth > 0 ? Math.min(1, imgFlick.width / implicitWidth, imgFlick.height / implicitHeight) : 1
                    width: implicitWidth * fit * root.zoom
                    height: implicitHeight * fit * root.zoom
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }
            }

            // PDF pages
            ListView {
                id: pages
                anchors.fill: parent
                anchors.margins: 8
                visible: root.item?.kind === "pdf"
                model: root.item?.kind === "pdf" ? root.item.pages : []
                spacing: 10
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: CalScrollBar {}
                SmoothWheel { flick: pages; step: 160; acceptedModifiers: Qt.NoModifier }
                contentWidth: Math.max(width, width * 0.9 * root.zoom)
                flickableDirection: Flickable.AutoFlickIfNeeded
                delegate: Item {
                    required property var modelData
                    required property int index
                    width: pages.contentWidth
                    height: page.height
                    Rectangle {
                        id: page
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(pages.width * 0.9, 900) * root.zoom
                        height: pimg.implicitWidth > 0 ? width * pimg.implicitHeight / pimg.implicitWidth : width * 1.414
                        color: "white"
                        radius: 4
                        Image {
                            id: pimg
                            anchors.fill: parent
                            source: "file://" + modelData
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                        }
                    }
                }
            }

            // text
            ScrollView {
                id: textScroll
                anchors.fill: parent
                anchors.margins: 8
                visible: root.item?.kind === "text"
                ScrollBar.vertical: CalScrollBar {}
                SmoothWheel { flick: textScroll.contentItem; step: 140; acceptedModifiers: Qt.NoModifier }
                TextArea {
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    text: root.item?.kind === "text" ? root.item.text + (root.item.truncated ? "\n\n[… only the first 300 KB are shown]" : "") : ""
                    color: Colors.fade(0.88)
                    selectionColor: Colors.fade(0.28)
                    font.pixelSize: Math.round(12 * root.zoom)
                    font.family: Properties.fontFamily
                    background: null
                }
            }

            // zoom with Ctrl + wheel anywhere
            WheelHandler {
                acceptedModifiers: Qt.ControlModifier
                onWheel: event => root.zoomBy(event.angleDelta.y > 0 ? 1.15 : 1 / 1.15)
            }

            // loading / error / can't show
            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - 80
                visible: root.loading || root.error !== "" || root.item?.kind === "other"
                spacing: 10
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.error ? I.junk : I.clip
                    color: root.error ? Colors.red : Colors.fade(0.25)
                    font.pixelSize: 40
                    font.family: Properties.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: root.loading ? "Opening…" : root.error ? root.error
                        : "This kind of file (" + (root.item?.type ?? "") + ") can't be shown here — open it with another app or save it."
                    color: Colors.fade(0.6)
                    font.pixelSize: 13
                    font.family: Properties.fontFamily
                }
            }
        }
    }
}
