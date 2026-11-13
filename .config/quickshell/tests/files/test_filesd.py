"""The file manager backend end to end: scripts/files/filesd.py runs as a
child process in a temp HOME (fake XDG dirs, bookmarks), driven over its
JSON-lines protocol like FmBackend.qml does.

Run: PYTHONDONTWRITEBYTECODE=1 python3 -I -m unittest discover -s tests/files
"""
import errno
import json
import os
import queue
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import warnings

HERE = os.path.dirname(os.path.abspath(__file__))
FILESD = os.path.join(HERE, "..", "..", "scripts", "files", "filesd.py")

# the same names and expected order as the FmSort test in tests/lib.test.mjs
SORT_NAMES = ["file10.txt", "File2.txt", "file1.txt", "b", "a10", "a9", "a09b", "Zed", "z"]
SORT_EXPECT = ["a9", "a09b", "a10", "b", "file1.txt", "File2.txt", "file10.txt", "z", "Zed"]


class Backend:
    def __init__(self, home, extra=None):
        env = {
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": home, "LANG": "C.UTF-8",
            "XDG_CONFIG_HOME": os.path.join(home, ".config"), "XDG_DATA_HOME": os.path.join(home, ".local/share"),
            "XDG_CACHE_HOME": os.path.join(home, ".cache"), "XDG_STATE_HOME": os.path.join(home, ".local/state"),
            "XDG_RUNTIME_DIR": os.environ.get("XDG_RUNTIME_DIR", home), "PYTHONDONTWRITEBYTECODE": "1",
            "GIO_USE_VFS": "local", "GVFS_DISABLE_FUSE": "1",
            "QS_SETTINGS_REMOTE": "1",
        }
        env.update(extra or {})
        self.p = subprocess.Popen(["python3", "-I", FILESD], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL, env=env)
        self.q = queue.Queue()
        self.next = 1
        threading.Thread(target=self._read, daemon=True).start()
        self.ready = self.event("ready")

    def _read(self):
        for line in self.p.stdout:
            self.q.put(json.loads(line))
        self.q.put(None)

    def send(self, op, **args):
        rid = self.next
        self.next += 1
        self.p.stdin.write((json.dumps({"id": rid, "op": op, "args": args}) + "\n").encode())
        self.p.stdin.flush()
        return rid

    def wait(self, rid, timeout=10):
        """(batches, final reply) of one request; events seen meanwhile are kept"""
        batches, end = [], time.monotonic() + timeout
        while True:
            m = self.q.get(timeout=max(0.01, end - time.monotonic()))
            if m is None:
                raise AssertionError("backend exited")
            if m.get("id") != rid:
                self.later.append(m)
                continue
            if m["type"] == "batch":
                batches.extend(m["items"])
            elif m["type"] not in ("progress", "ask"):
                return batches, m

    later = []

    def call(self, op, **args):
        return self.wait(self.send(op, **args))

    def event(self, name, timeout=10, pred=lambda m: True):
        for i, m in enumerate(self.later):
            if m.get("event") == name and pred(m):
                return self.later.pop(i)
        end = time.monotonic() + timeout
        while True:
            m = self.q.get(timeout=max(0.01, end - time.monotonic()))
            if m is None:
                raise AssertionError("backend exited")
            if m.get("event") == name and pred(m):
                return m
            self.later.append(m)

    def close(self):
        self.p.stdin.close()
        self.p.wait(5)
        self.p.stdout.close()


