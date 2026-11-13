"""Live folder updates: a Gio file monitor per open folder.

Events are gathered for a moment and sent as one "changed" event per folder:
for each name that was touched, the item as it is now (upsert) or a delete.
Looking at the file at flush time (instead of trusting the event kind) makes
renames, quick create + delete and editors' save-by-rename come out right.
More than RESCAN_AT names at once: a "rescan" (the UI lists the folder again).

Servers through GVfs (smb, sftp, …) and network file systems have no change
notification (or only for what this computer does). So two more sources:
- poke(names): an operation of ours names what it touched (Server.touch);
- such a folder is looked at every POLL_S seconds (its own mtime, in the pool:
  a dead server must not hold the loop): moved without us → "rescan".
"""
import os

from gi.repository import Gio, GLib

from . import listing
from .proto import send

FLUSH_MS = 150
RESCAN_AT = 1000
POLL_S = 4


class Watch:
    def __init__(self, wid, folder, on_gone, remote=False, pool=None):
        self.wid, self.folder, self.on_gone = wid, folder, on_gone
        self.pool = pool
        self.dir = Gio.File.new_for_path(folder)
        self.names = set()
        self.timer = 0
        self.rescan = False
        self.closed = False
        try:
            self.monitor = self.dir.monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, None)
        except GLib.Error:
            self.monitor = None           # (GVfs: "Operation not supported")
        if self.monitor is not None:
            self.monitor.set_rate_limit(FLUSH_MS)
            self.monitor.connect("changed", self._on_changed)
        # no notification, or only a local one: also look at the folder now and then
        self.polled = pool is not None and (remote or self.monitor is None)
        self.remote = self.polled
        self.stamp = None                 # the folder's mtime as last seen
        self.poll_timer = 0
        self.polling = False
        if self.polled:
            self.pool.submit(self._look, True)
            self.poll_timer = GLib.timeout_add_seconds(POLL_S, self._poll)

    def _on_changed(self, _monitor, f, other, event):
        E = Gio.FileMonitorEvent
        if f.equal(self.dir):
            if event in (E.DELETED, E.MOVED_OUT, E.UNMOUNTED, E.RENAMED):
                self.close()
                self.on_gone(self.wid)
                send({"event": "gone", "watch": self.wid})
            return
        for g in (f, other):
            if g is not None:
                parent = g.get_parent()
                if parent is not None and parent.equal(self.dir):
                    self.names.add(g.get_basename())
        self._schedule()

    def _schedule(self):
        if len(self.names) > RESCAN_AT:
            self.rescan = True
            self.names.clear()
        if not self.timer:
            self.timer = GLib.timeout_add(FLUSH_MS, self._flush)

    def poke(self, names):
        """these names changed (an operation of ours said so): looked at like monitor events"""
        if self.closed:
            return
        self.names.update(names)
        self.stamp = None                 # the folder's mtime moves because of us: no rescan for it
        self._schedule()

    def _flush(self):
        self.timer = 0
        if self.rescan:
            self.rescan = False
            send({"event": "changed", "watch": self.wid, "rescan": True})
            return False
        names, self.names = self.names, set()
        if not names:
            return False
        if self.remote:
            self.pool.submit(self._gather, names)     # a round trip per name: not on the loop
        else:
            self._gather(names)
        return False

    def _gather(self, names):
        try:
            hidden = listing.read_hidden(self.folder)
            changes = []
            for n in sorted(names):
                try:
                    lst = os.lstat(os.path.join(self.folder, n))
                except OSError:
                    changes.append({"kind": "delete", "name": n})
                    continue
                changes.append({"kind": "upsert", "item": listing.make_item(self.folder, n, lst, hidden)})
            if self.polled:
                self._look(True)          # that was us: not a change from elsewhere
            if not self.closed:
                send({"event": "changed", "watch": self.wid, "changes": changes})
        except Exception:  # noqa: BLE001  (a worker: nothing to tell, the next change tries again)
            pass

    # ── polling (worker threads) ──

    def _poll(self):
        if self.closed:
            self.poll_timer = 0
            return False
        if not self.polling and not self.timer:
            self.polling = True
            self.pool.submit(self._look, False)
        return True

    def _look(self, quiet):
        try:
            try:
                stamp = os.stat(self.folder).st_mtime_ns
            except OSError:
                return                    # unreachable right now: the listing's own error shows it
            moved = self.stamp is not None and stamp != self.stamp
            self.stamp = stamp
            if moved and not quiet and not self.closed:
                send({"event": "changed", "watch": self.wid, "rescan": True})
        finally:
            if not quiet:
                self.polling = False

    def close(self):
        self.closed = True
        if self.timer:
            GLib.source_remove(self.timer)
            self.timer = 0
        if self.poll_timer:
            GLib.source_remove(self.poll_timer)
            self.poll_timer = 0
        if self.monitor:
            self.monitor.cancel()
            self.monitor = None
