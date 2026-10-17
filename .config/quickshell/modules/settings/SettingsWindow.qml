import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// Settings app: a normal (floating) window to change the Properties.qml
// values and some compositor settings. Changes apply live and are saved to
// settings.json (services/Settings.qml); niri ones go to niri's override
// file (services/NiriSettings.qml), Hyprland ones to Hyprland's
// (services/HyprSettings.qml). Only the running compositor's pages show.
//
// Open it with:  qs ipc call settings toggle   (Mod+S, set in the override file)
//                qs ipc call settings openPage <id>   (ids below, e.g. niriLayout)
Scope {
    id: root

    // kept across shell reloads (config edits etc.): an open window comes back
    property alias open: persist.open
    property alias pageId: persist.pageId
    PersistentProperties {
        id: persist
        reloadableId: "settingsWindow"
        property bool open: false
        property string pageId: "appearance"
    }

    // open, or bring the already open window to the front (the compositor
    // focuses it, switching workspace / monitor if needed)
    function show() {
        if (root.open) Compositor.focusWindow(NiriSettings.windowTitle)
        root.open = true
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { root.open = !root.open }
        function open(): void { root.show() }
        function close(): void { root.open = false }
        // e.g. qs ipc call settings openPage niriInput
        function openPage(id: string): void {
            if (root.visiblePages.some(p => p.id === id)) root.pageId = id
            root.show()
        }
    }

    // ── Pages ────────────────────────────────────────────────────────────────
    // "properties" items are complete here; "niri" / "hyprland" items only name
    // a key of NiriSettings.schema / HyprSettings.schema and add layout hints
    // (sub / dependsOn). Pages with `wm` only show on that compositor.
    readonly property string wm: Compositor.isHyprland ? "hyprland" : "niri"
    readonly property string wmGroup: Compositor.isHyprland ? "Hyprland" : "Niri"
    readonly property var visiblePages: pages.filter(p => !p.wm || p.wm === wm)

    readonly property var pages: [
        { id: "appearance", group: "Shell", icon: "󰏘", title: "Appearance", store: "properties",
          desc: "Font, text and icons used all over the shell",
          sections: [
            { title: "Text", items: [
                { key: "fontFamily", type: "font", label: "Font", desc: "Used by the bar, popups and widgets" },
                { key: "pixelSize", type: "int", min: 8, max: 24, label: "Text size", desc: "Bar labels and stats" },
                { key: "fontBold", type: "bool", label: "Bold button text" },
                { key: "color", type: "color", label: "Text & icon color", desc: "Buttons, fields and bar icons" } ] },
            { title: "Icons", items: [
                { key: "iconSize", type: "int", min: 10, max: 32, label: "Icon size", desc: "Bar buttons, tray and profile" } ] } ] },

        { id: "bar", group: "Shell", icon: "󰍜", title: "Bar", store: "properties",
          desc: "Shape and spacing of the top bar",
          sections: [
            { title: "Shape", items: [
                { key: "barRadius", type: "int", min: 0, max: 30, label: "Corner radius" },
                { key: "barInset", type: "int", min: 0, max: 40, label: "Distance to screen edge", desc: "Also where popups attach" } ] },
            { title: "Content", items: [
                { key: "barMarginLeft", type: "int", min: 0, max: 60, label: "Left padding" },
                { key: "barMarginRight", type: "int", min: 0, max: 60, label: "Right padding" },
                { key: "spacing", type: "int", min: 0, max: 24, label: "Space between modules" },
                { key: "interval", type: "int", min: 100, max: 5000, step: 100, label: "Stats refresh (ms)",
                  desc: "How often CPU, GPU and memory update" } ] } ] },

        { id: "panels", group: "Shell", icon: "󰖯", title: "Panels", store: "properties",
          desc: "Bar background, popups, dashboard, launcher and cards",
          sections: [
            { title: "Colors", items: [
                { key: "panelColor", type: "color", label: "Panel background", desc: "Bar and every popup" },
                { key: "panelBorder", type: "color", label: "Panel border" },
                { key: "cardBorder", type: "color", label: "Card border", desc: "Inner cards in the dashboard and control center" },
                { key: "panelBorderWidth", type: "real", min: 0, max: 4, step: 0.5, label: "Border width" } ] },
            { title: "Corners", items: [
                { key: "panelRadius", type: "int", min: 0, max: 48, label: "Big panels",
                  desc: "Dashboard, notification center, launcher, lockscreen" },
                { key: "popupRadius", type: "int", min: 0, max: 32, label: "Notification popups" },
                { key: "flareRadius", type: "int", min: 0, max: 48, label: "Bar flares",
                  desc: "Inverted corners where a popup meets the bar" } ] } ] },

        { id: "buttons", group: "Shell", icon: "󰆽", title: "Buttons", store: "properties",
          desc: "Size and shape of buttons",
          sections: [
            { title: "Size", items: [
                { key: "buttonHeight", type: "int", min: 20, max: 48, label: "Height", desc: "Bar buttons, icon buttons, fields" },
                { key: "buttonWidth", type: "int", min: 12, max: 48, label: "Bar button padding", desc: "Extra width around bar button content" } ] },
            { title: "Corners", items: [
                { key: "radius", type: "int", min: 0, max: 20, label: "Buttons & fields" },
                { key: "buttonradius", type: "int", min: 0, max: 20, label: "Bar stats" } ] } ] },

        { id: "motion", group: "Shell", icon: "󰑮", title: "Motion", store: "properties",
          desc: "Hover and press feedback",
          sections: [
            { title: "Buttons", items: [
                { key: "bDuration", type: "int", min: 0, max: 600, step: 10, label: "Animation length (ms)" },
                { key: "onEnteredButtonScale", type: "real", min: 1, max: 1.3, step: 0.01, label: "Hover zoom" },
                { key: "onPressedButtonScale", type: "real", min: 0.7, max: 1, step: 0.01, label: "Press shrink" },
                { key: "onEnteredTextScale", type: "real", min: 1, max: 1.5, step: 0.01, label: "Workspace & tray hover zoom" } ] } ] },

        { id: "monitors", group: wmGroup, icon: "󰍹", title: "Monitors", custom: "monitors",
          desc: "Arrange screens, resolution, refresh rate and scale" },

        { id: "calendar", group: "Apps", icon: "󰃭", title: "Calendar", store: "calendar",
          desc: "Reminders and syncing of the calendar app",
          sections: [
            { title: "Reminders", items: [
                { key: "reminders", type: "bool", def: true, label: "Reminders",
                  desc: "Notification before an event starts" },
                { key: "defaultReminder", type: "choice", def: "10", options: ["off", "5", "10", "15", "30", "60"],
                  dependsOn: "reminders", label: "Default reminder (minutes before)",
                  desc: "For events that don't have their own reminder" },
                { key: "allDayReminder", type: "bool", def: false, dependsOn: "reminders",
                  label: "All-day events", desc: "Remind at 09:00 on the day" } ] },
            { title: "View", items: [
                { key: "defaultView", type: "choice", def: "month", options: ["day", "week", "month", "agenda"],
                  label: "Open in", desc: "View when the calendar starts" },
                { key: "dayStart", type: "choice", def: "7", options: ["6", "7", "8", "9", "10"],
                  label: "Day starts at", desc: "Where the day and week views scroll to" },
                { key: "weekNumbers", type: "bool", def: true, label: "Week numbers" } ] },
            { title: "Sync", items: [
                { key: "syncMinutes", type: "choice", def: "15", options: ["5", "15", "30", "60"],
                  label: "Sync every (minutes)", desc: "In the background too, for the dashboard and reminders" } ] } ] },

        { id: "niriLayout", wm: "niri", group: "Niri", icon: "󰕰", title: "Layout", store: "niri",
          desc: "How windows are placed",
          sections: [
            { title: "Windows", items: [
                { key: "gaps" }, { key: "centerColumn" }, { key: "columnWidth" }, { key: "cornerRadius" } ] },
            { title: "Apps", items: [ { key: "preferNoCsd" } ] } ] },

        { id: "niriLooks", wm: "niri", group: "Niri", icon: "󰖲", title: "Decorations", store: "niri",
          desc: "Focus ring, border and shadows",
          sections: [
            { title: "Focus ring", items: [
                { key: "ringOn" },
                { key: "ringWidth", dependsOn: "ringOn" },
                { key: "ringActive", dependsOn: "ringOn" },
                { key: "ringInactive", dependsOn: "ringOn" } ] },
            { title: "Border", items: [
                { key: "borderOn" },
                { key: "borderWidth", dependsOn: "borderOn" },
                { key: "borderInactive", dependsOn: "borderOn" },
                { key: "borderUrgent", dependsOn: "borderOn" } ] },
            { title: "Shadow", items: [
                { key: "shadowOn" },
                { key: "shadowSoftness", dependsOn: "shadowOn" },
                { key: "shadowSpread", dependsOn: "shadowOn" },
                { key: "shadowColor", dependsOn: "shadowOn" } ] } ] },

        { id: "niriEffects", wm: "niri", group: "Niri", icon: "󰂵", title: "Effects", store: "niri",
          desc: "Animations and blur",
          sections: [
            { title: "Animations", items: [ { key: "animationsOn" }, { key: "slowdown", dependsOn: "animationsOn" } ] },
            { title: "Blur", items: [ { key: "appBlur" }, { key: "blurPasses" }, { key: "blurOffset" } ] } ] },

        { id: "niriInput", wm: "niri", group: "Niri", icon: "󰌌", title: "Input", store: "niri",
          desc: "Keyboard, touchpad, mouse and cursor",
          sections: [
            { title: "Keyboard", items: [ { key: "kbLayout" }, { key: "numlock" } ] },
            { title: "Pointer", items: [ { key: "touchpadAccel" }, { key: "mouseAccel" }, { key: "cursorSize" } ] } ] },

        { id: "hyprLayout", wm: "hyprland", group: "Hyprland", icon: "󰕰", title: "Layout", store: "hyprland",
          desc: "How windows are placed",
          sections: [
            { title: "Tiling", items: [ { key: "layout" }, { key: "gapsIn" }, { key: "gapsOut" } ] },
            { title: "Corners", items: [ { key: "rounding" }, { key: "roundingPower" } ] } ] },

        { id: "hyprLooks", wm: "hyprland", group: "Hyprland", icon: "󰖲", title: "Decorations", store: "hyprland",
          desc: "Borders, opacity and shadows",
          sections: [
            { title: "Border", items: [ { key: "borderSize" }, { key: "activeBorder" }, { key: "inactiveBorder" } ] },
            { title: "Opacity", items: [
                { key: "activeOpacity" }, { key: "inactiveOpacity" },
                { key: "dimInactive" }, { key: "dimStrength", dependsOn: "dimInactive" } ] },
            { title: "Shadow", items: [
                { key: "shadowOn" },
                { key: "shadowRange", dependsOn: "shadowOn" },
                { key: "shadowPower", dependsOn: "shadowOn" },
                { key: "shadowColor", dependsOn: "shadowOn" } ] } ] },

        { id: "hyprEffects", wm: "hyprland", group: "Hyprland", icon: "󰂵", title: "Effects", store: "hyprland",
          desc: "Animations and blur",
          sections: [
            { title: "Animations", items: [ { key: "animationsOn" } ] },
            { title: "Blur", items: [
                { key: "blurOn" },
                { key: "blurSize", dependsOn: "blurOn" },
                { key: "blurPasses", dependsOn: "blurOn" },
                { key: "blurVibrancy", dependsOn: "blurOn" },
                { key: "blurXray", dependsOn: "blurOn" } ] } ] },

        { id: "hyprInput", wm: "hyprland", group: "Hyprland", icon: "󰌌", title: "Input", store: "hyprland",
          desc: "Keyboard, mouse and touchpad",
          sections: [
            { title: "Keyboard", items: [ { key: "kbLayout" }, { key: "numlock" } ] },
            { title: "Pointer", items: [ { key: "sensitivity" }, { key: "accelProfile" }, { key: "followMouse" } ] },
            { title: "Touchpad", items: [ { key: "naturalScroll" }, { key: "scrollFactor" } ] } ] }
    ]

    // niri / hyprland stores: their settings service
    function isWm(store) { return store === "niri" || store === "hyprland" }
    function wmFor(store) { return store === "hyprland" ? HyprSettings : NiriSettings }

    function fullSpec(store, item) {
        return isWm(store) ? Object.assign({}, wmFor(store).spec(item.key), item) : item
    }

    // current value of a setting in any store (for dependsOn)
    function valueOf(store, key) {
        if (isWm(store)) return wmFor(store).value(key)
        if (store === "calendar") {
            const v = Settings.calendar[key]
            if (v !== undefined) return v
            const p = pages.find(p => p.store === "calendar")
            for (const s of p.sections) for (const i of s.items) if (i.key === key) return i.def
            return undefined
        }
        return Properties[key]
    }

    function pageKeys(page) {
        const keys = []
        for (const s of page.sections ?? [])
            for (const i of s.items) keys.push(i.key)
        return keys
    }

    LazyLoader {
        active: root.open

        FloatingWindow {
            id: win
            title: NiriSettings.windowTitle
            implicitWidth: 980
            implicitHeight: 680
            minimumSize: Qt.size(760, 460)
            color: "transparent"
            visible: true
            // closed by niri (Mod+C) → unload
            onVisibleChanged: if (!visible) root.open = false

            property string query: ""
            readonly property string pageId: root.pageId
            readonly property var page: root.visiblePages.find(p => p.id === pageId) ?? root.visiblePages[0]

            // sections to show: the page, or search hits across all pages
            readonly property var sections: {
                const q = query.trim().toLowerCase()
                if (q === "")
                    return (page.sections ?? []).map(s => ({ title: s.title, store: page.store, items: s.items }))
                const out = []
                for (const p of root.visiblePages) {
                    for (const s of p.sections ?? []) {
                        const hits = s.items.filter(i => {
                            const sp = root.fullSpec(p.store, i)
                            return (sp.label + " " + (sp.desc ?? "") + " " + p.title + " " + s.title).toLowerCase().includes(q)
                        })
                        if (hits.length > 0)
                            out.push({ title: p.title + "  ·  " + s.title, store: p.store, items: hits })
                    }
                }
                return out
            }

            Component.onCompleted: Compositor.settings.refresh()

            Rectangle {
                id: bg
                anchors.fill: parent
                radius: Compositor.appRadius          // same corners as the compositor's windows
                color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.86)
                // no own border: the compositor draws the window's border (one inside got clipped at the corners)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 14

                    // ── Sidebar ───────────────────────────────────────────────
                    Rectangle {
                        Layout.preferredWidth: 230
                        Layout.fillHeight: true
                        radius: Math.max(6, Compositor.appRadius - 2)
                        color: "#27000000"
                        border.width: Properties.panelBorderWidth
                        border.color: Properties.cardBorder

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 6

                            // title, also the drag handle for the window
                            Item {
                                Layout.fillWidth: true
                                implicitHeight: 44
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 4
                                    spacing: 10
                                    Text {
                                        text: "󰒓"
                                        color: Colors.color6
                                        font.pixelSize: 22
                                        font.family: Properties.fontFamily
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Settings"
                                        color: "white"
                                        font.pixelSize: 18
                                        font.bold: true
                                        font.family: Properties.fontFamily
                                    }
                                }
                                DragHandler {
                                    target: null
                                    onActiveChanged: if (active) bg.Window.window.startSystemMove()
                                }
                            }

                            SearchField {
                                Layout.fillWidth: true
                                Layout.bottomMargin: 6
                                implicitHeight: Properties.buttonHeight + 2
                                placeholderText: "Search settings"
                                onTextChanged: win.query = text
                                Keys.onEscapePressed: text = ""
                            }

                            // the tabs scroll when the window is too short for all of them
                            Flickable {
                                id: navFlick
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                // reach into the sidebar padding so the hover scale isn't clipped
                                Layout.leftMargin: -4
                                Layout.rightMargin: -4
                                contentHeight: nav.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                ColumnLayout {
                                    id: nav
                                    x: 4
                                    width: navFlick.width - 8
                                    spacing: 6

                                    Repeater {
                                        model: ["Shell", "Apps", root.wmGroup]
                                        ColumnLayout {
                                            id: group
                                            required property string modelData
                                            Layout.fillWidth: true
                                            spacing: 3

                                            Text {
                                                Layout.topMargin: 6
                                                Layout.leftMargin: 8
                                                Layout.bottomMargin: 2
                                                text: group.modelData.toUpperCase()
                                                color: Qt.rgba(1, 1, 1, 0.4)
                                                font.pixelSize: 10
                                                font.bold: true
                                                font.letterSpacing: 1.2
                                                font.family: Properties.fontFamily
                                            }

                                            Repeater {
                                                model: root.visiblePages.filter(p => p.group === group.modelData)
                                                NavItem {
                                                    required property var modelData
                                                    Layout.fillWidth: true
                                                    icon: modelData.icon
                                                    label: modelData.title
                                                    selected: win.query === "" && win.pageId === modelData.id
                                                    changes: modelData.custom === "monitors" ? Object.keys(Settings.monitors).length : root.pageKeys(modelData)
                                                        .filter(k => Settings[modelData.store]?.[k] !== undefined).length
                                                    onClicked: { root.pageId = modelData.id; flick.contentY = 0 }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 6
                                spacing: 6
                                ActionButton {
                                    Layout.fillWidth: true
                                    icon: "󰈝"
                                    text: "Export"
                                    interactive: transfer.mode !== "busy"
                                    onClicked: transfer.exportSettings()
                                }
                                ActionButton {
                                    Layout.fillWidth: true
                                    icon: "󰋺"
                                    text: "Import"
                                    interactive: transfer.mode !== "busy"
                                    onClicked: transfer.importSettings()
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.leftMargin: 8
                                text: "Changes apply right away (monitors after Apply).\nThe dot marks changed values."
                                color: Qt.rgba(1, 1, 1, 0.35)
                                font.pixelSize: 10
                                font.family: Properties.fontFamily
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    // ── Content ───────────────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 10

                        // header (drag handle too)
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 56

                            DragHandler {
                                target: null
                                onActiveChanged: if (active) bg.Window.window.startSystemMove()
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                spacing: 8

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Text {
                                        text: win.query !== "" ? "Search" : win.page.title
                                        color: "white"
                                        font.pixelSize: 24
                                        font.bold: true
                                        font.family: Properties.fontFamily
                                    }
                                    Text {
                                        text: win.query !== ""
                                            ? (win.sections.length > 0 ? "Results for \"" + win.query + "\"" : "Nothing matches \"" + win.query + "\"")
                                            : win.page.desc
                                        color: Qt.rgba(1, 1, 1, 0.5)
                                        font.pixelSize: 12
                                        font.family: Properties.fontFamily
                                    }
                                }

                                IconButton {
                                    visible: win.query === "" && !win.page.custom
                                    icon: "󰑓"
                                    tooltip: root.isWm(win.page.store) ? "Reset page to your " + Compositor.name + " config" : "Reset page to defaults"
                                    interactive: root.pageKeys(win.page)
                                        .some(k => Settings[win.page.store ?? "properties"]?.[k] !== undefined)
                                    onClicked: {
                                        for (const k of root.pageKeys(win.page)) {
                                            if (root.isWm(win.page.store)) root.wmFor(win.page.store).reset(k)
                                            else Settings.reset(win.page.store, k)
                                        }
                                    }
                                }
                                IconButton {
                                    icon: "󰅖"
                                    tooltip: "Close"
                                    onClicked: root.open = false
                                }
                            }
                        }

                        // export / import result; an import waits here for confirmation
                        SettingsTransfer {
                            id: transfer
                            Layout.fillWidth: true
                            pages: root.pages
                        }

                        // compositor status: missing include / rejected config
                        Rectangle {
                            id: wmBanner
                            readonly property var svc: root.wmFor(win.page.store)
                            readonly property bool hypr: win.page.store === "hyprland"
                            Layout.fillWidth: true
                            visible: win.query === "" && root.isWm(win.page.store)
                                     && (!svc.included || svc.error !== "" || (hypr && !svc.available))
                            implicitHeight: banner.implicitHeight + 20
                            radius: 14
                            color: Qt.rgba(0.95, 0.55, 0.66, 0.12)
                            border.width: Properties.panelBorderWidth
                            border.color: Qt.rgba(0.95, 0.55, 0.66, 0.35)

                            RowLayout {
                                id: banner
                                anchors.fill: parent
                                anchors.margins: 10
                                anchors.leftMargin: 14
                                spacing: 10
                                Text {
                                    text: "󰀦"
                                    color: "#f38ba8"
                                    font.pixelSize: 18
                                    font.family: Properties.fontFamily
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: wmBanner.hypr && !wmBanner.svc.available
                                        ? (wmBanner.svc.legacyConfig
                                            ? "Only Hyprland's Lua config (hyprland.lua, Hyprland 0.55+) is supported, this one is hyprland.conf."
                                            : "No Hyprland config found at " + wmBanner.svc.mainConfig)
                                        : !wmBanner.svc.included
                                        ? (wmBanner.hypr
                                            ? "Hyprland doesn't load the settings yet: " + wmBanner.svc.mainConfig
                                              + " needs this as its last line\n" + wmBanner.svc.includeLine
                                            : "niri doesn't load the settings yet: " + wmBanner.svc.mainConfig
                                              + " needs the line\n" + wmBanner.svc.includeLine)
                                        : Compositor.name + " rejected the change, nothing was written:\n" + wmBanner.svc.error
                                    color: "white"
                                    font.pixelSize: 11
                                    font.family: Properties.fontFamily
                                    wrapMode: Text.WordWrap
                                }
                                IconButton {
                                    visible: wmBanner.svc.included
                                    icon: "󰑓"
                                    tooltip: "Undo all " + Compositor.name + " changes"
                                    onClicked: wmBanner.svc.resetAll()
                                }
                            }
                        }

                        Flickable {
                            id: flick
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentHeight: content.implicitHeight + 8
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: content
                                width: flick.width
                                spacing: 18

                                Loader {
                                    Layout.fillWidth: true
                                    active: win.query === "" && win.page.custom === "monitors"
                                    visible: active
                                    sourceComponent: MonitorsPage {}
                                }

                                Repeater {
                                    model: win.sections
                                    ColumnLayout {
                                        id: section
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Text {
                                            Layout.leftMargin: 6
                                            text: section.modelData.title
                                            color: Qt.rgba(1, 1, 1, 0.55)
                                            font.pixelSize: 12
                                            font.bold: true
                                            font.family: Properties.fontFamily
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: items.implicitHeight
                                            radius: 14
                                            color: "#27000000"
                                            border.width: Properties.panelBorderWidth
                                            border.color: Properties.cardBorder

                                            ColumnLayout {
                                                id: items
                                                width: parent.width
                                                spacing: 0

                                                Repeater {
                                                    model: section.modelData.items
                                                    ColumnLayout {
                                                        id: entry
                                                        required property var modelData
                                                        required property int index
                                                        Layout.fillWidth: true
                                                        spacing: 0

                                                        Rectangle {
                                                            visible: entry.index > 0
                                                            Layout.fillWidth: true
                                                            Layout.leftMargin: 16
                                                            Layout.rightMargin: 16
                                                            implicitHeight: 1
                                                            color: Qt.rgba(1, 1, 1, 0.06)
                                                        }

                                                        SettingItem {
                                                            Layout.fillWidth: true
                                                            store: section.modelData.store
                                                            spec: root.fullSpec(section.modelData.store, entry.modelData)
                                                            sub: entry.modelData.dependsOn !== undefined
                                                            parentOn: entry.modelData.dependsOn === undefined
                                                                      || !!root.valueOf(section.modelData.store, entry.modelData.dependsOn)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                        }
                    }
                }
            }
        }
    }
}