class FilesdTest(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp(prefix="filesd-test-")
        self.d = os.path.join(self.home, "d")
        os.makedirs(self.d)
        Backend.later = []
        self.b = Backend(self.home)

    def tearDown(self):
        self.b.close()
        for root, dirs, _ in os.walk(self.home):
            for x in dirs:
                os.chmod(os.path.join(root, x), 0o755)
        shutil.rmtree(self.home)

    def touch(self, *names, folder=None):
        for n in names:
            with open(os.path.join(folder or self.d, n), "w") as f:
                f.write("x")

    def test_ready_and_ping(self):
        self.assertEqual(self.b.ready["version"], 1)
        _, r = self.b.call("ping")
        self.assertTrue(r["pong"])

    def test_listing_parts(self):
        # (in-process: the streaming callback, the network fast path, the search skips)
        import sys
        sys.path[:0] = [os.path.join(HERE, "..", "..", "scripts", "files"), os.path.join(HERE, "..", "..", "scripts", "lib")]
        from filesd import listing, search
        self.touch(*["f%03d" % i for i in range(250)])
        seen = []
        items = listing.scan(self.d, lambda: False, progress=lambda out: seen.append(len(out)))
        self.assertEqual(len(items), 250)
        self.assertEqual(seen, [100, 200])
        # remote: no access() probe, no sniffing; the mode bits say read-only
        os.chmod(os.path.join(self.d, "f000"), 0o444)
        remote = {r["name"]: r for r in listing.scan(self.d, lambda: False, remote=True)}
        self.assertTrue(remote["f000"].get("ro"))
        self.assertNotIn("ro", remote["f001"])
        # a search never goes into a skipped folder
        os.makedirs(os.path.join(self.d, "skipme"))
        self.touch("needle", folder=os.path.join(self.d, "skipme"))
        got = []
        search.run(self.d, "needle", {"skip": frozenset((os.path.join(self.d, "skipme"),))}, lambda: False, got.extend)
        self.assertEqual(got, [])
        search.run(self.d, "needle", {}, lambda: False, got.extend)
        self.assertEqual([g["name"] for g in got], ["needle"])

    def test_natural_sort_folders_first(self):
        self.touch(*SORT_NAMES)
        os.mkdir(os.path.join(self.d, "zz dir"))
        os.mkdir(os.path.join(self.d, "A dir"))
        items, r = self.b.call("list", path=self.d)
        self.assertEqual(r["type"], "done")
        self.assertEqual([i["name"] for i in items], ["A dir", "zz dir"] + SORT_EXPECT)
        # reversed: folders still in front
        items, _ = self.b.call("list", path=self.d, reverse=True)
        self.assertEqual([i["name"] for i in items], ["zz dir", "A dir"] + SORT_EXPECT[::-1])
        items, _ = self.b.call("list", path=self.d, dirsFirst=False)
        self.assertEqual([i["name"] for i in items], ["a9", "a09b", "a10", "A dir", "b", "file1.txt", "File2.txt",
                                                      "file10.txt", "z", "Zed", "zz dir"])

    def test_sort_by_size_and_mtime(self):
        for n, size, t in (("big", 300, 100), ("small", 1, 300), ("mid", 20, 200)):
            with open(os.path.join(self.d, n), "w") as f:
                f.write("x" * size)
            os.utime(os.path.join(self.d, n), (t, t))
        items, _ = self.b.call("list", path=self.d, sort="size")
        self.assertEqual([i["name"] for i in items], ["small", "mid", "big"])
        items, _ = self.b.call("list", path=self.d, sort="mtime", reverse=True)
        self.assertEqual([i["name"] for i in items], ["small", "mid", "big"])
        _, r = self.b.call("list", path=self.d, sort="color")
        self.assertEqual(r["code"], "invalid")

    def test_hidden(self):
        self.touch(".dot", "backup~", "listed", "shown")
        with open(os.path.join(self.d, ".hidden"), "w") as f:
            f.write("listed\n")
        items, r = self.b.call("list", path=self.d)
        self.assertEqual([i["name"] for i in items], ["shown"])
        self.assertEqual(r["hiddenCount"], 4)            # .dot, backup~, listed, .hidden
        items, _ = self.b.call("list", path=self.d, hidden=True)
        self.assertEqual(len(items), 5)
        self.assertTrue(all(i["hidden"] for i in items if i["name"] != "shown"))

    def test_nasty_names_round_trip(self):
        names = ["$(rm -rf x).txt", "-rf", "it's", 'quote".txt', "new\nline", "emoji 🎉", "a" * 250]
        self.touch(*names)
        raw = os.path.join(os.fsencode(self.d), b"latin-\xe9")       # not UTF-8
        with open(raw, "w") as f:
            f.write("x")
        items, _ = self.b.call("list", path=self.d)
        got = {i["name"] for i in items}
        for n in names:
            self.assertIn(n, got)
        bad = [n for n in got if n.startswith("latin-")][0]
        self.assertEqual(os.fsencode(bad), b"latin-\xe9")
        # the name comes back as the UI would send it, and still finds the file
        _, r = self.b.call("info", paths=[os.path.join(self.d, bad)])
        self.assertEqual(r["items"][0]["name"], bad)

    def test_errors(self):
        locked = os.path.join(self.d, "locked")
        os.mkdir(locked, 0)
        if os.access(locked, os.R_OK):
            self.skipTest("running as root")
        _, r = self.b.call("list", path=locked)
        self.assertEqual(r["code"], "denied")
        _, r = self.b.call("list", path=os.path.join(self.d, "nope"))
        self.assertEqual(r["code"], "missing")
        self.touch("f")
        _, r = self.b.call("list", path=os.path.join(self.d, "f"))
        self.assertEqual(r["code"], "notdir")
        _, r = self.b.call("list", path="relative/path")
        self.assertEqual(r["code"], "invalid")
        _, r = self.b.call("list", path="/x\0y")
        self.assertEqual(r["code"], "invalid")
        _, r = self.b.call("nope")
        self.assertEqual(r["code"], "invalid")
        # the backend is still there after bad requests
        self.b.p.stdin.write(b"not json\n[1]\n")
        self.b.p.stdin.flush()
        _, r = self.b.call("ping")
        self.assertTrue(r["pong"])

    def test_dirs(self):
        for n in ["b dir", "A dir", ".hid", "x10", "x9"]:
            os.mkdir(os.path.join(self.d, n))
        self.touch("file.txt")
        os.symlink(os.path.join(self.d, "A dir"), os.path.join(self.d, "to a"))
        os.symlink(os.path.join(self.d, "nowhere"), os.path.join(self.d, "broken"))
        _, r = self.b.call("dirs", path=self.d)
        self.assertEqual(r["type"], "done")
        self.assertEqual(r["names"], [".hid", "A dir", "b dir", "to a", "x9", "x10"])
        self.assertFalse(r["more"])
        _, r = self.b.call("dirs", path=os.path.join(self.d, "file.txt"))
        self.assertEqual(r["code"], "notdir")
        _, r = self.b.call("dirs", path="rel")
        self.assertEqual(r["code"], "invalid")

    # ── operations ──

    def run_job(self, op, answers=(), **args):
        """an operation to its end; each "ask" gets the next answer; (progress lines, asks, reply)"""
        rid = self.b.send(op, **args)
        answers = list(answers)
        progress, asks = [], []
        end = time.monotonic() + 20
        while True:
            m = self.b.q.get(timeout=max(0.01, end - time.monotonic()))
            if m is None:
                raise AssertionError("backend exited")
            if m.get("id") != rid:
                Backend.later.append(m)
                continue
            if m["type"] == "progress":
                progress.append(m)
            elif m["type"] == "ask":
                asks.append(m)
                a = answers.pop(0) if answers else {"action": "cancel"}
                self.b.send("answer", target=rid, **a)
            else:
                return progress, asks, m

    def read(self, *parts):
        with open(os.path.join(*parts)) as f:
            return f.read()

    def test_copy_with_conflicts(self):
        src = os.path.join(self.home, "src")
        os.makedirs(os.path.join(src, "folder", "sub"))
        for n, t in (("a.txt", "new a"), ("b.txt", "new b"), ("folder/x", "x"), ("folder/sub/y", "y")):
            with open(os.path.join(src, n), "w") as f:
                f.write(t)
        os.symlink("a.txt", os.path.join(src, "lnk"))
        os.chmod(os.path.join(src, "b.txt"), 0o640)
        with open(os.path.join(self.d, "a.txt"), "w") as f:
            f.write("old a")
        os.makedirs(os.path.join(self.d, "folder"))
        self.touch("keep", folder=os.path.join(self.d, "folder"))
        sources = [os.path.join(src, n) for n in ("a.txt", "b.txt", "folder", "lnk")]
        # a.txt: keep both; folder: merge
        prog, asks, r = self.run_job("copy", [{"action": "rename", "name": "a mine.txt"}, {"action": "merge"}],
                                     sources=sources, dest=self.d, mode="copy")
        self.assertEqual(r["type"], "done", r)
        self.assertEqual([a["kind"] for a in asks], ["conflict", "conflict"])
        self.assertTrue(asks[1]["folders"])
        self.assertEqual(self.read(self.d, "a.txt"), "old a")
        self.assertEqual(self.read(self.d, "a mine.txt"), "new a")
        self.assertEqual(oct(os.stat(os.path.join(self.d, "b.txt")).st_mode & 0o777), "0o640")
        self.assertEqual(sorted(os.listdir(os.path.join(self.d, "folder"))), ["keep", "sub", "x"])
        self.assertEqual(os.readlink(os.path.join(self.d, "lnk")), "a.txt")
        self.assertEqual(len(r["made"]), 4)
        self.assertTrue(any(p["totalBytes"] > 0 for p in prog))
        self.assertFalse([n for n in os.listdir(self.d) if "qsfm-part" in n])
        # replace for all
        _, asks, r = self.run_job("copy", [{"action": "replace", "all": True}], sources=sources[:2], dest=self.d, mode="copy")
        self.assertEqual(len(asks), 1)
        self.assertEqual(self.read(self.d, "a.txt"), "new a")
        # into its own folder: "a (copy).txt", then "a (copy 2).txt"
        self.run_job("copy", sources=[os.path.join(self.d, "a.txt")], dest=self.d, mode="copy")
        _, _, r = self.run_job("copy", sources=[os.path.join(self.d, "a.txt")], dest=self.d, mode="copy")
        self.assertEqual(os.path.basename(r["made"][0]["dst"]), "a (copy 2).txt")
        # a folder into itself
        _, _, r = self.run_job("copy", sources=[src], dest=os.path.join(src, "folder"), mode="copy")
        self.assertEqual(r["code"], "invalid")
        # cancel at a conflict: stops, nothing half-done
        _, _, r = self.run_job("copy", [{"action": "cancel"}], sources=sources[:1], dest=self.d, mode="copy")
        self.assertTrue(r.get("cancelled") or r.get("code") == "cancelled")

    def test_move_link_and_relocate(self):
        src = os.path.join(self.home, "src")
        os.makedirs(os.path.join(src, "dir"))
        self.touch("f", folder=src)
        _, _, r = self.run_job("copy", sources=[os.path.join(src, "f"), os.path.join(src, "dir")], dest=self.d, mode="move")
        self.assertEqual(r["type"], "done", r)
        self.assertEqual(sorted(os.listdir(src)), [])
        self.assertEqual(sorted(os.listdir(self.d)), ["dir", "f"])
        # undo: back exactly where they were
        pairs = [{"from": m["dst"], "to": m["src"]} for m in r["made"]]
        _, _, r = self.run_job("relocate", pairs=pairs)
        self.assertEqual(sorted(os.listdir(src)), ["dir", "f"])
        # a taken target is an error for relocate, never a question
        self.touch("f", folder=self.d)
        _, asks, r = self.run_job("relocate", pairs=[{"from": os.path.join(self.d, "f"), "to": os.path.join(src, "f")}])
        self.assertEqual((asks, r["code"]), ([], "exists"))
        _, _, r = self.run_job("copy", sources=[os.path.join(src, "dir")], dest=self.d, mode="link")
        self.assertEqual(os.readlink(os.path.join(self.d, "dir")), os.path.join(src, "dir"))

    def test_trash_restore_delete(self):
        self.touch("t1", "t2")
        os.makedirs(os.path.join(self.d, "tdir", "in"))
        paths = [os.path.join(self.d, n) for n in ("t1", "t2", "tdir")]
        _, _, r = self.run_job("trash", paths=paths)
        self.assertEqual(sorted(r["trashed"]), sorted(paths), r)
        trash = os.path.join(self.home, ".local/share/Trash")
        self.assertEqual(sorted(os.listdir(os.path.join(trash, "files"))), ["t1", "t2", "tdir"])
        self.touch("t2")                        # its place got taken meanwhile
        _, asks, r = self.run_job("restore", [{"action": "rename", "name": "t2 back"}], paths=paths)
        self.assertEqual(sorted(r["restored"]), sorted([paths[0], os.path.join(self.d, "t2 back"), paths[2]]), r)
        self.assertTrue(os.path.isdir(os.path.join(self.d, "tdir", "in")))
        self.assertEqual(os.listdir(os.path.join(trash, "info")), [])
        _, _, r = self.run_job("delete", paths=[os.path.join(self.d, "tdir"), os.path.join(self.d, "t1")])
        self.assertEqual(len(r["deleted"]), 2)
        self.assertFalse(os.path.exists(os.path.join(self.d, "tdir")))
        _, _, r = self.run_job("delete", paths=[self.home])
        self.assertEqual(r["code"], "invalid")

    def test_errors_ask_and_skip(self):
        src = os.path.join(self.home, "src")
        os.makedirs(src)
        self.touch("ok", "secret", folder=src)
        os.chmod(os.path.join(src, "secret"), 0)
        if os.access(os.path.join(src, "secret"), os.R_OK):
            self.skipTest("running as root")
        _, asks, r = self.run_job("copy", [{"action": "skip"}], sources=[os.path.join(src, "ok"), os.path.join(src, "secret")],
                                  dest=self.d, mode="copy")
        self.assertEqual(asks[0]["kind"], "error")
        self.assertEqual((r["skipped"], sorted(os.listdir(self.d))), (1, ["ok"]))
        os.chmod(self.d, 0o500)                 # read-only target: one question per file, skip all
        try:
            _, asks, r = self.run_job("copy", [{"action": "skip", "all": True}], sources=[os.path.join(src, "ok")] * 1,
                                      dest=self.d, mode="copy")
        finally:
            os.chmod(self.d, 0o755)

    def test_pause_and_cancel(self):
        big = os.path.join(self.home, "big")
        with open(big, "wb") as f:
            f.truncate(0)
            f.write(os.urandom(1 << 20) * 64)          # 64 MiB
        rid = self.b.send("copy", sources=[big], dest=self.d, mode="copy")
        self.b.send("pause", target=rid, paused=True)
        time.sleep(0.3)
        self.b.send("cancel", target=rid)
        _, r = self.b.wait(rid)
        self.assertTrue(r.get("cancelled") or r.get("code") == "cancelled", r)
        self.assertEqual([n for n in os.listdir(self.d) if "qsfm-part" in n or n == "big"], [])

    def test_names_and_new_things(self):
        _, r = self.b.call("mkdir", dir=self.d, name="New Folder")
        self.assertTrue(os.path.isdir(r["path"]))
        _, r = self.b.call("mkdir", dir=self.d, name="New Folder")
        self.assertEqual(r["code"], "exists")
        for bad in ("", "  ", ".", "..", "a/b", "x" * 256):
            _, r = self.b.call("mkdir", dir=self.d, name=bad)
            self.assertEqual(r["code"], "invalid", bad)
        tpl = os.path.join(self.home, "tpl.txt")
        with open(tpl, "w") as f:
            f.write("hello")
        _, r = self.b.call("newfile", dir=self.d, name="from tpl.txt", template=tpl)
        self.assertEqual(self.read(r["path"]), "hello")
        _, r = self.b.call("newfile", dir=self.d, name="empty")
        self.assertEqual(os.path.getsize(r["path"]), 0)
        _, r = self.b.call("rename", path=os.path.join(self.d, "empty"), name="from tpl.txt")
        self.assertEqual(r["code"], "exists")
        _, r = self.b.call("rename", path=os.path.join(self.d, "empty"), name="$(rm -rf x)")
        self.assertTrue(os.path.exists(os.path.join(self.d, "$(rm -rf x)")))
        _, r = self.b.call("templates")
        self.assertEqual(r["type"], "done")

    def test_auto_mode_and_save(self):
        src = os.path.join(self.home, "src")
        os.makedirs(src)
        self.touch("f", folder=src)
        _, _, r = self.run_job("copy", sources=[os.path.join(src, "f")], dest=self.d, mode="auto")
        self.assertEqual(r["mode"], "move")          # same drive: a move
        _, r = self.b.call("save", dir=self.d, name="note.txt", text="hi")
        self.assertEqual(self.read(r["path"]), "hi")
        _, r = self.b.call("save", dir=self.d, name="note.txt", base64="aGk=")
        self.assertEqual(os.path.basename(r["path"]), "note (2).txt")
        _, r = self.b.call("save", dir=self.d, name="../evil", text="x")
        self.assertEqual(os.path.basename(r["path"]), "Saved from web")
        _, r = self.b.call("openUri", uri="file:///etc/passwd")
        self.assertEqual(r["code"], "invalid")

    def test_desktop_trust(self):
        p = os.path.join(self.d, "app.desktop")
        with open(p, "w") as f:
            f.write("[Desktop Entry]\nType=Application\nName=Thing\nExec=true\n")
        _, r = self.b.call("desktop", path=p)
        self.assertEqual((r["name"], r["exec"], r["trusted"]), ("Thing", "true", False))
        _, r = self.b.call("launchDesktop", path=p)
        self.assertEqual(r["code"], "denied")
        self.b.call("trust", path=p)
        _, r = self.b.call("desktop", path=p)
        self.assertTrue(r["trusted"])
        _, r = self.b.call("run", path=os.path.join(self.d, "app.desktop.nope"))
        self.assertEqual(r["code"], "missing")

    # ── knowing (Phase 4) ──

    @staticmethod
    def png(path, w=40, h=30):
        """a small real PNG (no imaging library needed)"""
        import struct
        import zlib
        raw = b"".join(b"\0" + bytes([200, 80, 40]) * w for _ in range(h))
        def chunk(t, d):
            return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
        with open(path, "wb") as f:
            f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                    + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))

    def test_search(self):
        os.makedirs(os.path.join(self.d, "Projects", "deep", ".secret"))
        self.touch("Documents.txt", "my documents.md", "docu.txt", "zz.txt")
        self.touch("documents", folder=os.path.join(self.d, "Projects", "deep"))
        self.touch("documents-hidden", folder=os.path.join(self.d, "Projects", "deep", ".secret"))
        items, r = self.b.call("search", path=self.d, query="docu")
        self.assertEqual(r["type"], "done", r)
        names = [i["name"] for i in items]
        self.assertEqual(set(names), {"Documents.txt", "my documents.md", "docu.txt", "documents"})
        by = {i["name"]: i for i in items}
        self.assertGreater(by["docu.txt"]["score"], by["my documents.md"]["score"])        # whole name beats inside
        self.assertGreater(by["Documents.txt"]["score"], by["documents"]["score"])         # nearer beats deeper
        self.assertEqual(by["documents"]["loc"], "Projects/deep")
        self.assertEqual(by["docu.txt"]["loc"], "")
        items, _ = self.b.call("search", path=self.d, query="docu", hidden=True)
        self.assertIn("documents-hidden", [i["name"] for i in items])
        items, _ = self.b.call("search", path=self.d, query="docu", depth=0)
        self.assertNotIn("documents", [i["name"] for i in items])
        items, _ = self.b.call("search", path=self.d, query="dcmnts")                       # loose: letters in order
        self.assertIn("Documents.txt", [i["name"] for i in items])
        items, _ = self.b.call("search", path=self.d, query="docu my")                      # every word
        self.assertEqual([i["name"] for i in items], ["my documents.md"])
        items, _ = self.b.call("search", path=self.d, query="d", kinds=["folder"])
        self.assertTrue(all(i["dir"] for i in items) and items)
        items, _ = self.b.call("search", path=self.d, query="docu", since=time.time() + 3600)
        self.assertEqual(items, [])

    def test_props_du_counts(self):
        os.makedirs(os.path.join(self.d, "f", "g"))
        with open(os.path.join(self.d, "f", "a"), "wb") as f:
            f.write(b"x" * 1000)
        os.link(os.path.join(self.d, "f", "a"), os.path.join(self.d, "f", "g", "hard"))
        self.touch(".hid", "b", folder=os.path.join(self.d, "f"))
        _, r = self.b.call("du", paths=[os.path.join(self.d, "f")])
        self.assertEqual((r["size"], r["files"], r["dirs"]), (1002, 4, 2), r)       # the hard link once
        _, r = self.b.call("counts", dir=self.d, names=["f", "nope"])
        self.assertEqual(r["counts"], {"f": 3, "nope": -1})
        _, r = self.b.call("counts", dir=self.d, names=["f"], hidden=True)
        self.assertEqual(r["counts"]["f"], 4)
        self.png(os.path.join(self.d, "pic.png"))
        _, r = self.b.call("props", path=os.path.join(self.d, "pic.png"))
        self.assertEqual((r["type"], r["mime"], r["width"], r["height"], r["mine"]), ("done", "image/png", 40, 30, True), r)
        self.assertIn("owner", r)
        _, r = self.b.call("chmod", path=os.path.join(self.d, "pic.png"), mode=0o600)
        self.assertEqual(oct(os.stat(os.path.join(self.d, "pic.png")).st_mode & 0o777), "0o600")
        _, r = self.b.call("chown", path=os.path.join(self.d, "pic.png"), owner="-R", group="x")
        self.assertEqual(r["code"], "invalid")

    def test_preview_and_thumb(self):
        with open(os.path.join(self.d, "t.txt"), "w") as f:
            f.write("héllo\n")
        _, r = self.b.call("preview", path=os.path.join(self.d, "t.txt"))
        self.assertEqual((r["type"], r["kind"], r["text"]), ("done", "text", "héllo\n"), r)
        with open(os.path.join(self.d, "bin.txt"), "wb") as f:
            f.write(b"\0\1\2")
        _, r = self.b.call("preview", path=os.path.join(self.d, "bin.txt"))
        self.assertEqual(r["kind"], "other")
        self.png(os.path.join(self.d, "p.png"))
        _, r = self.b.call("preview", path=os.path.join(self.d, "p.png"))
        self.assertEqual(r["kind"], "image")
        sys_pdf = os.path.join(HERE, "..", "mail", "sample.py")
        import importlib.util, sys as _s
        spec = importlib.util.spec_from_file_location("sample", sys_pdf)
        _s.path.insert(0, os.path.dirname(sys_pdf))
        sample = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(sample)
        with open(os.path.join(self.d, "doc.pdf"), "wb") as f:
            f.write(sample.tiny_pdf("Hi"))
        _, r = self.b.call("preview", path=os.path.join(self.d, "doc.pdf"))
        if r["type"] == "error" and "pdftoppm" in r["error"]:
            self.skipTest("poppler missing")
        self.assertEqual((r["kind"], r["pageCount"]), ("pdf", 1), r)
        self.assertTrue(os.path.exists(r["pages"][0]))
        st = os.stat(os.path.join(self.d, "p.png"))
        _, r = self.b.call("thumb", path=os.path.join(self.d, "p.png"), type="image/png", mtime=int(st.st_mtime))
        self.assertEqual(r["type"], "done", r)
        if r["thumb"]:
            self.assertTrue(r["thumb"].startswith(os.path.join(self.home, ".cache", "thumbnails")))
        st = os.stat(os.path.join(self.d, "doc.pdf"))
        _, r = self.b.call("thumb", path=os.path.join(self.d, "doc.pdf"), type="application/pdf", mtime=int(st.st_mtime), large=True)
        self.assertTrue(r["thumb"].endswith(".png") and "/large/" in r["thumb"], r)
        _, r = self.b.call("apps", type="text/plain")
        self.assertEqual(r["type"], "done")
        self.assertIn("apps", r)

    # ── reaching (Phase 5) ──

    def test_archives(self):
        import shutil as _sh
        src = os.path.join(self.home, "pack")
        os.makedirs(os.path.join(src, "inner"))
        with open(os.path.join(src, "inner", "a.txt"), "w") as f:
            f.write("hello")
        os.chmod(os.path.join(src, "inner", "a.txt"), 0o750)
        for fmt in ("zip", "tar.xz"):
            _, _, r = self.run_job("compress", paths=[src], dest=self.d, name="out-" + fmt.replace(".", ""), format=fmt)
            self.assertEqual(r["type"], "done", r)
            _, _, r = self.run_job("extract", path=r["path"], dest=os.path.join(self.home))
            self.assertEqual(r["type"], "done", r)
            self.assertEqual(self.read(r["path"], "inner", "a.txt"), "hello")
            _sh.rmtree(r["path"])
        # a zip with "../" in a name: refused, nothing left behind
        import zipfile
        bad = os.path.join(self.d, "bad.zip")
        with zipfile.ZipFile(bad, "w") as z:
            z.writestr("../escape.txt", "x")
        _, _, r = self.run_job("extract", path=bad, dest=self.d)
        self.assertEqual(r["code"], "invalid")
        self.assertFalse(os.path.exists(os.path.join(self.home, "escape.txt")))
        self.assertFalse([n for n in os.listdir(self.d) if "qsfm-part" in n])
        if not _sh.which("7z"):
            return
        # 7z with a password: typed into 7z's prompt, asked for when extracting
        _, _, r = self.run_job("compress", paths=[src], dest=self.d, name="secret", format="7z", password="pw 123")
        self.assertEqual(r["type"], "done", r)
        out = os.path.join(self.home, "x7")
        os.mkdir(out)
        _, asks, r = self.run_job("extract", [{"action": "ok", "password": "pw 123"}], path=os.path.join(self.d, "secret.7z"), dest=out)
        self.assertEqual(r["type"], "done", r)
        self.assertEqual([a["kind"] for a in asks], ["password"])
        self.assertEqual(self.read(r["path"], "inner", "a.txt"), "hello")

    def test_trash_view(self):
        self.touch("t1", "t2")
        self.run_job("trash", paths=[os.path.join(self.d, "t1"), os.path.join(self.d, "t2")])
        _, r = self.b.call("trashList")
        self.assertEqual(r["type"], "done", r)
        names = {i["name"]: i for i in r["items"]}
        self.assertEqual(set(names), {"t1", "t2"})
        self.assertEqual(names["t1"]["orig"], os.path.join(self.d, "t1"))
        e = names["t1"]
        _, _, r = self.run_job("trashRestore", items=[{"file": e["path"], "info": e["info"], "orig": e["orig"]}])
        self.assertTrue(os.path.exists(os.path.join(self.d, "t1")), r)
        # only real trash entries: a path outside is ignored
        _, _, r = self.run_job("trashDelete", items=[{"file": os.path.join(self.d, "t1"), "info": os.path.join(self.d, "t1.trashinfo"), "orig": ""}])
        self.assertTrue(os.path.exists(os.path.join(self.d, "t1")))
        _, _, r = self.run_job("trashEmpty")
        _, r = self.b.call("trashList")
        self.assertEqual(r["items"], [])

    def test_recent_and_scripts(self):
        self.touch("seen.txt")
        p = os.path.join(self.d, "seen.txt")
        _, r = self.b.call("addRecent", path=p, type="text/plain")
        self.assertEqual(r["type"], "done", r)
        _, r = self.b.call("addRecent", path=p, type="text/plain")
        x = self.read(self.home, ".local/share/recently-used.xbel")
        self.assertEqual(x.count("seen.txt"), 1)
        self.assertIn('count="2"', x)
        self.assertIn("mime-type", x)
        _, r = self.b.call("recent")
        self.assertEqual([i["path"] for i in r["items"]], [p])
        sd = os.path.join(self.home, ".local/share/quickshell/files/scripts")
        os.makedirs(sd)
        out = os.path.join(self.home, "script-ran")
        with open(os.path.join(sd, "Mark"), "w") as f:
            f.write('#!/bin/sh\nprintf "%s\\n" "$@" > "' + out + '"\n')
        os.chmod(os.path.join(sd, "Mark"), 0o700)
        with open(os.path.join(sd, "notexec"), "w") as f:
            f.write("x")
        _, r = self.b.call("scripts")
        self.assertEqual([x["name"] for x in r["scripts"]], ["Mark"])
        _, r = self.b.call("runScript", script=os.path.join(sd, "Mark"), paths=[p, os.path.join(self.d, "-rf")], cwd=self.d)
        for _ in range(50):
            if os.path.exists(out):
                break
            time.sleep(0.05)
        time.sleep(0.1)
        self.assertEqual(self.read(out), p + "\n" + os.path.join(self.d, "-rf") + "\n")
        _, r = self.b.call("runScript", script="/bin/sh", paths=[p], cwd=self.d)
        self.assertEqual(r["code"], "denied")
        _, r = self.b.call("connect", uri="file:///etc")
        self.assertEqual(r["code"], "invalid")
        _, r = self.b.call("places")
        self.assertIn("volumes", r)

    def test_bookmarks(self):
        bm = os.path.join(self.home, ".config/gtk-3.0/bookmarks")
        os.makedirs(os.path.dirname(bm))
        with open(bm, "w") as f:
            f.write("sftp://host/x Server\nfile:///keep\n")
        a, b = os.path.join(self.d, "a b"), os.path.join(self.d, "c")
        os.makedirs(a)
        os.makedirs(b)
        self.b.call("bookmark", action="add", path=a, label="Mine")
        self.b.call("bookmark", action="add", path=b)
        self.b.call("bookmark", action="add", path=b)                   # once only
        ua = "file://" + a.replace(" ", "%20")
        self.assertEqual(self.read(bm).splitlines(), ["sftp://host/x Server", "file:///keep", ua + " Mine", "file://" + b])
        self.b.call("bookmark", action="rename", uri=ua, label="New name")
        self.b.call("bookmark", action="move", uri=ua, step=-1)
        self.b.call("bookmark", action="remove", uri="file:///keep")
        self.assertEqual(self.read(bm).splitlines(), ["sftp://host/x Server", ua + " New name", "file://" + b])
        # a server by its address, a password typed into it never kept; not a server: refused
        _, r = self.b.call("bookmark", action="add", uri="sftp://me:secret@box/srv")
        self.assertNotIn("secret", self.read(bm))
        self.assertIn("sftp://me@box/srv", self.read(bm))
        self.assertEqual(self.b.call("bookmark", action="add", uri="file:///etc")[1]["type"], "error")
        self.b.call("bookmark", action="remove", uri="sftp://me@box/srv")
        self.b.call("bookmark", action="order", uris=["file://" + b, "sftp://host/x"])
        self.assertEqual(self.read(bm).splitlines(), ["file://" + b, "sftp://host/x Server", ua + " New name"])
        _, r = self.b.call("bookmark", action="rename", uri=ua, label="two\nlines")
        self.assertEqual(r["code"], "invalid")

    def test_items(self):
        os.mkdir(os.path.join(self.d, "sub"))
        self.touch("script.sh", "photo.JPG", "archive.tar.gz")
        os.chmod(os.path.join(self.d, "script.sh"), 0o755)
        os.symlink("sub", os.path.join(self.d, "to-sub"))
        os.symlink("gone", os.path.join(self.d, "dangling"))
        os.symlink("loop2", os.path.join(self.d, "loop1"))
        os.symlink("loop1", os.path.join(self.d, "loop2"))
        with open(os.path.join(self.d, "noext"), "w") as f:
            f.write("#!/bin/sh\necho hi\n")
        items, _ = self.b.call("list", path=self.d)
        by = {i["name"]: i for i in items}
        self.assertTrue(by["sub"]["dir"])
        self.assertTrue(by["to-sub"]["dir"] and by["to-sub"]["link"])
        self.assertEqual(by["to-sub"]["target"], "sub")
        self.assertTrue(by["dangling"]["broken"])
        self.assertTrue(by["loop1"]["broken"])
        self.assertTrue(by["script.sh"].get("exec"))
        self.assertEqual(by["photo.JPG"]["type"], "image/jpeg")
        self.assertEqual(by["archive.tar.gz"]["type"], "application/x-compressed-tar")
        self.assertEqual(by["noext"]["type"], "text/x-shellscript")        # by its first bytes

    def test_watch(self):
        self.touch("old")
        _, r = self.b.call("watch", path=self.d)
        wid = r["watch"]
        self.touch("new")
        os.rename(os.path.join(self.d, "old"), os.path.join(self.d, "renamed"))
        seen = {}
        end = time.monotonic() + 5
        while time.monotonic() < end and not ({"new", "renamed"} <= {k for k, v in seen.items() if v} and seen.get("old") is False):
            m = self.b.event("changed", pred=lambda m: m["watch"] == wid)
            for c in m.get("changes", []):
                seen[c["item"]["name"] if c["kind"] == "upsert" else c["name"]] = c["kind"] == "upsert"
        self.assertTrue(seen.get("new"))
        self.assertTrue(seen.get("renamed"))
        self.assertIs(seen.get("old"), False)
        # the folder itself goes away
        shutil.rmtree(self.d)
        self.b.event("gone", pred=lambda m: m["watch"] == wid)
        _, r = self.b.call("unwatch", watch=wid)
        self.assertFalse(r["found"])           # already dropped when it went

    def test_watch_burst_rescans(self):
        _, r = self.b.call("watch", path=self.d)
        wid = r["watch"]
        self.touch(*["f%d" % i for i in range(1500)])
        m = self.b.event("changed", pred=lambda m: m["watch"] == wid and m.get("rescan"))
        self.assertTrue(m["rescan"])

    def test_cancel(self):
        big = os.path.join(self.d, "big")
        os.mkdir(big)
        for i in range(20000):
            open(os.path.join(big, "f%05d" % i), "w").close()
        rid = self.b.send("list", path=big)
        self.b.send("cancel", target=rid)
        _, r = self.b.wait(rid)
        # either it was quicker than the cancel, or it stopped
        self.assertIn(r["type"], ("done", "error"))
        if r["type"] == "error":
            self.assertEqual(r["code"], "cancelled")

    def test_places(self):
        cfg = os.path.join(self.home, ".config")
        os.makedirs(os.path.join(cfg, "gtk-3.0"))
        dl = os.path.join(self.home, "Downloads")
        os.mkdir(dl)
        with open(os.path.join(cfg, "user-dirs.dirs"), "w") as f:
            f.write('XDG_DOWNLOAD_DIR="$HOME/Downloads"\nXDG_MUSIC_DIR="$HOME/Missing"\nXDG_DESKTOP_DIR="$HOME/"\n')
        with open(os.path.join(cfg, "gtk-3.0", "bookmarks"), "w") as f:
            f.write("file://%s Work stuff\nfile://%s/gone\nsftp://example.org/srv\n" % (self.d.replace(" ", "%20"), self.home))
        self.b.close()
        self.b = Backend(self.home)           # GLib reads user-dirs.dirs once
        _, r = self.b.call("places")
        self.assertEqual(r["home"], self.home)
        self.assertEqual([x["path"] for x in r["xdg"]], [dl])
        bm = r["bookmarks"]
        self.assertEqual(bm[0]["name"], "Work stuff")
        self.assertEqual(bm[0]["path"], self.d)
        self.assertTrue(bm[1]["missing"])
        self.assertTrue(bm[2]["remote"])
        self.assertGreater(r["root"]["size"], 0)
        # editing the bookmarks sends an event
        with open(os.path.join(cfg, "gtk-3.0", "bookmarks"), "a") as f:
            f.write("file:///tmp\n")
        self.b.event("places")

    def test_free_and_info(self):
        _, r = self.b.call("free", path=self.d)
        self.assertGreater(r["size"], 0)
        self.assertLessEqual(r["free"], r["size"])
        _, r = self.b.call("info", paths=[self.d, os.path.join(self.d, "nope")])
        self.assertTrue(r["items"][0]["dir"])
        self.assertIsNone(r["items"][1])

    def test_launch_checks(self):
        _, r = self.b.call("launch", path=self.d)
        self.assertEqual(r["code"], "invalid")
        _, r = self.b.call("launch", path=os.path.join(self.d, "nope"))
        self.assertEqual(r["code"], "missing")

    def test_state_dir(self):
        st = os.stat(os.path.join(self.home, ".local/state/quickshell/files"))
        self.assertEqual(st.st_mode & 0o777, 0o700)

