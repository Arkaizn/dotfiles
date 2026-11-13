"""The event loop and the ops (protocol: ../filesd.py).

One GLib main loop: stdin through an fd watch, Gio's monitors and async calls
on the loop, blocking work (listings, statvfs) in a small thread pool whose
workers answer directly (proto.send is thread-safe). One slow folder can
never hold up the others or a ping. Every pool request has a cancel flag.
"""
import concurrent.futures
import json
import os
import shutil
import stat
import subprocess
import threading
import time

import gi
gi.require_version("Gio", "2.0")
gi.require_version("GLibUnix", "2.0")
from gi.repository import Gio, GLib, GLibUnix  # noqa: E402

from . import archives, creds, devices, info, listing, ops, places, portal, search, views, watch  # noqa: E402
from . import thumbs  # noqa: E402
from .proto import VERSION, Fail, choice_arg, error_reply, from_os, path_arg, send  # noqa: E402

BATCH = 2000                  # items per "batch" line
PARTIAL_AFTER = 0.3           # s: a listing still running then shows what it has …
PARTIAL_EVERY = 0.25          # s: … and what's new this often
MAX_LINE = 4 << 20            # a request longer than this is dropped
SORTS = ("name", "size", "mtime", "type")
DIRS_MAX = 5000               # subfolder names one "dirs" answer holds
# our own variables: apps we start must not inherit them (a Quickshell started from
# a launched terminal would run in "remote" settings mode)
PRIVATE_ENV = ("QS_SETTINGS_REMOTE", "QS_NO_RELOAD_POPUP")
MAX_PATHS = 100000            # paths in one operation
SAVE_MAX = 50 << 20           # bytes a drop from another app may bring
HERE = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))     # scripts/files


