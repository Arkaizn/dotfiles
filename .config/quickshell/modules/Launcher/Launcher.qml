import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Wayland
import qs.components
import qs.services
import QtQuick.Effects

// ── Root of the launcher ──
// Owns the PanelWindow/layer-shell surface, the open/close slide animation,
// the shared search field, and the small mode-switcher (search vs
// clipboard). The actual result lists live in AppSearch.qml and
// ClipboardHistory.qml — this file just decides which one is showing and
// feeds them both the same search text.
PanelWindow {
    id: root
    visible: false

    // NOTE: only "bottom" is anchored (no left/right), which is what centers
    // this horizontally in Quickshell — same trick the dashboard uses.
    anchors {
        bottom: true
    }
    implicitWidth: 640

    // ── Why the surface size is a constant, not a binding ──
    // implicitHeight here drives the *real* Wayland layer-shell surface
    // (via WlrLayershell), not just a QtQuick item. Every time it changes,
    // Quickshell has to renegotiate a new surface size with the compositor.
    // That's fine once (e.g. on open), but animating it — or even just
    // letting it snap around every keystroke, or every time you switch
    // between the apps and clipboard views — causes visible desync:
    // ghosting, stale content bleeding through, UI elements briefly
    // rendered at the wrong position relative to the new bounds.
    //
    // The fix: make the surface a fixed size, big enough for the tallest
    // possible state across *both* views, and never touch it again while
    // the launcher is open. All the *visible* growing/shrinking happens on
    // `card` below instead — an ordinary Rectangle inside the surface,
    // animated with a plain `Behavior on height`. That's pure GPU-side
    // compositing, not a surface reconfigure, so it can animate as smoothly
    // as any other QtQuick property — including when switching modes.
    readonly property int maxResultsHeight: 360
    readonly property int contentSpacing: 8
    readonly property int modeBarHeight: 28
    readonly property int contentMargins: 16 + 26 // matches content's anchors.margins + bottomMargin below

    // tallest results list + search bar + mode-switcher row + the two gaps
    // between them (content always has exactly 3 visible children: one of
    // the two views, the search field, and the mode bar) + outer margins.
    implicitHeight: maxResultsHeight + contentSpacing * 2 + Properties.buttonHeight + modeBarHeight + contentMargins

    color: '#00000000'
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusiveZone: 0

    // Restricts click/hover input to the visible card instead of the whole
    // (mostly-empty, transparent) fixed-size surface. If your Quickshell
    // version doesn't support `mask` on PanelWindow, just delete this block —
    // everything else works without it, you'd just get a slightly larger
    // invisible click-catching area above the card.
    mask: Region {
        item: card
    }

    IpcHandler {
        target: "Launcher"
        function toggleAppSearch(): void {
            root.toggle()
        }
        // Dedicated clipboard-history entrypoint — bind this directly to a
        // hotkey (e.g. Super+V) if you want clipboard history to open
        // straight up instead of going through the apps view first.
        function toggleClipboard(): void {
            root.toggle("clipboard")
        }
    }

    BackgroundEffect.blurRegion: Region {
        item: card
        topLeftRadius: 12
        topRightRadius: 12
    }

    PopupAnimation {
        id: anim
        target: rect
        direction: "top"
        enterDuration: 150
        exitDuration: 150
        onExitFinished: root.visible = false
    }

    // Which sub-view is showing.
    property string mode: "apps" // "apps" | "clipboard"

    // Switching modes always clears the search text — carrying an "apps"
    // query like "steam" over into clipboard search would just be
    // confusing. Delete this if you'd rather the query persist across modes.
    onModeChanged: searchField.text = ""

    // Opens the launcher (optionally straight into a given mode), or closes
    // it if already open. Passing a mode while the launcher is already open
    // just switches views in place instead of closing — that's what makes
    // toggleClipboard() above useful as its own hotkey rather than only a
    // fresh-open action.
    function toggle(targetMode) {
        if (root.visible) {
            if (targetMode && targetMode !== root.mode) {
                root.mode = targetMode
            } else {
                anim.exit()
            }
            return
        }

        // Fresh opens always land on "apps" (or whatever targetMode was
        // explicitly requested) — deliberately NOT `root.mode`, so the panel
        // never "remembers" that you were on the clipboard tab last time.
        root.mode = targetMode || "apps"
        root.visible = true
        searchField.text = ""
        // `active` on ClipboardHistory only refreshes on the 0->1 edge, so
        // if we're reopening while still parked on the clipboard tab from
        // last time, force a refresh — otherwise you'd see a stale list.
        if (root.mode === "clipboard") clipboardView.refresh()
        enterTimer.start()
    }

    Timer {
        id: enterTimer
        interval: 50
        repeat: false
        onTriggered: {
            anim.enter()
            searchField.forceActiveFocus()
        }
    }

    // Routes keyboard nav to whichever view is currently visible.
    function activeView() {
        return root.mode === "apps" ? appSearchView : clipboardView
    }

    // ── Stable wrapper for the open/close slide animation ──
    // Fixed size, fills the whole (fixed-size) surface. PopupAnimation
    // targets THIS, not the dynamically-sized card below. Reason:
    // PopupAnimation almost certainly animates `y` (or `scale`) directly for
    // its slide effect, and the moment something animates `y` on an item,
    // QML silently breaks that item's `anchors.bottom` binding. `card` below
    // is bottom-anchored with a *variable* height, so if PopupAnimation
    // targeted it directly, the entrance animation would finish by
    // hard-setting `y` to some value, permanently detaching it from
    // `parent.height - card.height` — which is exactly why it flashed open
    // then vanished. By keeping the open/close animation on a target that
    // never resizes, there's nothing for it to conflict with.
    Item {
        id: rect
        anchors.fill: parent

        // ── The visible card ──
        // This is the piece that actually grows/shrinks on screen, nested
        // inside the stable `rect` above so its own height animation never
        // interacts with the open/close slide.
        Rectangle {
            id: card
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: content.implicitHeight + 32
            color: "transparent"
            radius: 12

            Behavior on height {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

            ColumnLayout {
                id: content
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 16
                anchors.bottomMargin: 26
                spacing: root.contentSpacing

                // ── The two views, both always instantiated ──
                // Same opacity/visible pattern your original file used for
                // recommendedFlow vs resultsList: whichever isn't active
                // fades to opacity 0 and gets `visible: false`, which drops
                // it out of the ColumnLayout's height calculation entirely.
                // That's what lets `card` smoothly animate its height when
                // you switch between a tall clipboard list and a short apps
                // grid, instead of snapping.
                AppSearch {
                    id: appSearchView
                    Layout.fillWidth: true
                    maxHeight: root.maxResultsHeight
                    query: searchField.text
                    opacity: root.mode === "apps" ? 1 : 0
                    visible: opacity > 0
                    onCloseRequested: { root.visible = false; searchField.text = "" }

                    Behavior on opacity {
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }
                }

                ClipboardHistory {
                    id: clipboardView
                    Layout.fillWidth: true
                    maxHeight: root.maxResultsHeight
                    query: searchField.text
                    active: root.mode === "clipboard"
                    opacity: root.mode === "clipboard" ? 1 : 0
                    visible: opacity > 0
                    onCloseRequested: { root.visible = false; searchField.text = "" }

                    Behavior on opacity {
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }
                }

                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    Layout.preferredHeight: Properties.buttonHeight
                    placeholderText: root.mode === "apps" ? "Search apps" : "Search clipboard history"
                    placeholderTextColor: Qt.rgba(1, 1, 1, 0.35)
                    color: Properties.color
                    font.pixelSize: 13
                    verticalAlignment: TextInput.AlignVCenter

                    background: Rectangle {
                        radius: Properties.radius
                        color: Qt.rgba(0, 0, 0, 0.18)
                        border.width: 1.5
                        border.color: Qt.rgba(1, 1, 1, searchField.activeFocus ? 0.28 : 0.18)
                        gradient: ButtonGradient { hovered: searchField.activeFocus }
                    }

                    Text {
                        id: clearIcon
                        text: "✕"
                        color: Qt.rgba(1, 1, 1, 0.5)
                        font.pixelSize: 11
                        visible: searchField.text.length > 0
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: searchField.text = ""
                        }
                    }

                    Keys.onDownPressed: root.activeView().moveDown()
                    Keys.onUpPressed: root.activeView().moveUp()
                    Keys.onReturnPressed: root.activeView().activateCurrent()

                    // Tab switches between apps <-> clipboard without
                    // touching the mouse. Remove if you'd rather Tab do the
                    // usual focus-chain thing.
                    Keys.onTabPressed: (event) => {
                        root.mode = root.mode === "apps" ? "clipboard" : "apps"
                        event.accepted = true
                    }

                    // Esc always closes. Delete only closes when the field is
                    // already empty, so it doesn't fight with deleting
                    // characters while typing.
                    Keys.onEscapePressed: anim.exit()
                    Keys.onDeletePressed: (event) => {
                        if (searchField.text.length === 0) {
                            anim.exit()
                        } else {
                            event.accepted = false
                        }
                    }
                }

                // ── Mode switcher — the two icon buttons from the sketch ──
                RowLayout {
                    id: modeBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.modeBarHeight
                    spacing: 8

                    Repeater {
                        model: [
                            { value: "apps", glyph: "⌕" },
                            { value: "clipboard", glyph: "⎘" }
                        ]

                        Item {
                            id: modeBtn
                            required property var modelData
                            readonly property bool isActive: root.mode === modelData.value
                            width: root.modeBarHeight
                            height: root.modeBarHeight

                            HoverHandler { id: modeHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.mode = modeBtn.modelData.value }

                            // Persistent soft fill + border on the active
                            // mode, plain hover fill on the other — same
                            // visual language as the result rows below.
                            Rectangle {
                                anchors.fill: parent
                                radius: 6
                                color: modeBtn.isActive ? Qt.rgba(1, 1, 1, 0.14)
                                     : modeHover.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                                border.width: modeBtn.isActive ? 1 : 0
                                border.color: Qt.rgba(1, 1, 1, 0.22)
                                Behavior on color { ColorAnimation { duration: 80 } }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: modeBtn.modelData.glyph
                                font.pixelSize: 14
                                color: modeBtn.isActive ? "white" : Qt.rgba(1, 1, 1, 0.6)
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }
            }
        }
    }
}