# ── Round 11: shares (no modes / times, no change notification), saved logins, the portal ──

sys.path.insert(0, os.path.join(HERE, "..", "..", "scripts", "files"))
warnings.filterwarnings("ignore", category=DeprecationWarning, module="gi")      # (PyGObject on a new Python)


class SoftMetaTest(unittest.TestCase):
    """a server through GVfs can't take a mode or a time: the copy still succeeds"""
    def test_copy_without_modes_and_times(self):
        from unittest import mock
        from filesd import ops
        home = tempfile.mkdtemp(prefix="filesd-test-")
        try:
            src, dst = os.path.join(home, "src"), os.path.join(home, "dst")
            os.makedirs(os.path.join(src, "sub"))
            os.makedirs(dst)
            with open(os.path.join(src, "sub", "a.txt"), "w") as f:
                f.write("hello")
            no = OSError(errno.EOPNOTSUPP, "Operation not supported")
            asked = []
            job = ops.Job(1)
            job.ask = lambda kind, key=None, **info: asked.append((kind, info)) or {"action": "skip"}
            with mock.patch("os.fchmod", side_effect=no), mock.patch("os.chmod", side_effect=no), \
                    mock.patch("os.utime", side_effect=no), mock.patch("os.copy_file_range", side_effect=no), \
                    mock.patch.object(ops, "send", lambda m: None):
                res = ops.run_transfer(job, ops.plan([src], dst, "copy"), "copy")
            self.assertEqual(asked, [])
            self.assertEqual(res["skipped"], 0)
            with open(os.path.join(dst, "src", "sub", "a.txt")) as f:
                self.assertEqual(f.read(), "hello")
            self.assertEqual([n for n in os.listdir(os.path.join(dst, "src", "sub")) if "qsfm-part" in n], [])
            # a real error still asks
            with mock.patch("os.fchmod", side_effect=OSError(errno.EIO, "I/O error")), mock.patch.object(ops, "send", lambda m: None):
                res = ops.run_transfer(job, [(os.path.join(src, "sub", "a.txt"), os.path.join(dst, "b.txt"))], "copy")
            self.assertEqual(len(asked), 1)
            self.assertEqual(res["skipped"], 1)
        finally:
            shutil.rmtree(home)