class Server:
    def __init__(self):
        self.loop = GLib.MainLoop()
        self.pool = concurrent.futures.ThreadPoolExecutor(max_workers=4, thread_name_prefix="filesd")
        # thumbnails wait in their own (a folder of photos must not hold up listings)
        self.thumb_pool = concurrent.futures.ThreadPoolExecutor(max_workers=3, thread_name_prefix="filesd-thumb")
        self.cancels = {}         # request id → threading.Event
        self.jobs = {}            # request id → ops.Job (copy, trash, delete …: threads of their own)
        self.clip = None          # the fmclip.py owning the clipboard, if it's ours
        self.mount_asks = {}      # request id → devices.Asker (a mount / connect waiting for an answer)
        self.fm1 = 0              # bus name id while we own org.freedesktop.FileManager1
        self.watches = {}         # watch id → watch.Watch
        self.next_watch = 1
        self.buf = b""
        self.volumes = Gio.VolumeMonitor.get()
        self.place_watcher = places.Watcher(self.volumes)
        self.ops = {
            "ping": self.op_ping, "list": self.op_list, "watch": self.op_watch, "unwatch": self.op_unwatch,
            "info": self.op_info, "free": self.op_free, "places": self.op_places, "launch": self.op_launch,
            "cancel": self.op_cancel, "dirs": self.op_dirs,
            "copy": self.op_copy, "relocate": self.op_relocate, "trash": self.op_trash, "restore": self.op_restore,
            "delete": self.op_delete, "rename": self.op_rename, "mkdir": self.op_mkdir, "newfile": self.op_newfile,
            "templates": self.op_templates, "answer": self.op_answer, "pause": self.op_pause,
            "clipSet": self.op_clip_set, "clipGet": self.op_clip_get,
            "run": self.op_run, "desktop": self.op_desktop, "trust": self.op_trust, "launchDesktop": self.op_launch_desktop,
            "save": self.op_save, "openUri": self.op_open_uri,
            "search": self.op_search, "thumb": self.op_thumb, "preview": self.op_preview, "props": self.op_props,
            "du": self.op_du, "counts": self.op_counts, "apps": self.op_apps, "launchWith": self.op_launch_with,
            "setDefault": self.op_set_default, "chmod": self.op_chmod, "chown": self.op_chown,
            "mount": self.op_mount, "unmount": self.op_unmount, "connect": self.op_connect, "network": self.op_network,
            "mountImage": self.op_mount_image, "compress": self.op_compress, "extract": self.op_extract,
            "trashList": self.op_trash_list, "trashRestore": self.op_trash_restore, "trashDelete": self.op_trash_delete,
            "trashEmpty": self.op_trash_empty, "recent": self.op_recent, "addRecent": self.op_add_recent,
            "scripts": self.op_scripts, "runScript": self.op_run_script,
            "bookmark": self.op_bookmark, "fileManager1": self.op_fm1,
            "logins": self.op_logins,
            "fileChooser": self.op_chooser, "chooserAck": self.op_chooser_ack, "chooserDone": self.op_chooser_done,
        }
        self.chooser = portal.Chooser(os.path.join(HERE, "files.sh"))

    # ── Plumbing ──────────────────────────────────────────────────────────────

    def run(self):
        for k in PRIVATE_ENV:
            os.environ.pop(k, None)
        GLibUnix.fd_add_full(GLib.PRIORITY_DEFAULT, 0, GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR, self.on_stdin)
        send({"event": "ready", "pid": os.getpid(), "version": VERSION})
        self.loop.run()
        for w in self.watches.values():
            w.close()
        for job in list(self.jobs.values()):
            job.cancel()
        self.pool.shutdown(wait=False, cancel_futures=True)
        self.thumb_pool.shutdown(wait=False, cancel_futures=True)

    def on_stdin(self, fd, cond, *_):
        try:
            data = os.read(fd, 65536)
        except OSError:
            data = b""
        if not data:              # the file manager went away
            self.loop.quit()
            return False
        self.buf += data
        while b"\n" in self.buf:
            line, self.buf = self.buf.split(b"\n", 1)
            if line.strip():
                self.handle(line)
        if len(self.buf) > MAX_LINE:
            self.buf = b""
            send({"id": None, "type": "error", "error": "request too long", "code": "invalid"})
        return True

    def handle(self, line):
        rid = None
        try:
            try:
                req = json.loads(line)
            except ValueError:
                raise Fail("not JSON", "invalid")
            if not isinstance(req, dict):
                raise Fail("a request is an object", "invalid")
            rid = req.get("id")
            if not isinstance(rid, int):
                raise Fail("a request needs an integer id", "invalid")
            args = req.get("args") or {}
            if not isinstance(args, dict):
                raise Fail("args must be an object", "invalid")
            op = self.ops.get(req.get("op"))
            if op is None:
                raise Fail("unknown op", "invalid")
            op(rid, args)
        except Exception as e:  # noqa: BLE001  (one bad request must not end the backend)
            send(error_reply(rid, e))

    def in_pool(self, rid, work, touched=None):
        """run work(cancelled) in a worker; its return value is the "done" reply.
        touched(res | None) → the paths it changed (see touch)"""
        flag = threading.Event()
        self.cancels[rid] = flag

        def job():
            res = None
            try:
                if flag.is_set():
                    raise Fail("cancelled", "cancelled")
                res = work(flag.is_set)
                if flag.is_set():
                    raise Fail("cancelled", "cancelled")
                self._touched(touched, res)
                send({"id": rid, **(res or {}), "type": "done"})        # last: a result can't replace it
            except Exception as e:  # noqa: BLE001
                self._touched(touched, None)
                send(error_reply(rid, e))
            finally:
                self.cancels.pop(rid, None)
        self.pool.submit(job)

    def _touched(self, touched, res):
        if touched is None:
            return
        try:
            self.touch(touched(res))
        except Exception:  # noqa: BLE001  (only a refresh hint)
            pass

    def touch(self, paths):
        """an operation changed these paths: the open folders they are in look at them now.
        Local folders hear it from their monitor anyway; servers through GVfs and network
        drives don't (a deleted file stayed in the view until F5). Any thread."""
        by = {}
        for p in paths or ():
            if isinstance(p, str) and p.startswith("/") and p != "/":
                p = p.rstrip("/")
                by.setdefault(os.path.dirname(p), set()).add(os.path.basename(p))
        if not by:
            return

        def go():
            for w in list(self.watches.values()):
                names = by.get(w.folder)
                if names:
                    w.poke(names)
            return False
        GLib.idle_add(go)

    def in_thread(self, rid, work, touched=None):
        """a long operation: a thread of its own, an ops.Job for progress / pause / answers.
        touched(res | None) → the paths it changed (also when it failed half way)"""
        job = ops.Job(rid)
        self.jobs[rid] = job

        def run():
            try:
                res = work(job) or {}
                self._touched(touched, res)
                send({"id": rid, **res, "type": "done"})
            except Exception as e:  # noqa: BLE001
                self._touched(touched, None)
                send(error_reply(rid, e))
            finally:
                self.jobs.pop(rid, None)
        threading.Thread(target=run, name="filesd-job", daemon=True).start()

    def fs_of(self, path):
        return places.fs_type(path, places.fs_types())

    # ── Ops ───────────────────────────────────────────────────────────────────

    def op_ping(self, rid, args):
        send({"id": rid, "type": "done", "pong": True, "t": time.time()})

    def op_list(self, rid, args):
        path = path_arg(args)
        by = choice_arg(args, "sort", SORTS, "name")
        show_hidden = args.get("hidden") is True
        reverse = args.get("reverse") is True
        dirs_first = args.get("dirsFirst") is not False

        def work(cancelled):
            fs = self.fs_of(path)
            # a folder that takes a while (big, or over the network) shows while it's read:
            # after PARTIAL_AFTER, what's new goes out every PARTIAL_EVERY ("partial": unsorted);
            # the sorted whole follows ("reset" on its first batch) and replaces it
            t0 = time.monotonic()
            sent = [0, t0]

            def progress(out):
                now = time.monotonic()
                if now - t0 < PARTIAL_AFTER or now - sent[1] < PARTIAL_EVERY:
                    return
                new = [r for r in out[sent[0]:] if show_hidden or not r["hidden"]]
                sent[0], sent[1] = len(out), now
                if new:
                    send({"id": rid, "type": "batch", "partial": True, "items": new})
            items = listing.scan(path, cancelled, fs in listing.REMOTE_FS, progress)
            if items is None:
                raise Fail("cancelled", "cancelled")
            hidden = sum(1 for r in items if r["hidden"])
            if not show_hidden:
                items = [r for r in items if not r["hidden"]]
            listing.sort_items(items, by, reverse, dirs_first)
            streamed = sent[0] > 0
            for i in range(0, len(items), BATCH):
                if cancelled():
                    raise Fail("cancelled", "cancelled")
                b = {"id": rid, "type": "batch", "items": items[i:i + BATCH]}
                if streamed and i == 0:
                    b["reset"] = True
                send(b)
            if streamed and not items:
                send({"id": rid, "type": "batch", "reset": True, "items": []})
            # (a server's mode bits say little — ACLs decide there: writing is tried, and the
            # server's own answer shown, instead of refusing up front)
            return {"count": len(items), "hiddenCount": hidden, "path": path,
                    "canWrite": fs in listing.REMOTE_FS or os.access(path, os.W_OK), "fs": fs}
        self.in_pool(rid, work)

    def op_dirs(self, rid, args):
        path = path_arg(args)

        def work(cancelled):
            names, more = listing.dirs(path, cancelled, DIRS_MAX)
            if names is None:
                raise Fail("cancelled", "cancelled")
            return {"path": path, "names": names, "more": more}
        self.in_pool(rid, work)

    def op_watch(self, rid, args):
        path = path_arg(args)
        if not os.path.isdir(path):
            raise Fail("This isn't a folder", "notdir")
        wid = self.next_watch
        self.next_watch += 1
        # (a server through GVfs / a network drive has no change notification: such a watch
        # polls, and our own operations tell it what they touched — touch())
        self.watches[wid] = watch.Watch(wid, path, lambda w: self.watches.pop(w, None),
                                        self.fs_of(path) in listing.REMOTE_FS, self.pool)
        send({"id": rid, "type": "done", "watch": wid})

    def op_unwatch(self, rid, args):
        w = self.watches.pop(args.get("watch"), None)
        if w:
            w.close()
        send({"id": rid, "type": "done", "found": w is not None})

    def op_info(self, rid, args):
        paths = args.get("paths")
        if not isinstance(paths, list) or len(paths) > 1000:
            raise Fail("paths: a list of up to 1000 paths", "invalid")
        checked = [path_arg({"path": p}) for p in paths]
        self.in_pool(rid, lambda cancelled: {"items": [listing.item_for(p) for p in checked]})

    def op_free(self, rid, args):
        path = path_arg(args)

        def work(cancelled):
            if not places.local_fs(path, places.fs_types()):
                raise Fail("free space isn't checked on network drives", "unsupported")
            return places.space(path)
        self.in_pool(rid, work)

    def op_places(self, rid, args):
        result = places.collect(self.volumes)
        result["volumes"] = devices.volumes(self.volumes)
        self.in_pool(rid, lambda cancelled: places.add_space(result))

    def op_launch(self, rid, args):
        path = path_arg(args)
        if os.path.isdir(path):
            raise Fail("folders are opened in the file manager", "invalid")
        if not os.path.lexists(path):
            raise Fail("This doesn't exist (any more)", "missing")
        ctx = Gio.AppLaunchContext()
        for k in PRIVATE_ENV:
            ctx.unsetenv(k)

        # the app that will open it: its window names, so the UI can bring that window up
        mime = (listing.item_for(path) or {}).get("type") or ""
        keys = info.app_keys(Gio.AppInfo.get_default_for_type(mime, False)) if mime else []

        def done(_src, res):
            try:
                Gio.AppInfo.launch_default_for_uri_finish(res)
                send({"id": rid, "type": "done", "app": keys})
            except GLib.Error as e:
                send({"id": rid, "type": "error", "code": "unsupported",
                      "error": e.message.split("\n")[0] or "No app opens this kind of file"})
        # the default app for its type: a script opens in the editor, nothing is run
        Gio.AppInfo.launch_default_for_uri_async(Gio.File.new_for_path(path).get_uri(), ctx, None, done)

    def op_cancel(self, rid, args):
        flag = self.cancels.get(args.get("target"))
        if flag:
            flag.set()
        job = self.jobs.get(args.get("target"))
        if job:
            job.cancel()
        asker = self.mount_asks.get(args.get("target"))
        if asker:
            asker.give({"action": "cancel"})
        send({"id": rid, "type": "done", "found": flag is not None or job is not None or asker is not None})

    # ── Operations (protocol: ops.py) ─────────────────────────────────────────

    @staticmethod
    def paths_arg(args, key="paths"):
        ps = args.get(key)
        if not isinstance(ps, list) or not ps or len(ps) > MAX_PATHS:
            raise Fail(key + ": a list of 1 to %d paths" % MAX_PATHS, "invalid")
        return [path_arg({"path": p}) for p in ps]

    def op_copy(self, rid, args):
        sources = self.paths_arg(args, "sources")
        dest = path_arg(args, "dest")
        mode = choice_arg(args, "mode", ("copy", "move", "link", "auto"), "copy")
        if mode == "auto":
            # a drag without keys, like Nautilus: a move on the same drive, else a copy
            mode = "move" if all(ops.same_dev(s, dest) for s in sources) else "copy"

        pairs = []

        def work(job):
            pairs.extend(ops.plan(sources, dest, mode))
            res = ops.run_transfer(job, pairs, mode)
            res["mode"] = mode
            return res
        self.in_thread(rid, work, lambda res: sources + [d for _, d in pairs] + [m["dst"] for m in (res or {}).get("made", [])])

    def op_save(self, rid, args):
        """something dropped from another app that isn't a file (a browser's image,
        text, a link): a new file, never over an existing one"""
        folder = path_arg(args, "dir")
        name = args.get("name")
        text, b64 = args.get("text"), args.get("base64")

        def work(cancelled):
            import base64
            if isinstance(b64, str):
                if len(b64) > SAVE_MAX * 4 // 3 + 8:
                    raise Fail("That's too big to drop here", "invalid")
                try:
                    data = base64.b64decode(b64, validate=True)
                except ValueError:
                    raise Fail("The dropped data isn't readable", "invalid")
            elif isinstance(text, str):
                data = text.encode("utf-8", "surrogateescape")
            else:
                raise Fail("nothing to save", "invalid")
            if len(data) > SAVE_MAX:
                raise Fail("That's too big to drop here", "invalid")
            n = name if isinstance(name, str) and not ops.name_error(name) else "Saved from web"
            if os.path.lexists(os.path.join(folder, n)):
                n = ops.free_name(folder, n)
            res = ops.newfile(folder, n, None, self.fs_of(folder))
            with open(res["path"], "wb") as f:
                f.write(data)
            return res
        self.in_pool(rid, work, lambda res: [res["path"]] if res else [])

    def op_open_uri(self, rid, args):
        u = args.get("uri")
        if not isinstance(u, str) or not u.split(":", 1)[0].lower() in ("http", "https", "mailto") or len(u) > 8192:
            raise Fail("Only web and mail links open from here", "invalid")
        ctx = Gio.AppLaunchContext()
        for k in PRIVATE_ENV:
            ctx.unsetenv(k)
        try:
            Gio.AppInfo.launch_default_for_uri(u, ctx)
        except GLib.Error as e:
            raise Fail(e.message.split("\n")[0], "unsupported")
        send({"id": rid, "type": "done"})

    def op_relocate(self, rid, args):
        pairs = args.get("pairs")
        if not isinstance(pairs, list) or not pairs or len(pairs) > MAX_PATHS:
            raise Fail("pairs: a list of {from, to}", "invalid")
        checked = [(path_arg(p, "from"), path_arg(p, "to")) for p in pairs if isinstance(p, dict)]
        self.in_thread(rid, lambda job: ops.run_transfer(job, checked, "move", explicit=True),
                       lambda res: [p for pair in checked for p in pair])

    def op_trash(self, rid, args):
        paths = self.paths_arg(args)
        self.in_thread(rid, lambda job: ops.run_trash(job, paths, Gio), lambda res: paths)

    def op_restore(self, rid, args):
        paths = self.paths_arg(args)
        self.in_thread(rid, lambda job: ops.run_restore(job, paths), lambda res: paths + (res or {}).get("restored", []))

    def op_delete(self, rid, args):
        paths = self.paths_arg(args)
        if "/" in paths or os.path.expanduser("~") in paths:
            raise Fail("That can't be deleted from here", "invalid")
        self.in_thread(rid, lambda job: ops.run_delete(job, paths), lambda res: paths)

    def op_rename(self, rid, args):
        path = path_arg(args)
        name = args.get("name")
        self.in_pool(rid, lambda c: ops.rename(path, name, self.fs_of(os.path.dirname(path))),
                     lambda res: [path, res["path"]] if res else [path])

    def op_mkdir(self, rid, args):
        folder = path_arg(args, "dir")
        name = args.get("name")
        self.in_pool(rid, lambda c: ops.mkdir(folder, name, self.fs_of(folder)), lambda res: [res["path"]] if res else [])

    def op_newfile(self, rid, args):
        folder = path_arg(args, "dir")
        name = args.get("name")
        template = path_arg(args, "template") if args.get("template") else None
        self.in_pool(rid, lambda c: ops.newfile(folder, name, template, self.fs_of(folder)), lambda res: [res["path"]] if res else [])

    def op_templates(self, rid, args):
        self.in_pool(rid, lambda c: ops.templates(GLib))

    def op_answer(self, rid, args):
        target = args.get("target")
        job, asker = self.jobs.get(target), self.mount_asks.get(target)
        a = {"action": choice_arg(args, "action", ("replace", "skip", "rename", "merge", "retry", "delete", "ok", "cancel"), "cancel"),
             "all": args.get("all") is True}
        for k in ("name", "user", "domain", "password"):
            if isinstance(args.get(k), str) and len(args[k]) <= 4096:
                a[k] = args[k]
        for k in ("anonymous", "remember"):
            a[k] = args.get(k) is True
        if isinstance(args.get("choice"), int):
            a["choice"] = args["choice"]
        if job:
            job.give(a)
        if asker:
            cred = args.get("cred")
            if isinstance(cred, str) and a["action"] == "ok":
                # a saved login picked in the password dialog: its password is read here
                self._login(cred, a["remember"])(asker)
            else:
                asker.give(a)
        send({"id": rid, "type": "done", "found": job is not None or asker is not None})

    def op_pause(self, rid, args):
        job = self.jobs.get(args.get("target"))
        if job:
            job.pause(args.get("paused") is not False)
        send({"id": rid, "type": "done", "found": job is not None})

    # ── Knowing: search, thumbnails, preview, properties, apps ────────────────

    def op_search(self, rid, args):
        path = path_arg(args)
        query = args.get("query")
        if not isinstance(query, str) or len(query) > 500:
            raise Fail("query: text", "invalid")
        depth = args.get("depth", 64)
        opts = {"depth": depth if isinstance(depth, int) and 0 <= depth <= 64 else 64,
                "hidden": args.get("hidden") is True,
                "kinds": [k for k in (args.get("kinds") or []) if k in search.KINDS],
                "since": args.get("since") if isinstance(args.get("since"), (int, float)) else 0}

        if args.get("everywhere") is True:
            # from /: the whole computer, without pseudo / network file systems (/proc, mounted servers …)
            path = "/"
            types = places.fs_types()
            opts["skip"] = search.SKIP_ROOTS | {mp for mp, t in types.items()
                                                if mp != "/" and (t in search.PSEUDO_FS or t in listing.REMOTE_FS)}

        def work(cancelled):
            res = search.run(path, query, opts, cancelled, lambda items: send({"id": rid, "type": "batch", "items": items}))
            if res is None:
                raise Fail("cancelled", "cancelled")
            return res
        self.in_pool(rid, work)

    def op_thumb(self, rid, args):
        path = path_arg(args)
        mime = args.get("type") if isinstance(args.get("type"), str) else ""
        mtime = args.get("mtime") if isinstance(args.get("mtime"), (int, float)) else 0
        large = args.get("large") is True
        flag = threading.Event()
        self.cancels[rid] = flag

        def job():
            try:
                t = None if flag.is_set() else thumbs.thumbnail(path, mime, int(mtime), large)
                send({"id": rid, "type": "done", "thumb": t or ""})
            except Exception as e:  # noqa: BLE001
                send(error_reply(rid, e))
            finally:
                self.cancels.pop(rid, None)
        self.thumb_pool.submit(job)

    def op_preview(self, rid, args):
        path = path_arg(args)
        mime = args.get("type") if isinstance(args.get("type"), str) else ""
        self.in_pool(rid, lambda c: info.preview(path, mime or listing.item_for(path)["type"], Gio))

    def op_props(self, rid, args):
        path = path_arg(args)

        def work(cancelled):
            from gi.repository import GdkPixbuf
            res = info.props(path, listing.item_for(path), GdkPixbuf)
            if os.path.isdir(path) or not res.get("dir"):
                try:
                    res.update(places.space(path if os.path.isdir(path) else os.path.dirname(path)))
                except OSError:
                    pass
            return res
        self.in_pool(rid, work)

    def op_du(self, rid, args):
        paths = self.paths_arg(args)
        self.in_thread(rid, lambda job: info.du(job, paths))

    def op_counts(self, rid, args):
        folder = path_arg(args, "dir")
        names = args.get("names")
        if not isinstance(names, list) or len(names) > 5000 or not all(isinstance(n, str) and "/" not in n for n in names):
            raise Fail("names: up to 5000 names", "invalid")
        hidden = args.get("hidden") is True
        self.in_pool(rid, lambda c: info.counts(folder, names, hidden, c))

    def op_apps(self, rid, args):
        if args.get("all") is True:
            send({"id": rid, **info.all_apps(Gio), "type": "done"})
            return
        mime = args.get("type")
        if not isinstance(mime, str) or not mime or len(mime) > 200:
            raise Fail("type: a content type", "invalid")
        send({"id": rid, "type": "done", **info.apps_for(mime, Gio)})

    def op_launch_with(self, rid, args):
        paths = self.paths_arg(args)
        app = args.get("app")
        if not isinstance(app, str) or not app.endswith(".desktop") or "/" in app:
            raise Fail("app: a .desktop id", "invalid")
        ctx = Gio.AppLaunchContext()
        for k in PRIVATE_ENV:
            ctx.unsetenv(k)
        try:
            keys = info.launch_with(paths, app, Gio, ctx)
        except GLib.Error as e:
            raise Fail(e.message.split("\n")[0], "unsupported")
        send({"id": rid, "type": "done", "app": keys})

    def op_set_default(self, rid, args):
        mime, app = args.get("type"), args.get("app")
        if not isinstance(mime, str) or not mime or "/" not in mime or not isinstance(app, str) or not app.endswith(".desktop") or "/" in app:
            raise Fail("type and app", "invalid")
        try:
            send({"id": rid, "type": "done", **info.set_default(mime, app, Gio)})
        except GLib.Error as e:
            raise Fail(e.message.split("\n")[0], "unsupported")

    def op_chmod(self, rid, args):
        path = path_arg(args)
        mode = args.get("mode")
        if not isinstance(mode, int) or not 0 <= mode <= 0o7777:
            raise Fail("mode: 0…0o7777", "invalid")
        try:
            send({"id": rid, "type": "done", **info.chmod(path, mode)})
        except OSError as e:
            raise from_os(e)

    def op_chown(self, rid, args):
        path = path_arg(args)
        owner, group = args.get("owner"), args.get("group")
        rec = args.get("recursive") is True
        self.in_thread(rid, lambda job: info.chown(path, owner, group, rec))

    # ── Reaching: drives, servers, network, archives, views ───────────────────

    def _finish(self, rid):
        def done(res, err=None):
            send(error_reply(rid, err) if err else {"id": rid, **(res or {}), "type": "done"})
        return done

    def op_mount(self, rid, args):
        vid = args.get("volume")
        if not isinstance(vid, str) or not vid:
            raise Fail("volume: an id from places", "invalid")
        devices.mount_volume(self.volumes, vid, rid, self.mount_asks, self._finish(rid))

    def op_unmount(self, rid, args):
        uri = args.get("uri")
        if not isinstance(uri, str) or not uri:
            raise Fail("uri: a mount's", "invalid")
        devices.unmount(self.volumes, uri, args.get("eject") is True, rid, self.mount_asks, self._finish(rid))

    def op_connect(self, rid, args):
        uri = args.get("uri")
        if not isinstance(uri, str):
            raise Fail("uri: a server address", "invalid")
        cred = args.get("cred")
        login = self._login(cred, args.get("remember") is True) if isinstance(cred, str) else None
        devices.connect(uri.strip(), rid, self.mount_asks, self._finish(rid), login)

    def _login(self, cred, remember):
        """answers a mount's password question with a saved login (keyring item `cred`): read in
        the pool (the keyring may prompt to unlock), given on the loop; on a failure the UI asks"""
        def answer(asker):
            def work():
                try:
                    user, domain, password = creds.secret_of(cred)
                except Exception as e:  # noqa: BLE001
                    why = str(e) if isinstance(e, Fail) else "The saved login couldn't be read"
                    GLib.idle_add(lambda: asker.ask_again(why) and False)
                    return
                a = {"action": "ok", "user": user, "domain": domain, "password": password, "remember": remember}
                GLib.idle_add(lambda: asker.give(a) and False)
            self.pool.submit(work)
        return answer

    def op_logins(self, rid, args):
        self.in_pool(rid, lambda c: {"logins": creds.logins()})

    # ── Other apps' Open / Save dialogs (portal.py) ───────────────────────────

    def op_chooser(self, rid, args):
        send({"id": rid, "type": "done", **self.chooser.set(args.get("on") is True)})

    def op_chooser_ack(self, rid, args):
        send({"id": rid, "type": "done", "found": self.chooser.ack(args.get("chooser"))})

    def op_chooser_done(self, rid, args):
        paths = args.get("paths")
        if not isinstance(paths, list) or len(paths) > 10000:
            raise Fail("paths: a list", "invalid")
        checked = [path_arg({"path": p}) for p in paths]
        choices = args.get("choices") if isinstance(args.get("choices"), dict) else {}
        flt = args.get("filter") if isinstance(args.get("filter"), int) else -1
        send({"id": rid, "type": "done",
              "found": self.chooser.done(args.get("chooser"), args.get("ok") is True, checked, choices, flt)})

    def op_network(self, rid, args):
        devices.network(self._finish(rid))

    def op_mount_image(self, rid, args):
        path = path_arg(args)
        self.in_pool(rid, lambda c: devices.mount_image(path))

    def op_compress(self, rid, args):
        paths = self.paths_arg(args)
        dest = path_arg(args, "dest")
        name = args.get("name")
        fmt = choice_arg(args, "format", archives.FORMATS, "zip")
        password = args.get("password") if isinstance(args.get("password"), str) and args.get("password") else None
        self.in_thread(rid, lambda job: archives.compress(job, paths, dest, name, fmt, password),
                       lambda res: [res["path"]] if res and res.get("path") else [])

    def op_extract(self, rid, args):
        path = path_arg(args)
        dest = path_arg(args, "dest")
        self.in_thread(rid, lambda job: archives.extract(job, path, dest),
                       lambda res: [res["path"]] if res and res.get("path") else [])

    def _entries(self, args):
        es = args.get("items")
        if not isinstance(es, list) or not es or len(es) > MAX_PATHS:
            raise Fail("items: [{file, info, orig}]", "invalid")
        out = []
        for e in es:
            if not isinstance(e, dict):
                continue
            out.append({"file": path_arg(e, "file"), "info": path_arg(e, "info"),
                        "orig": e["orig"] if isinstance(e.get("orig"), str) else ""})
        return out

    def op_trash_list(self, rid, args):
        send({"id": rid, **views.trash_list(Gio), "type": "done"})

    def op_trash_restore(self, rid, args):
        es = self._entries(args)
        self.in_thread(rid, lambda job: views.trash_restore(job, es, Gio), lambda res: [e["orig"] for e in es])

    def op_trash_delete(self, rid, args):
        es = self._entries(args)
        self.in_thread(rid, lambda job: views.trash_delete(job, es, Gio))

    def op_trash_empty(self, rid, args):
        self.in_thread(rid, lambda job: views.trash_empty(job, Gio))

    def op_recent(self, rid, args):
        self.in_pool(rid, lambda c: views.recent())

    def op_add_recent(self, rid, args):
        path = path_arg(args)
        mime = args.get("type") if isinstance(args.get("type"), str) else ""
        self.in_pool(rid, lambda c: views.add_recent(path, mime))

    def op_scripts(self, rid, args):
        self.in_pool(rid, lambda c: views.scripts())

    def op_run_script(self, rid, args):
        script = path_arg(args, "script")
        paths = self.paths_arg(args)
        cwd = path_arg(args, "cwd")
        send({"id": rid, **views.run_script(script, paths, cwd, self._env()), "type": "done"})

    # ── Bookmarks (GTK's file: GTK file dialogs see the same) ─────────────────

    def op_bookmark(self, rid, args):
        action = choice_arg(args, "action", ("add", "remove", "rename", "move", "order"), "add")
        if action == "order":
            uris = args.get("uris")
            if not isinstance(uris, list) or len(uris) > 2000 or not all(isinstance(u, str) and u and "\n" not in u and " " not in u for u in uris):
                raise Fail("uris: the bookmarks' URIs", "invalid")
            res = places.bookmark_order(uris)
        elif action == "add":
            label = args.get("label") if isinstance(args.get("label"), str) else ""
            if "\n" in label or len(label) > 500:
                raise Fail("label: one line", "invalid")
            if isinstance(args.get("uri"), str):
                # a server (sftp://, smb://, …): kept as its address, a click connects
                res = places.bookmark_add(places.server_uri(args["uri"]), label)
            else:
                res = places.bookmark_add(places.uri_for_path(path_arg(args), ops.uri), label)
        else:
            uri = args.get("uri")
            if not isinstance(uri, str) or not uri or "\n" in uri or " " in uri:
                raise Fail("uri: a bookmark's", "invalid")
            if action == "remove":
                res = places.bookmark_remove(uri)
            elif action == "rename":
                label = args.get("label") if isinstance(args.get("label"), str) else ""
                if "\n" in label or len(label) > 500:
                    raise Fail("label: one line", "invalid")
                res = places.bookmark_rename(uri, label.strip())
            else:
                res = places.bookmark_move(uri, -1 if args.get("step") == -1 else 1)
        self.place_watcher.poke(reload_dirs=False)
        send({"id": rid, **res, "type": "done"})

    # ── org.freedesktop.FileManager1 ("Show in folder" from browsers, …) ─────
    # Owned only while the file manager says so (its setting); the calls become
    # events {"event": "fm1", "method": ShowFolders | ShowItems | ShowItemProperties, "uris": [...]}.

    FM1_XML = """<node><interface name="org.freedesktop.FileManager1">
      <method name="ShowFolders"><arg type="as" name="URIs" direction="in"/><arg type="s" name="StartupId" direction="in"/></method>
      <method name="ShowItems"><arg type="as" name="URIs" direction="in"/><arg type="s" name="StartupId" direction="in"/></method>
      <method name="ShowItemProperties"><arg type="as" name="URIs" direction="in"/><arg type="s" name="StartupId" direction="in"/></method>
    </interface></node>"""

    FM1_SERVICE = "org.freedesktop.FileManager1.service"
    FM1_MARK = "# quickshell files (Settings → Files → Show in folder from other apps)"

    def _fm1_file(self, on):
        """the D-Bus activation file: an app asking while the file manager isn't running starts
        it (files.sh --start); ours only — a file someone else wrote is left alone"""
        d = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "dbus-1", "services")
        f = os.path.join(d, self.FM1_SERVICE)
        try:
            with open(f, encoding="utf-8") as fh:
                current = fh.read()
        except OSError:
            current = None
        if current is not None and self.FM1_MARK not in current:
            return
        if on:
            os.makedirs(d, exist_ok=True)
            text = "%s\n[D-BUS Service]\nName=org.freedesktop.FileManager1\nExec=%s --start\n" % (
                self.FM1_MARK, os.path.join(HERE, "files.sh"))
            if current != text:
                tmp = f + ".qsfm-tmp"
                with open(tmp, "w", encoding="utf-8") as fh:
                    fh.write(text)
                os.replace(tmp, f)
        elif current is not None:
            os.unlink(f)

    def op_fm1(self, rid, args):
        on = args.get("on") is True
        try:
            self._fm1_file(on)
        except OSError:
            pass
        if on and not self.fm1:
            info = Gio.DBusNodeInfo.new_for_xml(self.FM1_XML).interfaces[0]

            def call(conn, sender, path, iface, method, params, invocation):
                uris = [u for u in params.unpack()[0] if isinstance(u, str)][:100]
                send({"event": "fm1", "method": method, "uris": uris})
                invocation.return_value(None)

            def acquired(conn, name):
                conn.register_object("/org/freedesktop/FileManager1", info, call)

            def got(conn, name):
                send({"event": "fm1", "method": "owned", "uris": []})

            def lost(conn, name):
                send({"event": "fm1", "method": "lost", "uris": []})
            self.fm1 = Gio.bus_own_name(Gio.BusType.SESSION, "org.freedesktop.FileManager1",
                                        Gio.BusNameOwnerFlags.NONE, acquired, got, lost)
        elif not on and self.fm1:
            Gio.bus_unown_name(self.fm1)
            self.fm1 = 0
        send({"id": rid, "type": "done", "on": bool(self.fm1)})

    # ── Clipboard (fmclip.py owns it, with the types other file managers read) ──

    def op_clip_set(self, rid, args):
        paths = self.paths_arg(args)
        cut = args.get("cut") is True
        uris = [ops.uri(p) for p in paths]
        text = "\n".join(paths)
        types = {
            "x-special/gnome-copied-files": ("cut" if cut else "copy") + "\n" + "\n".join(uris),
            "text/uri-list": "\r\n".join(uris) + "\r\n",
            "text/plain;charset=utf-8": text, "text/plain": text, "UTF8_STRING": text,
        }
        self._clip_stop()
        try:
            p = subprocess.Popen(["python3", "-I", os.path.join(HERE, "fmclip.py")], stdin=subprocess.PIPE,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, start_new_session=True)
            p.stdin.write(json.dumps({"types": types}, ensure_ascii=False).encode("utf-8", "surrogateescape"))
            p.stdin.close()
        except OSError as e:
            raise from_os(e)
        self.clip = p
        # it exits at once when it couldn't take the clipboard
        def check():
            try:
                code = p.wait(0.4)
            except subprocess.TimeoutExpired:
                send({"id": rid, "type": "done", "count": len(paths), "cut": cut})
                return
            err = (p.stderr.read() or b"").decode("utf-8", "replace").strip().split("\n")[-1]
            send({"id": rid, "type": "error", "code": "unsupported", "error": err or "Couldn't use the clipboard (%d)" % code})
        self.pool.submit(check)

    def _clip_stop(self):
        if self.clip and self.clip.poll() is None:
            try:
                self.clip.terminate()
            except OSError:
                pass
        self.clip = None

    def op_clip_get(self, rid, args):
        def work(cancelled):
            def paste(*a):
                r = subprocess.run(["wl-paste", "-n", *a], capture_output=True, timeout=3)
                if r.returncode != 0:
                    return None
                return r.stdout
            try:
                types = (paste("--list-types") or b"").decode("utf-8", "replace").split("\n")
            except (OSError, subprocess.TimeoutExpired):
                raise Fail("Couldn't read the clipboard (is wl-clipboard installed?)", "unsupported")
            types = [t.strip() for t in types if t.strip()]
            out = {"types": types[:50], "paths": [], "cut": False}
            raw = None
            if "x-special/gnome-copied-files" in types:
                raw = paste("-t", "x-special/gnome-copied-files")
                if raw is not None:
                    lines = raw.decode("utf-8", "surrogateescape").replace("\r", "").split("\n")
                    out["cut"] = lines[0].strip() == "cut"
                    uris = lines[1:]
            if raw is None and "text/uri-list" in types:
                raw = paste("-t", "text/uri-list")
                uris = (raw or b"").decode("utf-8", "surrogateescape").replace("\r", "").split("\n")
            if raw is not None:
                out["paths"] = [p for p in (ops.path_from_uri(u.strip()) for u in uris if u.strip() and not u.startswith("#")) if p][:MAX_PATHS]
            # we put it there ourselves and it's still ours: the same answer, and we know
            out["ours"] = self.clip is not None and self.clip.poll() is None
            return out
        self.in_pool(rid, work)

    # ── Running things (only on the user's explicit answer in the UI) ─────────

    def _env(self):
        env = dict(os.environ)
        for k in PRIVATE_ENV:
            env.pop(k, None)
        return env

    def op_run(self, rid, args):
        path = path_arg(args)
        terminal = args.get("terminal") is True
        try:
            st = os.stat(path)
        except OSError as e:
            raise from_os(e)
        if not stat.S_ISREG(st.st_mode) or not st.st_mode & 0o111:
            raise Fail("This isn't an executable file", "invalid")
        folder = os.path.dirname(path)
        if terminal:
            if not shutil.which("kitty"):
                raise Fail("kitty isn't installed", "unsupported")
            argv = ["kitty", "--hold", "--directory", folder, "--", path]
        else:
            argv = [path]
        try:
            subprocess.Popen(argv, cwd=folder, env=self._env(), stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
        except OSError as e:
            raise from_os(e)
        send({"id": rid, "type": "done"})

    @staticmethod
    def _desktop_trusted(path, st):
        # like GNOME: a launcher of your own, executable, writable by nobody else
        return st.st_uid == os.getuid() and bool(st.st_mode & 0o100) and not st.st_mode & 0o022

    def op_desktop(self, rid, args):
        path = path_arg(args)

        def work(cancelled):
            kf = GLib.KeyFile()
            try:
                kf.load_from_file(path, GLib.KeyFileFlags.NONE)
            except GLib.Error as e:
                raise Fail("Not a valid app launcher: " + e.message.split("\n")[0], "invalid")
            g = "Desktop Entry"

            def get(key, loc=False):
                try:
                    return kf.get_locale_string(g, key, None) if loc else kf.get_string(g, key)
                except GLib.Error:
                    return ""
            st = os.stat(path)
            return {"type": get("Type"), "name": get("Name", True), "exec": get("Exec"), "url": get("URL"),
                    "comment": get("Comment", True), "trusted": self._desktop_trusted(path, st)}
        self.in_pool(rid, work)

    def op_trust(self, rid, args):
        path = path_arg(args)
        try:
            st = os.lstat(path)
            if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid():
                raise Fail("Only your own launchers can be trusted", "denied")
            os.chmod(path, (stat.S_IMODE(st.st_mode) | 0o100) & ~0o022)
        except OSError as e:
            raise from_os(e)
        send({"id": rid, "type": "done"})

    def op_launch_desktop(self, rid, args):
        path = path_arg(args)
        try:
            st = os.stat(path)
        except OSError as e:
            raise from_os(e)
        if not self._desktop_trusted(path, st):
            raise Fail("This launcher isn't trusted", "denied")
        ctx = Gio.AppLaunchContext()
        for k in PRIVATE_ENV:
            ctx.unsetenv(k)
        kf = GLib.KeyFile()
        try:
            kf.load_from_file(path, GLib.KeyFileFlags.NONE)
            kind = kf.get_string("Desktop Entry", "Type")
            if kind == "Link":
                Gio.AppInfo.launch_default_for_uri(kf.get_string("Desktop Entry", "URL"), ctx)
            else:
                app = Gio.DesktopAppInfo.new_from_filename(path)
                if app is None:
                    raise Fail("Not a valid app launcher", "invalid")
                app.launch([], ctx)
        except GLib.Error as e:
            raise Fail(e.message.split("\n")[0], "unsupported")
        send({"id": rid, "type": "done"})


def main():
    # where the file manager keeps its state (FmState.qml writes it); private
    state = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "quickshell", "files")
    try:
        os.makedirs(state, mode=0o700, exist_ok=True)
    except OSError:
        pass
    Server().run()
    return 0
