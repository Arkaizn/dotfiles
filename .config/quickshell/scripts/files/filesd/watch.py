"""Live folder updates: a Gio file monitor per open folder.

Events are gathered for a moment and sent as one "changed" event per folder:
for each name that was touched, the item as it is now (upsert) or a delete.
Looking at the file at flush time (instead of trusting the event kind) makes
renames, quick create + delete and editors' save-by-rename come out right.
More than RESCAN_AT names at once: a "rescan" (the UI lists the folder again).
"""
import os

from gi.repository import Gio, GLib

from . import listing
from .proto import send

FLUSH_MS = 150
RESCAN_AT = 1000


class Watch:
    def __init__(self, wid, folder, on_gone):
        self.wid, self.folder, self.on_gone = wid, folder, on_gone
        self.dir = Gio.File.new_for_path(folder)
        self.names = set()
        self.timer = 0
        self.rescan = False
        self.monitor = self.dir.monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, None)
        self.monitor.set_rate_limit(FLUSH_MS)
        self.monitor.connect("changed", self._on_changed)

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
        if len(self.names) > RESCAN_AT:
            self.rescan = True
            self.names.clear()
        if not self.timer:
            self.timer = GLib.timeout_add(FLUSH_MS, self._flush)

    def _flush(self):
        self.timer = 0
        if self.rescan:
            self.rescan = False
            send({"event": "changed", "watch": self.wid, "rescan": True})
            return False
        names, self.names = self.names, set()
        if not names:
            return False
        hidden = listing.read_hidden(self.folder)
        changes = []
        for n in sorted(names):
            try:
                lst = os.lstat(os.path.join(self.folder, n))
            except OSError:
                changes.append({"kind": "delete", "name": n})
                continue
            changes.append({"kind": "upsert", "item": listing.make_item(self.folder, n, lst, hidden)})
        send({"event": "changed", "watch": self.wid, "changes": changes})
        return False

    def close(self):
        if self.timer:
            GLib.source_remove(self.timer)
            self.timer = 0
        if self.monitor:
            self.monitor.cancel()
            self.monitor = None