class PolledWatchTest(unittest.TestCase):
    """a folder without change notification: our operations name what they touched, and a
    change from elsewhere is seen by looking at the folder now and then"""
    def test_poke_and_poll(self):
        import concurrent.futures
        from gi.repository import GLib
        from filesd import watch
        home = tempfile.mkdtemp(prefix="filesd-test-")
        pool = concurrent.futures.ThreadPoolExecutor(max_workers=2)
        sent = []
        old_send, old_poll = watch.send, watch.POLL_S
        watch.send, watch.POLL_S = sent.append, 1
        ctx = GLib.MainContext.default()

        def spin(until, timeout=6):
            end = time.monotonic() + timeout
            while not until() and time.monotonic() < end:
                ctx.iteration(False)
                time.sleep(0.01)
            return until()
        try:
            with open(os.path.join(home, "gone.txt"), "w"):
                pass
            w = watch.Watch(7, home, lambda wid: None, True, pool)
            w.monitor.cancel()               # as on a server: nothing arrives by itself
            w.monitor = None
            self.assertTrue(w.polled)
            spin(lambda: w.stamp is not None)
            os.unlink(os.path.join(home, "gone.txt"))
            with open(os.path.join(home, "new.txt"), "w"):
                pass
            w.poke({"gone.txt", "new.txt"})
            self.assertTrue(spin(lambda: len(sent) > 0))
            kinds = {(c["kind"], c.get("name") or c["item"]["name"]) for c in sent[0]["changes"]}
            self.assertEqual(kinds, {("delete", "gone.txt"), ("upsert", "new.txt")})
            self.assertEqual(sent[0]["watch"], 7)
            # our own change doesn't come back as a rescan …
            spin(lambda: False, 2.5)
            self.assertEqual(len(sent), 1)
            # … one from elsewhere does
            with open(os.path.join(home, "elsewhere.txt"), "w"):
                pass
            os.utime(home, ns=(1, time.time_ns() + 5_000_000_000))
            self.assertTrue(spin(lambda: len(sent) > 1))
            self.assertEqual(sent[1], {"event": "changed", "watch": 7, "rescan": True})
            w.close()
        finally:
            watch.send, watch.POLL_S = old_send, old_poll
            pool.shutdown(wait=False)
            shutil.rmtree(home)


