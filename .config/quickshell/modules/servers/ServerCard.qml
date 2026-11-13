import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.lib

// One server in the Servers app: status dot, name, address, what the last scan
// found (badges), its health checks (chips; an http one opens its page) and the
// quick actions (terminal, files, menu). `compact`: one row, for the list view.
//
//   ServerCard { server: s; compact: false; onEdit: …; onMenu: (item, x, y) => … }
Pressable {
    id: root

    required property var server
    property bool compact: false
    readonly property var info: ServerStore.info[server.name] ?? ({})
    readonly property bool archived: server.archived

    signal edit()
    signal menu(Item item, real x, real y)
    signal updateRequested(Item item)
    // dragging it onto a group (scene coordinates; the window maps them)
    signal dragStarted(point scenePos, point grab)
    signal dragMoved(point scenePos)
    signal dragEnded()
    property bool dragged: false             // set by the window while this one is dragged

    // archive / restore / delete: shrinks away before the list changes
    readonly property bool leaving: ServerStore.leaving[server.name] === true

    // what a running scan / update is doing on it right now
    readonly property var run: ServerRuns.per(server.name)
    // scans / checks do every server at once (no steps); updates go in waves (steps, waiting ones)
    readonly property string runMode: ServerRuns.modeOf(server.name)
    readonly property bool parallel: runMode !== "update"
    readonly property bool working: run !== null && (run.status ?? "") === "" && ((run.phase ?? "") !== "" || parallel)
    readonly property bool queued: run !== null && (run.status ?? "") === "" && !working
    readonly property string runText: !run ? "" : (run.status ?? "") !== "" ? run.status
        : run.phase || (runMode === "check" ? "health checks…" : parallel ? "scanning…" : "waiting")

    // offline / not checked: grey · critical (security, reboot) or failing checks: red ·
    // normal updates: orange · nothing to do: green (ServerStore.statusColor, same everywhere)
    readonly property color statusColor: ServerStore.statusColor(server.name)
    // Select mode (the window's Select button): a click ticks it instead of opening the details
    readonly property bool selecting: ServerStore.selecting && !archived
    readonly property bool selected: selecting && ServerStore.selection.includes(server.name)
    readonly property string statusText: working ? runText : info.checking ? "checking…"
        : info.reachable === false ? "offline" + (info.error ? ": " + info.error.replace(/^ssh: /, "") : "")
        : info.scanned && !info.scanOk ? "online, but the scan failed: " + info.scanError.replace(/^ssh: /, "")
        : info.reachable === null || info.reachable === undefined ? "not checked yet"
        : "online" + (info.live ? "" : " at the last scan")

    tooltip: ""
    accessibleName: server.name
    implicitHeight: compact ? row.implicitHeight + 2 * Tokens.space.s10 : col.implicitHeight + 2 * Tokens.space.s14
    opacity: leaving ? 0 : dragged ? 0.3 : archived ? 0.6 : 1
    scale: leaving ? 0.85 : 1
    Behavior on opacity { NumberAnimation { duration: Anim.medium; easing.type: Anim.standard } }
    Behavior on scale { NumberAnimation { duration: Anim.medium; easing.type: Anim.exit } }

    // hover that stays on while the pointer is over one of its buttons (Pressable's own
    // `hovered` goes off there: the button takes the hover)
    HoverHandler { id: cardHover }
    readonly property bool over: cardHover.hovered && !dragged

    DragHandler {
        id: dragH
        target: null
        dragThreshold: 12
        onActiveChanged: active ? root.dragStarted(centroid.scenePosition, centroid.pressPosition) : root.dragEnded()
        onCentroidChanged: if (active) root.dragMoved(centroid.scenePosition)
    }

    // a run's result for this server: a green glow (fine) or a shake + red edge (failed)
    readonly property string result: ServerRuns.resultOf(server.name)
    // Only for a result that comes in while this card is on screen and a run is going.
    // A card that is (re)built — at startup, on a reload, when the details pane opens and
    // the cards reflow — starts with the last run's result: that isn't news, no glow.
    property bool ready: false
    Component.onCompleted: ready = true
    onResultChanged: {
        if (!ready || !ServerRuns.anyBusy) return
        if (["ok", "up-to-date", "healthy"].includes(result)) glowAnim.restart()
        else if (["failed", "unreachable", "unhealthy", "rolled-back"].includes(result)) shakeAnim.restart()
    }
    SequentialAnimation {
        id: glowAnim
        PropertyAction { target: glow; property: "border.color"; value: Colors.green }
        ParallelAnimation {
            NumberAnimation { target: glow; property: "opacity"; from: 0; to: 0.9; duration: Anim.fast; easing.type: Anim.standard }
            // (a list row is wide: growing it would look like lines sliding over its neighbours)
            NumberAnimation { target: glow; property: "scale"; from: root.compact ? 1 : 0.98; to: root.compact ? 1 : 1.02; duration: Anim.medium; easing.type: Anim.standard }
        }
        NumberAnimation { target: glow; property: "opacity"; to: 0; duration: Anim.slower; easing.type: Anim.exit }
    }
    SequentialAnimation {
        id: shakeAnim
        PropertyAction { target: glow; property: "border.color"; value: Colors.red }
        PropertyAction { target: glow; property: "scale"; value: 1 }
        ParallelAnimation {
            SequentialAnimation {
                NumberAnimation { target: shakeT; property: "x"; to: -7; duration: 50 }
                NumberAnimation { target: shakeT; property: "x"; to: 6; duration: 70 }
                NumberAnimation { target: shakeT; property: "x"; to: -4; duration: 60 }
                NumberAnimation { target: shakeT; property: "x"; to: 2; duration: 50 }
                NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 40 }
            }
            SequentialAnimation {
                NumberAnimation { target: glow; property: "opacity"; to: 0.9; duration: Anim.fast }
                PauseAnimation { duration: Anim.medium }
                NumberAnimation { target: glow; property: "opacity"; to: 0; duration: Anim.slower; easing.type: Anim.exit }
            }
        }
    }
    onClicked: root.edit()
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onRightClicked: root.menu(root, root.width / 2, Math.min(root.height, 40))

    // hover: lifts a little, the border brightens; shakeT: a failed run
    transform: [
        Translate { y: root.over && !root.compact ? -2 : 0; Behavior on y { NumberAnimation { duration: Anim.fast; easing.type: Anim.standard } } },
        Translate { id: shakeT }
    ]

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: Tokens.radius.lg
        color: root.selected ? Colors.alpha(Colors.accent, root.over ? 0.16 : 0.11) : root.over ? Colors.fade(0.07) : Colors.card
        border.width: root.selected ? 1.5 : 1
        border.color: root.selected ? Colors.accent : root.over ? Colors.alpha(root.statusColor, 0.55) : Properties.cardBorder
        Behavior on color { ColorAnimation { duration: Anim.fast } }
        Behavior on border.color { ColorAnimation { duration: Anim.fast } }
        // a thin status line on the left edge
        Rectangle {
            x: 0; y: Tokens.space.s10
            width: 3; height: parent.height - 2 * Tokens.space.s10
            radius: 1.5
            color: root.statusColor
            opacity: 0.8
            Behavior on color { ColorAnimation { duration: Anim.medium } }
        }
    }

    Rectangle {
        id: glow
        anchors.fill: parent
        anchors.margins: -3
        radius: Tokens.radius.lg + 3
        color: "transparent"
        border.width: 2
        border.color: Colors.green
        opacity: 0
    }

    // ── pieces used by both layouts ──
    component Dot: Item {
        implicitWidth: 10; implicitHeight: 10
        Rectangle {
            id: core
            anchors.centerIn: parent
            width: 8; height: 8; radius: 4
            color: root.statusColor
            Behavior on color { ColorAnimation { duration: Anim.medium } }
        }
        // soft pulse while it's being checked
        Rectangle {
            anchors.centerIn: parent
            width: 8; height: 8; radius: 4
            color: "transparent"
            border.width: 1.5
            border.color: root.statusColor
            opacity: 0
            SequentialAnimation on scale {
                running: (root.info.checking === true || root.working) && Anim.ambient
                loops: Animation.Infinite
                NumberAnimation { from: 1; to: 2.4; duration: 900; easing.type: Anim.loop }
                PauseAnimation { duration: 200 }
            }
            SequentialAnimation on opacity {
                running: (root.info.checking === true || root.working) && Anim.ambient
                loops: Animation.Infinite
                NumberAnimation { from: 0.8; to: 0; duration: 900; easing.type: Anim.loop }
                PauseAnimation { duration: 200 }
            }
        }
        HoverTip { text: root.statusText; shown: dotArea.containsMouse }
        MouseArea { id: dotArea; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; acceptedButtons: Qt.NoButton }
    }

    component Badge: Rectangle {
        property string icon: ""
        property string text: ""
        property color tone: Colors.accent
        property string tip: ""
        implicitWidth: bl.implicitWidth + 14
        implicitHeight: 20
        radius: 10
        color: Colors.alpha(tone, 0.16)
        border.width: 1
        border.color: Colors.alpha(tone, 0.32)
        // pops in when it appears / its number changes
        scale: 1
        onTextChanged: if (visible) popAnim.restart()
        SequentialAnimation {
            id: popAnim
            NumberAnimation { target: parent; property: "scale"; to: 1.12; duration: Anim.instant; easing.type: Anim.standard }
            NumberAnimation { target: parent; property: "scale"; to: 1; duration: Anim.normal; easing.type: Anim.pop }
        }
        Text {
            id: bl
            anchors.centerIn: parent
            text: (parent.icon ? parent.icon + " " : "") + parent.text
            color: parent.tone
            font.pixelSize: Tokens.font.caption
            font.family: Properties.fontFamily
            font.bold: true
        }
        HoverTip { text: parent.tip; shown: parent.tip !== "" && bma.containsMouse }
        MouseArea { id: bma; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
    }

    component Badges: Flow {
        spacing: Tokens.space.s4
        Badge { visible: root.info.reachable === false; icon: "󰅛"; text: "offline"; tone: Colors.fade(0.6); tip: root.statusText }
        Badge { visible: root.info.security > 0; icon: "󰒃"; text: root.info.security + " security"; tone: Colors.red
                tip: "Security updates (critical)" }
        Badge { visible: root.info.reboot === true; icon: "󰜉"; text: "reboot"; tone: Colors.red
                tip: root.server.noReboot || root.info.proxmox ? "Needs a reboot (never rebooted automatically: do it by hand)" : "Needs a reboot" }
        Badge { visible: root.info.normal > 0; icon: "󰚰"; text: String(root.info.normal); tone: Colors.orange
                tip: root.info.normal + (root.info.normal === 1 ? " package update" : " package updates") }
        Badge { visible: root.info.containers > 0; icon: "󰡨"; text: String(root.info.containers); tone: Colors.orange
                tip: root.info.containers + (root.info.containers === 1 ? " container has a new image" : " containers have new images") }
        Badge { visible: (root.info.restartPending ?? 0) > 0; icon: "󰜉"; text: root.info.restartPending + " restart"; tone: Colors.orange
                tip: root.info.restartPending + (root.info.restartPending === 1 ? " container has" : " containers have") + " the new image downloaded and still run" + (root.info.restartPending === 1 ? "s" : "") + " the old one: restart from the details" }
        Badge { visible: (root.info.plainNew ?? 0) > 0; icon: "󰡨"; text: root.info.plainNew + " plain"; tone: root.server.plainContainers ? Colors.orange : Colors.fade(0.6)
                tip: root.info.plainNew + (root.info.plainNew === 1 ? " container" : " containers") + " started with docker run " + (root.info.plainNew === 1 ? "has" : "have") + " a newer image"
                     + (root.server.plainContainers ? "" : " (not updated: turn it on in Edit)") }
        Badge { visible: root.info.checksFailed > 0; icon: "󰀦"; text: root.info.checksFailed + " failing"; tone: Colors.red
                tip: (root.info.checks ?? []).filter(c => !c.ok).map(c => c.name + ": " + c.detail).join("\n") }
        Badge { visible: root.info.containersBad > 0; icon: "󰡨"; text: root.info.containersBad + " unhealthy"; tone: Colors.red }
        Badge { visible: root.info.stale === true; icon: "󰔟"; text: "rescan"; tone: Colors.fade(0.6); tip: "Updated since the last scan: scan again for the current state" }
        Badge { visible: root.info.scanOk === true && root.info.reachable !== false && root.info.packages + root.info.containers + (root.info.restartPending ?? 0) === 0 && !root.info.reboot
                icon: "󰄬"; text: "up to date"; tone: Colors.green }
        Badge { visible: root.info.scanned === true && root.info.scanOk !== true && root.info.reachable !== false
                icon: "󰅙"; text: "scan failed"; tone: Colors.fade(0.6); tip: root.info.scanError || "the scan couldn't get in" }
        Badge { visible: root.info.apiOnly === true; icon: "󰌆"; text: "API only"; tone: Colors.fade(0.6)
                tip: "Reached only through its API, for snapshots of its guests. The tool doesn't log in over SSH, so it doesn't scan or update the host itself" }
        Badge { visible: root.info.scanned !== true && root.info.reachable !== false && root.info.apiOnly !== true; icon: "󰔟"; text: "not scanned"; tone: Colors.fade(0.55) }
    }

    component Actions: RowLayout {
        property bool menuButton: true
        spacing: Tokens.space.s2
        IconButton { implicitWidth: 30; implicitHeight: 30; iconSize: Tokens.icon.sm; icon: "󰚰"; tooltip: "Update…"
                     visible: !root.archived && root.info.reachable !== false && !root.working; onClicked: root.updateRequested(this) }
        // a run is on it: stop this server only (a stuck wait ends right away, a running install finishes first)
        IconButton { implicitWidth: 30; implicitHeight: 30; iconSize: Tokens.icon.sm; icon: "󰜺"
                     tooltip: (root.run?.aborting ?? false) ? "Aborting…" : "Abort this server"
                     visible: root.working && root.runMode !== "check" && root.runMode !== "snapshots"
                     interactive: !(root.run?.aborting ?? false)
                     onClicked: ServerRuns.abortServer(root.server.name) }
        IconButton { implicitWidth: 30; implicitHeight: 30; iconSize: Tokens.icon.sm; icon: "󰑓"; tooltip: "Scan + health checks"
                     visible: !root.archived; busy: root.working; onClicked: ServerRuns.scanAll([root.server.name]) }
        IconButton { implicitWidth: 30; implicitHeight: 30; iconSize: Tokens.icon.sm; icon: "󰆍"; tooltip: "Terminal (SSH)"
                     onClicked: ServerStore.ssh(root.server.name) }
        IconButton { implicitWidth: 30; implicitHeight: 30; iconSize: Tokens.icon.sm; icon: "󰉋"; visible: root.server.sftp
                     tooltip: "Files (SFTP)"; onClicked: ServerStore.sftp(root.server.name) }
        IconButton { implicitWidth: 30; implicitHeight: 30; iconSize: Tokens.icon.sm; icon: "󰇘"; tooltip: "More"; visible: parent.menuButton
                     onClicked: root.menu(this, width / 2, height) }
    }

    readonly property string address: ServerStore.destOf(server) + (server.port !== 22 ? ":" + server.port : "")
    readonly property string scanAge: info.lastScan ? "scanned " + Format.ago(info.lastScan) : ""

    // ── card ──
    ColumnLayout {
        id: col
        visible: !root.compact
        anchors.fill: parent
        anchors.margins: Tokens.space.s14
        anchors.leftMargin: Tokens.space.s14 + 2
        spacing: Tokens.space.s8

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s8
            Dot { visible: !root.selecting }
            SelectMark { visible: root.selecting; selected: root.selected }
            ServerLogo { name: root.server.name; size: 30 }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: root.server.name
                    color: Colors.ink
                    font.pixelSize: Tokens.font.body
                    font.bold: true
                    font.family: Properties.fontFamily
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: root.address + (root.info.osName ? "  ·  " + root.info.osName.replace(/ GNU\/Linux| \(.*\)$/g, "") : root.info.pm ? "  ·  " + root.info.pm : "")
                          + (ServerStore.kindLabel(root.server) !== "" ? "  ·  " + ServerStore.kindLabel(root.server) : root.info.proxmox ? "  ·  Proxmox" : "")
                    color: Colors.textMuted
                    font.pixelSize: Tokens.font.caption
                    font.family: Properties.fontFamily
                    elide: Text.ElideRight
                }
            }
            IconButton { implicitWidth: 28; implicitHeight: 28; iconSize: Tokens.icon.sm; icon: "󰇘"; tooltip: "More"
                         onClicked: root.menu(this, width / 2, height) }
        }

        Badges { Layout.fillWidth: true }

        // a scan / update working on it: its current step
        RowLayout {
            Layout.fillWidth: true
            visible: root.working || root.queued
            spacing: Tokens.space.s6
            Spinner { running: root.working; visible: root.working; size: Tokens.font.caption }
            Text {
                Layout.fillWidth: true
                text: root.queued ? "waiting for its turn" : root.runText
                color: root.queued ? Colors.textFaint : Colors.accent
                font.pixelSize: Tokens.font.caption
                font.family: Properties.fontFamily
                elide: Text.ElideRight
            }
        }

        // health checks: a dot per check (green / red), http ones open their page
        Flow {
            Layout.fillWidth: true
            visible: root.info.checks?.length > 0
            spacing: Tokens.space.s4
            Repeater {
                model: (root.info.checks ?? []).slice(0, 10)
                Pressable {
                    id: chip
                    required property var modelData
                    readonly property bool web: modelData.type === "http"
                    implicitWidth: cl.implicitWidth + 16
                    implicitHeight: 22
                    interactive: web
                    dimDisabled: false
                    tooltip: modelData.name + ": " + (modelData.ok ? "ok" : modelData.detail) + (web ? "\n" + modelData.target : "")
                    onClicked: ServerStore.openUrl(modelData.target)
                    Rectangle {
                        anchors.fill: parent
                        radius: 11
                        color: chip.hovered ? Colors.fade(0.12) : Colors.fade(0.05)
                        Behavior on color { ColorAnimation { duration: Anim.fast } }
                    }
                    Row {
                        id: cl
                        anchors.centerIn: parent
                        spacing: 5
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: 3
                                    color: chip.modelData.ok ? Colors.green : Colors.red }
                        Text {
                            text: chip.modelData.name
                            color: Colors.textSecondary
                            font.pixelSize: Tokens.font.caption
                            font.family: Properties.fontFamily
                        }
                    }
                }
            }
            Text {
                visible: (root.info.checks ?? []).length > 10
                height: 22
                verticalAlignment: Text.AlignVCenter
                text: "+" + ((root.info.checks ?? []).length - 10)
                color: Colors.textFaint
                font.pixelSize: Tokens.font.caption
                font.family: Properties.fontFamily
            }
        }

        // footer: the quick actions (Termix-style), tags, when it was scanned
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.s6
            Actions { menuButton: false }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                text: root.server.tags.map(t => "#" + t).join(" ")
                color: Colors.textFaint
                font.pixelSize: Tokens.font.caption
                font.family: Properties.fontFamily
                elide: Text.ElideRight
            }
            Text {
                text: root.scanAge
                color: Colors.textFaint
                font.pixelSize: Tokens.font.caption
                font.family: Properties.fontFamily
            }
        }
    }

    // ── list row ──
    RowLayout {
        id: row
        visible: root.compact
        anchors.fill: parent
        anchors.leftMargin: Tokens.space.s14 + 2
        anchors.rightMargin: Tokens.space.s8
        spacing: Tokens.space.s10
        Dot { visible: !root.selecting }
        SelectMark { visible: root.selecting; selected: root.selected }
        ServerLogo { name: root.server.name; size: 20; badge: false }
        Text {
            Layout.preferredWidth: 170
            text: root.server.name
            color: Colors.ink
            font.pixelSize: Tokens.font.body
            font.bold: true
            font.family: Properties.fontFamily
            elide: Text.ElideRight
        }
        Text {
            Layout.preferredWidth: 170
            text: root.working || root.queued ? (root.queued ? "waiting…" : root.runText) : root.address
            color: root.working ? Colors.accent : Colors.textMuted
            font.pixelSize: Tokens.font.caption
            font.family: Properties.fontFamily
            elide: Text.ElideRight
        }
        Badges { Layout.fillWidth: true }
        Text {
            visible: (root.info.checks ?? []).length > 0
            text: ((root.info.checks ?? []).length - (root.info.checksFailed ?? 0)) + "/" + (root.info.checks ?? []).length + " checks"
            color: root.info.checksFailed > 0 ? Colors.red : Colors.textMuted
            font.pixelSize: Tokens.font.caption
            font.family: Properties.fontFamily
        }
        Actions {}
    }
}
