import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services

// A settings dialog with its pages listed on the left (like the settings app)
// and the picked one on the right — no long scrolling through everything.
//   PagedModal {
//       id: m
//       title: "Mail settings"; icon: "󰒓"
//       pages: [{ id: "new", icon: "󰂚", label: "New mail" },
//               { id: "a1", label: "Work", color: "#88f", group: "Accounts" },     // group: a heading above it
//               { id: "add", icon: "󰐕", label: "Add account", action: true }]      // action: emits actionPicked
//       MailSettingsPages { page: m.page; showAll: m.query !== "" }   // the pages, one shown at a time
//   }
//   m.openPage(id)
// Each page is an item with a `pageId`, visible when it's the picked one — and every
// page while searching (`query` not empty; for the search above the list): it finds
// every shown PlainRow of every page by its label / description and opens the page
// on that row (scrolled to it, flashed).
// Animated: the highlight slides to the picked page, a page comes in from the
// direction of the list, search results fade in one after another.
Modal {
    id: root

    cardWidth: 900
    property string icon: "󰒓"
    property string title: ""
    property string subtitle: "Changes apply right away"
    property var pages: []
    property string page: ""
    default property alias pageContent: pageCol.data
    signal actionPicked(string id)

    function openPage(id) { page = id; open() }
    onShownChanged: if (shown) {
        if (!pages.some(p => p.id === page && !p.action)) page = pages.find(p => !p.action)?.id ?? ""
        searchField.clear()
        Qt.callLater(() => searchField.forceActiveFocus())    // after open() focused the card
    }
    // the new page slides in from where it is in the list (below: from below)
    property int pageIndex: -1
    onPageChanged: {
        pageFlick.contentY = 0
        const i = pages.findIndex(p => p.id === page)
        pageIn.dir = pageIndex < 0 || i === pageIndex ? 0 : i > pageIndex ? 1 : -1
        pageIndex = i
        pageIn.restart()
    }
    // a page that went away (an account removed): the first one
    onPagesChanged: if (page && !pages.some(p => p.id === page)) page = pages.find(p => !p.action)?.id ?? ""

    readonly property var current: pages.find(p => p.id === page) ?? null

    // ── search ──
    property string query: ""
    onQueryChanged: if (query === "") pageFlick.contentY = 0
    // the pages under an item (they have a pageId; also inside a component like MailSettingsPages)
    function pagesOf(item, out) {
        for (const c of item.children) {
            if (c.pageId !== undefined) out.push(c)
            else pagesOf(c, out)
        }
        return out
    }
    // the PlainRows under an item (duck-typed: label + desc + content slot)
    function rowsOf(item, out) {
        for (const c of item.children) {
            if (c.label !== undefined && c.desc !== undefined && c.content !== undefined) out.push(c)
            else rowsOf(c, out)
        }
        return out
    }
    // [{ pageId, page, row (null: the page itself), label, desc }], best first
    readonly property var results: {
        const q = query.trim().toLowerCase()
        if (q === "") return []
        const toks = q.split(/\s+/)
        const has = t => toks.every(k => t.includes(k))
        const out = []
        for (const pg of pagesOf(pageCol, [])) {
            const info = pages.find(p => p.id === pg.pageId)
            if (!info) continue
            const pl = String(info.heading ?? info.label ?? "").toLowerCase()
            if (has(pl)) out.push({ pageId: info.id, page: info, row: null, label: info.label, desc: info.heading ?? "", score: 4 })
            for (const r of rowsOf(pg, [])) {
                const l = String(r.label).toLowerCase(), d = String(r.desc).toLowerCase()
                if (!r.visible || !l || !has(l + " " + d + " " + pl)) continue
                out.push({ pageId: info.id, page: info, row: r, label: r.label, desc: r.desc,
                           score: l.startsWith(q) ? 3 : has(l) ? 2 : 1 })
            }
        }
        return out.map((r, i) => [r, i]).sort((a, b) => b[0].score - a[0].score || a[1] - b[1]).map(x => x[0])
    }
    readonly property var matchedPages: results.map(r => r.pageId)

    function jump(r) {
        searchField.clear()
        page = r.pageId
        flashRow = r.row
        if (r.row) jumpTimer.restart()
    }
    property Item flashRow: null
    Timer {
        id: jumpTimer
        interval: 40       // the page has laid out by then
        onTriggered: {
            const r = root.flashRow
            if (!r) return
            const p = r.mapToItem(pageFlick.contentItem, 0, 0)
            pageFlick.contentY = Math.max(0, Math.min(p.y - 40, pageFlick.contentHeight - pageFlick.height))
            flash.x = p.x; flash.y = p.y; flash.width = r.width; flash.height = r.height
            flashAnim.restart()
        }
    }

    ColumnLayout {
        width: parent.width
        // one height for every page: switching doesn't make the card jump
        height: Math.max(360, Math.min(640, root.height - 90))
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text { text: root.icon; color: Colors.color6; font.pixelSize: 20; font.family: Properties.fontFamily }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text { Layout.fillWidth: true; text: root.title; color: Colors.ink; font.pixelSize: 17; font.bold: true; font.family: Properties.fontFamily }
                Text { text: root.subtitle; color: Colors.fade(0.5); font.pixelSize: 11; font.family: Properties.fontFamily }
            }
            IconButton { implicitWidth: 30; implicitHeight: 30; icon: "󰅖"; onClicked: root.close() }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 14

            // ── search + the pages ──
            ColumnLayout {
                Layout.preferredWidth: 200
                Layout.maximumWidth: 200
                Layout.fillHeight: true
                spacing: 8
                SearchField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: "Search settings"
                    onTextChanged: root.query = text
                    Keys.onEscapePressed: event => { if (text !== "") clear(); else event.accepted = false }
                    Keys.onReturnPressed: if (root.results.length > 0) root.jump(root.results[0])
                    Keys.onEnterPressed: if (root.results.length > 0) root.jump(root.results[0])
                }
                Flickable {
                    id: navFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: nav.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height
                    // the picked page's highlight: one, sliding from page to page (a small squash on the way)
                    Rectangle {
                        id: navHighlight
                        property Item target: null
                        width: nav.width
                        y: target ? target.parent.y + target.y : 0
                        height: 34
                        radius: Properties.radius + 2
                        border.width: 1.5
                        border.color: Colors.fade(0.24)
                        gradient: ButtonGradient { hovered: true }
                        opacity: target && root.query === "" ? 1 : 0
                        scale: travel.running ? 0.97 : 1
                        onYChanged: if (opacity > 0) travel.restart()
                        Timer { id: travel; interval: 180 }
                        Behavior on y { enabled: navHighlight.opacity > 0; NumberAnimation { duration: 340; easing.type: Easing.OutQuint } }
                        Behavior on opacity { NumberAnimation { duration: 160 } }
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }
                    ColumnLayout {
                        id: nav
                        width: navFlick.width
                        spacing: 2
                        Repeater {
                            model: root.pages
                            ColumnLayout {
                                id: navRow
                                required property var modelData
                                required property int index
                                readonly property bool selected: root.page === modelData.id && root.query === ""
                                Layout.fillWidth: true
                                spacing: 2
                                onSelectedChanged: if (selected) navHighlight.target = navItem
                                Component.onCompleted: if (selected) navHighlight.target = navItem
                                // searching: pages without a match fade
                                opacity: root.query === "" || modelData.action || root.matchedPages.includes(modelData.id) ? 1 : 0.35
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                                Text {
                                    visible: !!navRow.modelData.group
                                    Layout.leftMargin: 10
                                    Layout.topMargin: navRow.index > 0 ? 12 : 0
                                    Layout.bottomMargin: 2
                                    text: (navRow.modelData.group ?? "").toUpperCase()
                                    color: Colors.fade(0.4)
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.letterSpacing: 1.1
                                    font.family: Properties.fontFamily
                                }
                                Item {
                                    id: navItem
                                    Layout.fillWidth: true
                                    implicitHeight: 34
                                    scale: navMouse.pressed ? 0.96 : 1
                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    // hover only (the picked one has the sliding highlight)
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Properties.radius + 2
                                        border.width: 1.5
                                        border.color: Colors.fade(0.14)
                                        gradient: ButtonGradient { hovered: false }
                                        opacity: !navRow.selected && navMouse.containsMouse ? 0.6 : 0
                                        Behavior on opacity { NumberAnimation { duration: 140 } }
                                    }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        Item {
                                            implicitWidth: 18
                                            implicitHeight: 18
                                            // an account: its color with its first letter
                                            Rectangle {
                                                visible: !!navRow.modelData.color
                                                anchors.centerIn: parent
                                                width: 18; height: 18; radius: 9
                                                color: navRow.modelData.color || "transparent"
                                                opacity: navRow.modelData.dim ? 0.4 : 1
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (navRow.modelData.label ?? "").charAt(0).toUpperCase()
                                                    color: Colors.background
                                                    font.pixelSize: 9
                                                    font.bold: true
                                                    font.family: Properties.fontFamily
                                                }
                                            }
                                            Text {
                                                visible: !navRow.modelData.color
                                                anchors.centerIn: parent
                                                text: navRow.modelData.icon ?? ""
                                                color: navRow.selected || (navRow.modelData.action && navMouse.containsMouse) ? Colors.color6 : Colors.fade(0.55)
                                                Behavior on color { ColorAnimation { duration: 200 } }
                                                font.pixelSize: 15
                                                font.family: Properties.fontFamily
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: navRow.modelData.label ?? ""
                                            color: navRow.selected ? Colors.ink : Colors.fade(navRow.modelData.action ? 0.55 : 0.78)
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                            font.pixelSize: 12
                                            font.bold: navRow.selected
                                            font.family: Properties.fontFamily
                                            elide: Text.ElideRight
                                        }
                                    }
                                    MouseArea {
                                        id: navMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (navRow.modelData.action) { root.actionPicked(navRow.modelData.id); return }
                                            searchField.clear()
                                            root.page = navRow.modelData.id
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Colors.fade(0.07) }

            // ── the picked page ──
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10
                Text {
                    id: pageTitle
                    transform: Translate { id: pageTitleShift }
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    text: root.query !== "" ? (root.results.length > 0 ? "Search" : "Nothing found")
                        : root.current?.heading ?? root.current?.label ?? ""
                    color: Colors.ink
                    font.pixelSize: 15
                    font.bold: true
                    font.family: Properties.fontFamily
                    elide: Text.ElideRight
                }
                // search results over the pages: while searching the pages stay laid out
                // underneath (unseen), so a row's own `visible` is real (hidden rows aren't found)
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Flickable {
                        id: resultFlick
                        anchors.fill: parent
                        opacity: root.query !== "" ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        contentHeight: resultCol.implicitHeight + 4
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: contentHeight > height
                        ScrollBar.vertical: CalScrollBar { id: resultBar }
                        SmoothWheel { flick: resultFlick; step: 140 }
                        ColumnLayout {
                            id: resultCol
                            width: resultFlick.width - (resultBar.visible ? 12 : 2)
                            spacing: 2
                            Text {
                                visible: root.results.length === 0
                                Layout.leftMargin: 4
                                text: "No setting matches \"" + root.query.trim() + "\""
                                color: Colors.fade(0.45)
                                font.pixelSize: 12
                                font.family: Properties.fontFamily
                            }
                            Repeater {
                                model: root.results
                                Item {
                                    id: hit
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    implicitHeight: hitRow.implicitHeight + 16
                                    // in one after another
                                    opacity: 0
                                    transform: Translate { id: hitShift; x: 14 }
                                    Component.onCompleted: hitIn.start()
                                    SequentialAnimation {
                                        id: hitIn
                                        PauseAnimation { duration: Math.min(hit.index, 10) * 22 }
                                        ParallelAnimation {
                                            NumberAnimation { target: hit; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
                                            NumberAnimation { target: hitShift; property: "x"; to: 0; duration: 260; easing.type: Easing.OutCubic }
                                        }
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Properties.radius + 2
                                        color: Colors.fade(hitMouse.containsMouse ? 0.07 : hit.index === 0 ? 0.035 : 0)
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                    }
                                    RowLayout {
                                        id: hitRow
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        Item {
                                            Layout.alignment: Qt.AlignTop
                                            implicitWidth: 18
                                            implicitHeight: 18
                                            Rectangle {
                                                visible: !!hit.modelData.page.color
                                                anchors.centerIn: parent
                                                width: 12; height: 12; radius: 6
                                                color: hit.modelData.page.color || "transparent"
                                            }
                                            Text {
                                                visible: !hit.modelData.page.color
                                                anchors.centerIn: parent
                                                text: hit.modelData.page.icon ?? ""
                                                color: Colors.fade(0.55)
                                                font.pixelSize: 14
                                                font.family: Properties.fontFamily
                                            }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            Text {
                                                Layout.fillWidth: true
                                                text: hit.modelData.row ? hit.modelData.page.label + "  ›  " + hit.modelData.label : hit.modelData.label
                                                color: Colors.ink
                                                font.pixelSize: 12
                                                font.bold: true
                                                font.family: Properties.fontFamily
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                visible: text !== ""
                                                text: hit.modelData.desc ?? ""
                                                color: Colors.fade(0.5)
                                                font.pixelSize: 11
                                                font.family: Properties.fontFamily
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                    MouseArea {
                                        id: hitMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.jump(hit.modelData)
                                    }
                                }
                            }
                        }
                    }
                    Flickable {
                        id: pageFlick
                        anchors.fill: parent
                        opacity: root.query === "" ? 1 : 0
                        enabled: root.query === ""
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        contentHeight: pageCol.implicitHeight + 4
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: contentHeight > height
                        ScrollBar.vertical: CalScrollBar { id: pageBar }
                        SmoothWheel { flick: pageFlick; step: 140 }
                        ColumnLayout {
                            id: pageCol
                            width: pageFlick.width - (pageBar.visible ? 12 : 2)
                            spacing: 8
                            transform: Translate { id: pageShift }
                        }
                        // a page coming in (onPageChanged)
                        ParallelAnimation {
                            id: pageIn
                            property int dir: 0         // 1: from below, -1: from above, 0: only fades
                            NumberAnimation { target: pageCol; property: "opacity"; from: 0; to: 1; duration: 240; easing.type: Easing.OutCubic }
                            NumberAnimation { target: pageTitle; property: "opacity"; from: 0; to: 1; duration: 240; easing.type: Easing.OutCubic }
                            NumberAnimation { target: pageShift; property: "y"; from: pageIn.dir * 26; to: 0; duration: 380; easing.type: Easing.OutQuint }
                            NumberAnimation { target: pageTitleShift; property: "x"; from: pageIn.dir === 0 ? 0 : 10; to: 0; duration: 320; easing.type: Easing.OutQuint }
                        }
                        // a row opened from search lights up once
                        Rectangle {
                            id: flash
                            z: 10
                            radius: 12
                            opacity: 0
                            color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.16)
                            border.width: 1.5
                            border.color: Qt.rgba(Colors.color6.r, Colors.color6.g, Colors.color6.b, 0.5)
                            SequentialAnimation {
                                id: flashAnim
                                NumberAnimation { target: flash; property: "opacity"; to: 1; duration: 160 }
                                PauseAnimation { duration: 700 }
                                NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 600 }
                            }
                        }
                    }
                }
            }
        }
    }
}