class SearchStreamTest(unittest.TestCase):
    """a match found early is sent at once, not when the whole search is over"""
    def test_first_match_goes_out_at_once(self):
        from filesd import search
        home = tempfile.mkdtemp(prefix="filesd-test-")
        try:
            with open(os.path.join(home, "needle.txt"), "w"):
                pass
            for i in range(30):
                os.makedirs(os.path.join(home, "d%02d" % i))
            got, scanned_at_first = [], []
            real = os.scandir

            def slow(path):
                if got and not scanned_at_first:
                    scanned_at_first.append(path)
                return real(path)
            from unittest import mock
            with mock.patch("os.scandir", side_effect=slow):
                res = search.run(home, "needle", {"depth": 64}, lambda: False, got.append)
            self.assertEqual(res["count"], 1)
            self.assertEqual([[i["name"] for i in b] for b in got], [["needle.txt"]])
            # it was sent while folders were still to be read (the first subfolder), not at the end
            self.assertTrue(scanned_at_first and os.path.dirname(scanned_at_first[0]) == home)
        finally:
            shutil.rmtree(home)


class LoginsTest(unittest.TestCase):
    def test_only_keyring_item_ids(self):
        from filesd import creds
        from filesd.proto import Fail
        for bad in ("", "/etc/passwd", "/org/freedesktop/secrets/collection/login", "/org/freedesktop/secrets/collection/a/../b", 7, None):
            with self.assertRaises(Fail):
                creds.secret_of(bad)


