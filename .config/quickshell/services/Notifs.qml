pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// ── Notification store ──
// Single source of truth for both the popups (NotifPopup.qml) and the
// notification center (NotificationsSection.qml).
//
// Both views use ListModels (not JS arrays) so adding/removing one entry
// only creates/destroys that one delegate — reassigning a JS array would
// rebuild every delegate and kill any running animation.
//
// Removal is always two-step so the views can animate it:
//   1. the entry's `closing` role is set to true → delegate plays its exit animation
//   2. after `exitDuration` the entry is actually removed from the model
Singleton {
    id: root

    // ── Tunables ──────────────────────────────────────────────
    readonly property int popupTimeout: 5000   // used when the app doesn't specify one
    readonly property int maxPopups: 5         // oldest popup gets hidden beyond this
    readonly property int exitDuration: 420    // must cover the delegates' exit animations
    readonly property int clearStagger: 45     // delay between groups on "clear all"

    // ── Models ────────────────────────────────────────────────
    // popupModel:  { uid, appName, appIcon, image, summary, body, urgency, timeout, closing }
    // groupModel:  { appName, appIcon, time, expanded, closing, items: ListModel }
    //   items:     { uid, summary, body, image, time, closing }
    readonly property alias popupModel: popupModel
    readonly property alias groupModel: groupModel
    readonly property int count: _count

    // Ticks every 30s so relative timestamps ("5m ago") stay fresh.
    property double now: Date.now()

    // uid -> live Notification object (for actions / dismiss).
    property var _notifs: ({})
    property int _count: 0
    property int _nextUid: 1

    ListModel { id: popupModel }
    ListModel { id: groupModel }

    Timer {
        interval: 30000; running: true; repeat: true
        onTriggered: root.now = Date.now()
    }

    NotificationServer {
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        // Keep notifications across config reloads. Re-emitted ones have
        // lastGeneration set — they go back into the center, but don't pop up again.
        keepOnReload: true

        onNotification: notif => {
            notif.tracked = true // must happen synchronously or the notification is discarded
            // Re-emitted notifications arrive *while the reloaded config is still
            // being constructed*. Creating the center's delegates (with icon Images)
            // at that point segfaults Qt in QQuickImageBase::loadPixmap, so wait
            // until construction has finished.
            if (notif.lastGeneration) Qt.callLater(() => root._add(notif))
            else root._add(notif)
        }
    }

    // Bind these to keys, e.g. in niri:
    //   Mod+N { spawn "qs" "ipc" "call" "notifs" "dismissLatest"; }
    IpcHandler {
        target: "notifs"
        function dismissLatest(): void {
            if (popupModel.count > 0) {
                for (let i = 0; i < popupModel.count; i++)
                    if (!popupModel.get(i).closing) { root.dismiss(popupModel.get(i).uid); return }
            }
        }
        function clearAll(): void { root.clearAll() }
        function count(): int { return root.count }
    }

    // ── Public API ────────────────────────────────────────────

    // Popup timed out: hide the popup, keep it in the center.
    function hidePopup(uid) {
        const i = _indexOf(popupModel, uid)
        if (i < 0 || popupModel.get(i).closing) return
        popupModel.setProperty(i, "closing", true)
        _later(() => { const j = _indexOf(popupModel, uid); if (j >= 0) popupModel.remove(j) })
    }

    // User closed it (✕, drag, click): remove it everywhere and tell the app.
    function dismiss(uid) {
        hidePopup(uid)
        _removeFromCenter(uid)
        const n = _notifs[uid]
        delete _notifs[uid]
        if (n) n.dismiss()
    }

    // Click on a notification: run its default action (if any), then dismiss.
    function activate(uid) {
        const n = _notifs[uid]
        const def = n?.actions.find(a => a.identifier === "default")
        if (def) def.invoke()
        dismiss(uid)
    }

    function invokeAction(uid, identifier) {
        const n = _notifs[uid]
        const a = n?.actions.find(a => a.identifier === identifier)
        if (a) a.invoke()
        dismiss(uid)
    }

    // Non-default actions as plain {identifier, text} so delegates can render them.
    function actionsFor(uid) {
        const n = _notifs[uid]
        if (!n) return []
        return n.actions
            .filter(a => a.identifier !== "default" && a.text !== "")
            .map(a => ({ identifier: a.identifier, text: a.text }))
    }

    function hasDefaultAction(uid) {
        return !!_notifs[uid]?.actions.some(a => a.identifier === "default")
    }

    function toggleGroup(appName) {
        const i = _groupIndex(appName)
        if (i >= 0) groupModel.setProperty(i, "expanded", !groupModel.get(i).expanded)
    }

    function collapseAll() {
        for (let i = 0; i < groupModel.count; i++)
            if (groupModel.get(i).expanded) groupModel.setProperty(i, "expanded", false)
    }

    function dismissGroup(appName) {
        const i = _groupIndex(appName)
        if (i < 0) return
        const items = groupModel.get(i).items
        const uids = []
        for (let k = 0; k < items.count; k++) uids.push(items.get(k).uid)
        _closeGroup(appName)
        uids.forEach(uid => { hidePopup(uid); _forget(uid) })
    }

    // Staggered: each group slides out a little after the one above it.
    function clearAll() {
        const names = []
        for (let i = 0; i < groupModel.count; i++)
            if (!groupModel.get(i).closing) names.push(groupModel.get(i).appName)
        names.forEach((name, i) => _later(() => root.dismissGroup(name), i * clearStagger))
    }

    function relativeTime(t) {
        const s = Math.max(0, Math.floor((now - t) / 1000))
        if (s < 60) return "now"
        if (s < 3600) return Math.floor(s / 60) + "m"
        if (s < 86400) return Math.floor(s / 3600) + "h"
        return Math.floor(s / 86400) + "d"
    }

    // appIcon can be an icon name, an absolute path or a file:// URL.
    // Falls back to the icon of the app's .desktop entry.
    function iconSource(appIcon, desktopEntry) {
        let icon = appIcon || ""
        if (!icon && desktopEntry) icon = DesktopEntries.byId(desktopEntry)?.icon ?? ""
        if (!icon) return ""
        if (icon.startsWith("/")) return "file://" + icon
        if (icon.includes("://")) return icon
        return Quickshell.iconPath(icon, true)
    }

    // ── Internals ─────────────────────────────────────────────

    function _add(notif) {
        notif.tracked = true
        const uid = _nextUid++
        _notifs[uid] = notif

        const appName = notif.appName || "Unknown"
        const appIcon = iconSource(notif.appIcon, notif.desktopEntry)
        const image = notif.image || ""
        const time = Date.now()

        // App closed/replaced the notification on its own → drop it everywhere.
        notif.closed.connect(() => {
            if (!(uid in root._notifs)) return // we dismissed it ourselves
            delete root._notifs[uid]
            root.hidePopup(uid)
            root._removeFromCenter(uid)
        })

        // ── center ──
        const item = { uid, summary: notif.summary || "", body: notif.body || "", image, time, closing: false }
        let gi = _groupIndex(appName)
        if (gi < 0) {
            groupModel.insert(0, { appName, appIcon, time, expanded: false, closing: false, items: [item] })
        } else {
            const g = groupModel.get(gi)
            g.items.insert(0, item)
            groupModel.setProperty(gi, "time", time)
            if (appIcon) groupModel.setProperty(gi, "appIcon", appIcon)
            if (gi > 0) groupModel.move(gi, 0, 1)
        }
        _count++

        // ── popup ──
        if (notif.lastGeneration) return
        popupModel.insert(0, {
            uid, appName, appIcon, image,
            summary: notif.summary || "",
            body: notif.body || "",
            urgency: notif.urgency,
            timeout: notif.expireTimeout > 0 ? notif.expireTimeout : popupTimeout,
            closing: false
        })
        // Too many on screen → retire the oldest visible one.
        let visible = 0
        for (let i = 0; i < popupModel.count; i++) {
            if (popupModel.get(i).closing) continue
            if (++visible > maxPopups) hidePopup(popupModel.get(i).uid)
        }
    }

    function _removeFromCenter(uid) {
        for (let gi = 0; gi < groupModel.count; gi++) {
            const g = groupModel.get(gi)
            const ii = _indexOf(g.items, uid)
            if (ii < 0) continue
            if (g.items.get(ii).closing || g.closing) return

            // Count what's left once this one is gone; last one → close the whole group.
            let alive = 0
            for (let k = 0; k < g.items.count; k++) if (!g.items.get(k).closing) alive++
            if (alive <= 1) {
                _closeGroup(g.appName)
                return
            }
            g.items.setProperty(ii, "closing", true)
            _count--
            const appName = g.appName
            _later(() => {
                const gj = root._groupIndex(appName)
                if (gj < 0) return
                const items = groupModel.get(gj).items
                const ij = root._indexOf(items, uid)
                if (ij >= 0) items.remove(ij)
            })
            return
        }
    }

    function _closeGroup(appName) {
        const gi = _groupIndex(appName)
        if (gi < 0 || groupModel.get(gi).closing) return
        const items = groupModel.get(gi).items
        for (let k = 0; k < items.count; k++) if (!items.get(k).closing) _count--
        groupModel.setProperty(gi, "closing", true)
        _later(() => {
            // Look it up again — indices may have shifted in the meantime.
            for (let i = 0; i < groupModel.count; i++) {
                const g = groupModel.get(i)
                if (g.appName === appName && g.closing) { groupModel.remove(i); return }
            }
        })
    }

    // Dismiss the Notification object without touching the models.
    function _forget(uid) {
        const n = _notifs[uid]
        delete _notifs[uid]
        if (n) n.dismiss()
    }

    function _indexOf(model, uid) {
        for (let i = 0; i < model.count; i++) if (model.get(i).uid === uid) return i
        return -1
    }

    // Closing groups don't count — a new notification from that app starts a fresh group.
    function _groupIndex(appName) {
        for (let i = 0; i < groupModel.count; i++) {
            const g = groupModel.get(i)
            if (g.appName === appName && !g.closing) return i
        }
        return -1
    }

    function _later(fn, delay) {
        const t = laterTimer.createObject(root, { interval: delay ?? exitDuration })
        t.triggered.connect(() => { fn(); t.destroy() })
        t.start()
    }

    Component {
        id: laterTimer
        Timer { repeat: false }
    }
}