class PortalConfTest(unittest.TestCase):
    def test_conf_round_trip(self):
        from filesd import portal
        plain = "[preferred]\ndefault=gtk\norg.freedesktop.impl.portal.ScreenCast=gnome\n"
        on = portal.conf_set(plain, True)
        self.assertIn("org.freedesktop.impl.portal.FileChooser=quickshell", on)
        self.assertEqual(portal.conf_set(on, True), on)
        self.assertEqual(portal.conf_set(on, False), plain)
        had = "[preferred]\ndefault=gnome\norg.freedesktop.impl.portal.FileChooser=gtk\n\n[other]\nx=1\n"
        on = portal.conf_set(had, True)
        self.assertEqual(on.count("FileChooser="), 1)
        self.assertIn("before = gtk", on)
        self.assertLess(on.index("FileChooser=quickshell"), on.index("[other]"))
        off = portal.conf_set(on, False)
        self.assertIn("org.freedesktop.impl.portal.FileChooser=gtk", off)
        self.assertNotIn("quickshell", off)
        self.assertEqual(portal.conf_set("", False), "")

    def test_parse_and_results(self):
        from gi.repository import GLib
        from filesd import portal
        opts = GLib.Variant("a{sv}", {
            "accept_label": GLib.Variant("s", "_Open it\nnow"), "multiple": GLib.Variant("b", True),
            "filters": GLib.Variant("a(sa(us))", [("Images", [(0, "*.png"), (1, "image/jpeg")]), ("All", [(0, "*")])]),
            "current_filter": GLib.Variant("(sa(us))", ("All", [(0, "*")])),
            "choices": GLib.Variant("a(ssa(ss)s)", [("enc", "Encoding", [("utf8", "UTF-8"), ("l1", "Latin 1")], "utf8"), ("ro", "Read only", [], "false")]),
            "current_folder": GLib.Variant("ay", b"/tmp/some dir\0"),
        })
        req = portal.parse("OpenFile", "Pick", opts)
        self.assertEqual((req["mode"], req["multiple"], req["accept"], req["folder"], req["filter"]),
                         ("open", True, "Open it now", "/tmp/some dir", 1))
        self.assertEqual(req["filters"][0], {"name": "Images", "globs": ["*.png"], "mimes": ["image/jpeg"]})
        self.assertEqual(req["choices"][1], {"id": "ro", "label": "Read only", "options": [], "value": "false"})
        raw = [opts.lookup_value("filters", None).get_child_value(i) for i in range(2)]
        code, res = portal.results(req, raw, True, ["/tmp/a b.txt"], {"enc": "l1", "ro": "true", "nope": "x", "enc2": 3}, 0).unpack()
        self.assertEqual(code, 0)
        self.assertEqual(res["uris"], ["file:///tmp/a%20b.txt"])
        self.assertEqual(sorted(res["choices"]), [("enc", "l1"), ("ro", "true")])
        self.assertEqual(res["current_filter"][0], "Images")
        self.assertEqual(portal.results(req, raw, False, ["/x"], {}, -1).unpack(), (1, {}))
        self.assertEqual(portal.parse("OpenFile", "x", GLib.Variant("a{sv}", {"directory": GLib.Variant("b", True)}))["mode"], "folder")
        save = portal.parse("SaveFile", "x", GLib.Variant("a{sv}", {"current_name": GLib.Variant("s", "../a/b.txt"),
                                                                 "current_file": GLib.Variant("ay", b"/home/u/old.txt\0")}))
        self.assertEqual((save["mode"], save["name"], save["file"]), ("save", "..ab.txt", "/home/u/old.txt"))
        many = portal.parse("SaveFiles", "x", GLib.Variant("a{sv}", {"files": GLib.Variant("aay", [b"one.txt\0", b"../two.txt\0"])}))
        self.assertEqual(many["files"], ["one.txt", "two.txt"])
        code, res = portal.results(many, [], True, ["/dest"], {}, -1).unpack()
        self.assertEqual(res["uris"], ["file:///dest/one.txt", "file:///dest/two.txt"])


@unittest.skipUnless(shutil.which("dbus-daemon") and shutil.which("gdbus"), "needs dbus-daemon and gdbus")
class PortalBusTest(unittest.TestCase):
    """the backend as xdg-desktop-portal's FileChooser, on a private session bus"""
    def setUp(self):
        self.home = tempfile.mkdtemp(prefix="filesd-test-")
        self.bus = subprocess.Popen(["dbus-daemon", "--session", "--nofork", "--print-address"], stdout=subprocess.PIPE, text=True)
        self.addr = self.bus.stdout.readline().strip()
        os.makedirs(os.path.join(self.home, ".config", "xdg-desktop-portal"))
        with open(os.path.join(self.home, ".config", "xdg-desktop-portal", "portals.conf"), "w") as f:
            f.write("[preferred]\ndefault=gtk\n")
        Backend.later = []
        self.b = Backend(self.home, {"DBUS_SESSION_BUS_ADDRESS": self.addr, "XDG_CURRENT_DESKTOP": "niri"})
        self.helpers = []

    def tearDown(self):
        self.b.close()
        for h in self.helpers:
            h.kill()
            h.wait()
        self.bus.kill()
        self.bus.wait()
        self.bus.stdout.close()
        shutil.rmtree(self.home)

    def gdbus(self, method, options="{}", handle="/org/freedesktop/portal/desktop/request/1_1/t"):
        return subprocess.Popen(["gdbus", "call", "--address", self.addr, "--dest", "org.freedesktop.impl.portal.desktop.quickshell",
                                 "--object-path", "/org/freedesktop/portal/desktop", "--timeout", "30",
                                 "--method", "org.freedesktop.impl.portal.FileChooser." + method, handle, "app", "", "A title", options],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def files(self):
        data = os.path.join(self.home, ".local/share")
        return (os.path.join(data, "dbus-1/services/org.freedesktop.impl.portal.desktop.quickshell.service"),
                os.path.join(data, "xdg-desktop-portal/portals/quickshell.portal"),
                os.path.join(self.home, ".config/xdg-desktop-portal/portals.conf"))

    def test_on_off_writes_and_removes(self):
        _, r = self.b.call("fileChooser", on=True)
        self.assertEqual((r["on"], r["problem"]), (True, ""))
        service, portal_file, conf = self.files()
        with open(service) as f:
            self.assertIn("files.sh --start", f.read())
        with open(portal_file) as f:
            self.assertIn("Interfaces=org.freedesktop.impl.portal.FileChooser", f.read())
        with open(conf) as f:
            self.assertIn("org.freedesktop.impl.portal.FileChooser=quickshell", f.read())
        _, r = self.b.call("fileChooser", on=False)
        self.assertFalse(r["on"])
        self.assertFalse(os.path.exists(service) or os.path.exists(portal_file))
        with open(conf) as f:
            self.assertEqual(f.read(), "[preferred]\ndefault=gtk\n")

    def test_someone_elses_files_stay(self):
        service, portal_file, _ = self.files()
        os.makedirs(os.path.dirname(portal_file))
        with open(portal_file, "w") as f:
            f.write("[portal]\nDBusName=other\n")
        self.b.call("fileChooser", on=True)
        self.b.call("fileChooser", on=False)
        with open(portal_file) as f:
            self.assertEqual(f.read(), "[portal]\nDBusName=other\n")

    def test_open_and_cancel(self):
        self.b.call("fileChooser", on=True)
        time.sleep(0.3)
        g = self.gdbus("OpenFile", "{'multiple': <true>, 'accept_label': <'_Pick'>}")
        ev = self.b.event("chooser")
        self.assertEqual((ev["mode"], ev["multiple"], ev["title"], ev["accept"]), ("open", True, "A title", "Pick"))
        self.assertTrue(self.b.call("chooserAck", chooser=ev["chooser"])[1]["found"])
        self.assertTrue(self.b.call("chooserDone", chooser=ev["chooser"], ok=True, paths=["/tmp/one.txt", "/tmp/t wo.txt"])[1]["found"])
        out = g.communicate(timeout=10)[0]
        self.assertIn("uint32 0", out)
        self.assertIn("file:///tmp/one.txt", out)
        self.assertIn("file:///tmp/t%20wo.txt", out)
        # answered twice: nothing there any more
        self.assertFalse(self.b.call("chooserDone", chooser=ev["chooser"], ok=True, paths=["/x"])[1]["found"])
        g = self.gdbus("SaveFile", "{'current_name': <'new.txt'>}")
        ev = self.b.event("chooser")
        self.assertEqual((ev["mode"], ev["name"]), ("save", "new.txt"))
        self.b.call("chooserAck", chooser=ev["chooser"])
        self.b.call("chooserDone", chooser=ev["chooser"], ok=False, paths=[])
        self.assertIn("uint32 1", g.communicate(timeout=10)[0])

    def test_request_closed_by_the_app(self):
        self.b.call("fileChooser", on=True)
        time.sleep(0.3)
        handle = "/org/freedesktop/portal/desktop/request/1_1/closeme"
        g = self.gdbus("OpenFile", handle=handle)
        ev = self.b.event("chooser")
        self.b.call("chooserAck", chooser=ev["chooser"])
        subprocess.run(["gdbus", "call", "--address", self.addr, "--dest", "org.freedesktop.impl.portal.desktop.quickshell",
                        "--object-path", handle, "--method", "org.freedesktop.impl.portal.Request.Close"], capture_output=True, timeout=10)
        self.assertEqual(self.b.event("chooserClosed")["chooser"], ev["chooser"])
        self.assertIn("uint32 1", g.communicate(timeout=10)[0])

    def test_no_window_passes_the_call_on(self):
        # a stand-in for GTK's backend on the private bus
        code = (
            "import gi\nfrom gi.repository import Gio, GLib\n"
            "xml='<node><interface name=\"org.freedesktop.impl.portal.FileChooser\"><method name=\"OpenFile\">"
            "<arg type=\"o\" direction=\"in\"/><arg type=\"s\" direction=\"in\"/><arg type=\"s\" direction=\"in\"/>"
            "<arg type=\"s\" direction=\"in\"/><arg type=\"a{sv}\" direction=\"in\"/>"
            "<arg type=\"u\" direction=\"out\"/><arg type=\"a{sv}\" direction=\"out\"/></method></interface></node>'\n"
            "info=Gio.DBusNodeInfo.new_for_xml(xml).interfaces[0]\n"
            "def call(c,s,p,i,m,a,inv): inv.return_value(GLib.Variant('(ua{sv})',(0,{'uris':GLib.Variant('as',['file:///from/gtk'])})))\n"
            "def got(c,n): c.register_object('/org/freedesktop/portal/desktop',info,call); print('up',flush=True)\n"
            "Gio.bus_own_name(Gio.BusType.SESSION,'org.freedesktop.impl.portal.desktop.gtk',0,got,None,None)\n"
            "GLib.MainLoop().run()\n")
        h = subprocess.Popen(["python3", "-I", "-c", code], stdout=subprocess.PIPE, text=True,
                             env={"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "DBUS_SESSION_BUS_ADDRESS": self.addr})
        self.helpers.append(h)
        self.assertEqual(h.stdout.readline().strip(), "up")
        self.b.call("fileChooser", on=True)
        time.sleep(0.3)
        g = self.gdbus("OpenFile")
        ev = self.b.event("chooser")
        # no chooserAck: after a moment the call goes to the next backend, and the UI is told to drop it
        self.assertEqual(self.b.event("chooserClosed", timeout=8)["chooser"], ev["chooser"])
        self.assertIn("file:///from/gtk", g.communicate(timeout=10)[0])
        self.assertFalse(self.b.call("chooserDone", chooser=ev["chooser"], ok=True, paths=["/late"])[1]["found"])
        h.stdout.close()


if __name__ == "__main__":
    unittest.main()
