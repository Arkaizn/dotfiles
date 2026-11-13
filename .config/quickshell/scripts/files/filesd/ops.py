"""File operations: copy / move / link, trash and restore, delete, rename, new
folder / file. Each long one runs in a thread of its own (a big copy never
takes a listing's worker), reports progress (at most ~10 lines a second), can
be paused and cancelled, and asks the UI when it can't decide:

    {"id": n, "type": "ask", "kind": "conflict", "src": item, "dst": item, "suggest": name}
    {"id": n, "type": "ask", "kind": "error", "path": p, "error": msg}
    {"id": n, "type": "ask", "kind": "notrash", "path": p, "error": msg}
answered with the "answer" op: {target: n, action, all?, name?}
    conflict: replace | skip | rename (name) | merge (two folders) | cancel
    error:    retry | skip | cancel        notrash: delete | skip | cancel
`all` keeps the answer for the rest of the job (per kind; for conflicts per
file / folder). Nothing is ever overwritten without a "replace", and a
replaced file is swapped in only once its copy is complete.

Names travel as str with surrogate escapes (non-UTF-8 bytes) and go to os.*
as they are; nothing here runs a shell.
"""
import datetime
import errno
import os
import stat
import threading
import time
import urllib.parse

from .proto import Fail, from_os, send

CHUNK = 1 << 20
ABORT = (errno.ENOSPC, errno.EDQUOT, errno.EROFS)     # no point asking: the whole job stops
# file systems that refuse these characters in names (Windows rules)
FAT_LIKE = ("vfat", "msdos", "exfat", "ntfs", "ntfs3", "fuseblk")
FAT_BAD = '<>:"\\|?*'


# ── Names ─────────────────────────────────────────────────────────────────────

def name_error(name, fs=""):
    """"" or why `name` can't be a file name here (the UI shows the same, FmPath.validName)"""
    if not isinstance(name, str) or name.strip() == "":
        return "Enter a name"
    if name in (".", ".."):
        return "“%s” isn't a file name" % name
    if "/" in name:
        return "A name can't contain “/”"
    if "\0" in name:
        return "A name can't contain a null character"
    if len(os.fsencode(name)) > 255:
        return "That name is too long"
    if fs in FAT_LIKE and (any(c in FAT_BAD for c in name) or name.endswith((" ", "."))):
        return "This drive doesn't allow %s or a space / dot at the end" % " ".join(FAT_BAD)
    return ""


def split_ext(name):
    """("photo", ".tar.gz") — the extension stays together when numbering"""
    if name.startswith(".") and name.count(".") == 1:
        return name, ""
    dot = name.rfind(".")
    if dot <= 0:
        return name, ""
    if name[:dot].lower().endswith(".tar"):
        dot = name[:dot].rfind(".")
    return name[:dot], name[dot:]


def free_name(folder, name, word=""):
    """a name not taken in folder: "x (2).txt" or, with word "copy", "x (copy).txt", "x (copy 2).txt" """
    base, ext = split_ext(name)
    n = 1 if word else 2
    while True:
        tag = (word if n == 1 else "%s %d" % (word, n)) if word else str(n)
        cand = "%s (%s)%s" % (base, tag, ext)
        if not os.path.lexists(os.path.join(folder, cand)):
            return cand
        n += 1


def uri(path):
    return "file://" + urllib.parse.quote(os.fsencode(path), safe="/")


def path_from_uri(u):
    if not u.startswith("file://"):
        return None
    rest = u[7:]
    if rest.startswith("localhost/"):
        rest = rest[9:]
    if not rest.startswith("/"):
        return None
    p = os.fsdecode(urllib.parse.unquote_to_bytes(rest))
    return None if "\0" in p else os.path.normpath(p)


# ── A job: progress, pause, cancel, questions ─────────────────────────────────

class Job:
    def __init__(self, rid):
        self.rid = rid
        self.cancelled = threading.Event()
        self.running = threading.Event()
        self.running.set()
        self.answered = threading.Event()
        self.answer = None
        self.remembered = {}
        self.done = self.total = self.bytes = self.total_bytes = 0
        self.current = ""
        self._last = 0.0

    # the UI's side
    def pause(self, on):
        if on:
            self.running.clear()
        else:
            self.running.set()

    def cancel(self):
        self.cancelled.set()
        self.running.set()
        self.answered.set()

    def give(self, answer):
        self.answer = answer
        self.answered.set()

    # the worker's side
    def check(self):
        """a pause waits here; a cancel ends the job"""
        if not self.running.is_set():
            self.progress(force=True)
            self.running.wait()
        if self.cancelled.is_set():
            raise Fail("cancelled", "cancelled")

    def progress(self, force=False):
        now = time.monotonic()
        if not force and now - self._last < 0.1:
            return
        self._last = now
        send({"id": self.rid, "type": "progress", "done": self.done, "total": self.total, "bytes": self.bytes,
              "totalBytes": self.total_bytes, "current": self.current, "paused": not self.running.is_set()})

    def ask(self, kind, key=None, **info):
        k = (kind, key)
        if k in self.remembered:
            return dict(self.remembered[k])
        self.answer = None
        self.answered.clear()
        send({"id": self.rid, "type": "ask", "kind": kind, **info})
        self.answered.wait()
        if self.cancelled.is_set():
            raise Fail("cancelled", "cancelled")
        a = self.answer if isinstance(self.answer, dict) else {"action": "cancel"}
        if a.get("action") == "cancel":
            self.cancelled.set()
            raise Fail("cancelled", "cancelled")
        if a.get("all") and a.get("action") != "rename":
            self.remembered[k] = {"action": a["action"]}
        return a

    def guard(self, path, work):
        """run work(); an OSError asks retry / skip (a full or read-only drive stops the job).
        True when done, False when skipped"""
        while True:
            self.check()
            try:
                work()
                return True
            except OSError as e:
                if e.errno in ABORT:
                    raise from_os(e)
                a = self.ask("error", path=path, error=str(from_os(e)))
                if a["action"] == "skip":
                    return False


def item(path):
    """what the conflict dialog shows of one side"""
    try:
        st = os.lstat(path)
    except OSError:
        return {"name": os.path.basename(path)}
    return {"name": os.path.basename(path), "dir": stat.S_ISDIR(st.st_mode), "size": st.st_size,
            "mtime": int(st.st_mtime), "link": stat.S_ISLNK(st.st_mode)}


# ── Copy / move / link ────────────────────────────────────────────────────────

def plan(sources, dest, mode):
    """(src, dst) pairs for copy / move / link of sources into dest"""
    if not os.path.isdir(dest):
        raise Fail("The target isn't a folder", "notdir")
    pairs = []
    for src in sources:
        if not os.path.lexists(src):
            raise Fail("“%s” doesn't exist (any more)" % os.path.basename(src), "missing")
        name = os.path.basename(src)
        if mode != "link" and os.path.isdir(src) and not os.path.islink(src) and \
                (dest == src or dest.startswith(src.rstrip("/") + "/")):
            raise Fail("“%s” can't go into itself" % name, "invalid")
        same = os.path.dirname(src) == dest
        if same and mode == "move":
            continue                                      # already there
        if same:
            name = free_name(dest, name, "copy" if mode == "copy" else "link")
        pairs.append((src, os.path.join(dest, name)))
    return pairs


def measure(job, pairs):
    """count files and bytes first, so the progress has a total"""
    for src, _ in pairs:
        stack = [src]
        while stack:
            job.check()
            p = stack.pop()
            try:
                st = os.lstat(p)
            except OSError:
                continue
            job.total += 1
            if stat.S_ISDIR(st.st_mode):
                try:
                    with os.scandir(p) as it:
                        stack.extend(e.path for e in it)
                except OSError:
                    pass
            elif stat.S_ISREG(st.st_mode):
                job.total_bytes += st.st_size
        job.progress()


def run_transfer(job, pairs, mode, explicit=False):
    """the job's work: pairs of exact paths. explicit (undo of a move): a taken
    target is an error, not a question. Returns {made: [{src, dst}], skipped}"""
    measure(job, pairs)
    made, skipped = [], [0]
    for src, dst in pairs:
        job.check()
        try:
            ok = transfer(job, src, dst, mode, explicit, skipped)
        except Fail as e:
            if e.code == "cancelled":
                return {"made": made, "skipped": skipped[0], "cancelled": True}
            raise
        if ok:
            made.append({"src": src, "dst": ok})
    job.progress(force=True)
    return {"made": made, "skipped": skipped[0]}


def same_dev(src, folder):
    try:
        return os.lstat(src).st_dev == os.stat(folder).st_dev
    except OSError:
        return False


def transfer(job, src, dst, mode, explicit, skipped):
    """src → dst (one entry, folders with what's in them). Returns the path it
    ended up at, or None when skipped"""
    job.current = os.path.basename(src)
    try:
        sst = os.lstat(src)
    except OSError as e:
        if job.guard(src, lambda: os.lstat(src)) is False:
            skipped[0] += 1
            return None
        sst = os.lstat(src)
    is_dir = stat.S_ISDIR(sst.st_mode)

    replace = False
    if os.path.lexists(dst):
        if os.path.exists(dst) and os.path.exists(src) and os.path.samefile(src, dst) and mode == "move":
            return dst
        if explicit:
            raise Fail("“%s” is in the way" % os.path.basename(dst), "exists")
        dst_dir = os.path.isdir(dst) and not os.path.islink(dst)
        both_dirs = is_dir and dst_dir and mode != "link"
        a = job.ask("conflict", key="dir" if both_dirs else "file", src=item(src), dst=item(dst),
                    suggest=free_name(os.path.dirname(dst), os.path.basename(dst)), folders=both_dirs)
        act = a["action"]
        if act == "skip":
            skipped[0] += 1
            job.done += _count(src)
            return None
        if act == "rename":
            new = a.get("name") or free_name(os.path.dirname(dst), os.path.basename(dst))
            if name_error(new) or os.path.lexists(os.path.join(os.path.dirname(dst), new)):
                new = free_name(os.path.dirname(dst), os.path.basename(dst))
            return transfer(job, src, os.path.join(os.path.dirname(dst), new), mode, explicit, skipped)
        if act == "merge" and both_dirs:
            return _merge(job, src, dst, mode, skipped)
        if act in ("replace", "merge"):
            if dst_dir != (is_dir and mode != "link"):
                # a folder never silently replaces a file or the other way round
                a = job.ask("error", path=dst, error="A file and a folder can't replace each other")
                skipped[0] += 1
                return None
            if dst_dir:
                return _merge(job, src, dst, mode, skipped)
            replace = True

    if mode == "link":
        def make():
            if replace:
                tmp = _tmp(dst, job)
                os.symlink(src, tmp)
                os.replace(tmp, dst)
            else:
                os.symlink(src, dst)
        if not job.guard(dst, make):
            skipped[0] += 1
            return None
        job.done += 1
        job.progress()
        return dst

    if mode == "move" and same_dev(src, os.path.dirname(dst)):
        size = _size(src)
        if not job.guard(src, lambda: os.replace(src, dst) if replace else _rename_new(src, dst)):
            skipped[0] += 1
            return None
        job.done += _count(dst)
        job.bytes += size
        job.progress()
        return dst

    # a copy (or a move across drives: copy, then the original goes)
    if is_dir:
        if not job.guard(dst, lambda: os.mkdir(dst, 0o700)):
            skipped[0] += 1
            return None
        job.done += 1
        complete = _copy_children(job, src, dst, mode, skipped)
        job.guard(dst, lambda: _copy_meta(sst, dst))
        if mode == "move" and complete:
            job.guard(src, lambda: os.rmdir(src))
        return dst
    ok = _copy_entry(job, src, dst, sst, replace)
    if not ok:
        skipped[0] += 1
        return None
    if mode == "move":
        job.guard(src, lambda: os.unlink(src))
    return dst


def _merge(job, src, dst, mode, skipped):
    job.done += 1
    complete = _copy_children(job, src, dst, mode, skipped)
    if mode == "move" and complete:
        job.guard(src, lambda: os.rmdir(src))
    return dst


def _copy_children(job, src, dst, mode, skipped):
    """True when every child got there (a move may then remove src)"""
    names = []
    job.guard(src, lambda: names.extend(sorted(os.listdir(src))))
    before = skipped[0]
    for n in names:
        job.check()
        transfer(job, os.path.join(src, n), os.path.join(dst, n), mode, False, skipped)
    return skipped[0] == before


def _copy_entry(job, src, dst, sst, replace):
    """one file / link / special file; written to a hidden temp name first"""
    if stat.S_ISLNK(sst.st_mode):
        target = os.readlink(src)

        def make():
            tmp = _tmp(dst, job)
            os.symlink(target, tmp)
            _place(tmp, dst, replace)
        ok = job.guard(dst, make)
    elif stat.S_ISREG(sst.st_mode):
        ok = _copy_file(job, src, dst, sst, replace)
    else:
        job.ask("error", path=src, error="Pipes, sockets and devices aren't copied")
        ok = False
    job.done += 1
    job.progress()
    return ok


def _copy_file(job, src, dst, sst, replace):
    tmp = _tmp(dst, job)
    copied = [0]

    def work():
        job.bytes -= copied[0]                         # a retry starts the file over
        copied[0] = 0
        fi = os.open(src, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
        try:
            fo = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
            try:
                fast = True
                while True:
                    job.check()
                    n = -1
                    if fast:
                        try:
                            n = os.copy_file_range(fi, fo, CHUNK)
                        except OSError as e:
                            # not between these two (another drive, a share, a file system without
                            # it): plain read + write from here on. A real error shows there too
                            if e.errno not in SOFT and e.errno not in (errno.EXDEV, errno.EBADF, errno.EIO):
                                raise
                            fast = False
                    if n < 0:
                        data = os.read(fi, CHUNK)
                        n = len(data)
                        view = memoryview(data)
                        while view:
                            view = view[os.write(fo, view):]
                    if n == 0:
                        break
                    copied[0] += n
                    job.bytes += n
                    job.progress()
                _soft(lambda: os.fchmod(fo, stat.S_IMODE(sst.st_mode)))
            finally:
                os.close(fo)
        finally:
            os.close(fi)
        _soft(lambda: os.utime(tmp, ns=(sst.st_atime_ns, sst.st_mtime_ns), follow_symlinks=False))
        _place(tmp, dst, replace)
    try:
        return job.guard(dst, work)
    finally:
        if os.path.lexists(tmp):
            try:
                os.unlink(tmp)
            except OSError:
                pass


def _tmp(dst, job):
    return os.path.join(os.path.dirname(dst), ".%s.%d.qsfm-part" % (os.path.basename(dst)[:200], job.rid))


def _place(tmp, dst, replace):
    if replace:
        os.replace(tmp, dst)
    else:
        _rename_new(tmp, dst)


def _rename_new(src, dst):
    """rename, but never over something (checked, then done: the gap is tiny)"""
    if os.path.lexists(dst):
        raise FileExistsError(errno.EEXIST, "exists", dst)
    os.rename(src, dst)


# a file system that can't take a mode or a time (a server through GVfs, FAT, some NAS):
# the copy itself is fine — keeping the mode / times is best effort, never a failed copy
SOFT = (errno.EOPNOTSUPP, errno.ENOSYS, errno.EPERM, errno.EACCES, errno.EINVAL, errno.ENOTTY)


def _soft(work):
    try:
        work()
    except OSError as e:
        if e.errno not in SOFT:
            raise


def _copy_meta(sst, dst):
    _soft(lambda: os.chmod(dst, stat.S_IMODE(sst.st_mode)))
    _soft(lambda: os.utime(dst, ns=(sst.st_atime_ns, sst.st_mtime_ns)))


def _count(path):
    n, stack = 0, [path]
    while stack:
        p = stack.pop()
        n += 1
        if os.path.isdir(p) and not os.path.islink(p):
            try:
                stack.extend(os.path.join(p, x) for x in os.listdir(p))
            except OSError:
                pass
    return n


def _size(path):
    total, stack = 0, [path]
    while stack:
        p = stack.pop()
        try:
            st = os.lstat(p)
        except OSError:
            continue
        if stat.S_ISDIR(st.st_mode):
            try:
                stack.extend(os.path.join(p, x) for x in os.listdir(p))
            except OSError:
                pass
        elif stat.S_ISREG(st.st_mode):
            total += st.st_size
    return total


# ── Delete ────────────────────────────────────────────────────────────────────

def run_delete(job, paths):
    for p in paths:
        job.total += _count(p)
    job.progress(force=True)
    deleted, skipped = [], 0
    for p in paths:
        job.check()
        if _delete(job, p):
            deleted.append(p)
        else:
            skipped += 1
    job.progress(force=True)
    return {"deleted": deleted, "skipped": skipped}


def _delete(job, p):
    job.current = os.path.basename(p)
    try:
        st = os.lstat(p)
    except FileNotFoundError:
        return True
    if stat.S_ISDIR(st.st_mode):
        names = []
        if not job.guard(p, lambda: names.extend(os.listdir(p))):
            return False
        ok = all([_delete(job, os.path.join(p, n)) for n in names])
        if not ok:
            return False
        done = job.guard(p, lambda: os.rmdir(p))
    else:
        done = job.guard(p, lambda: os.unlink(p))
    job.done += 1
    job.progress()
    return done


# ── Trash (freedesktop.org trash spec) ────────────────────────────────────────

def run_trash(job, paths, Gio):
    """Gio does the moving (home trash, or .Trash-<uid> on other drives). A drive
    without a trash asks whether to delete for good instead"""
    job.total = len(paths)
    trashed, deleted, skipped = [], [], 0
    for p in paths:
        job.check()
        job.current = os.path.basename(p)
        while True:
            try:
                Gio.File.new_for_path(p).trash(None)
                trashed.append(p)
                break
            except Exception as e:                    # GLib.Error
                msg = getattr(e, "message", str(e)).split("\n")[0]
                if "No such file" in msg or not os.path.lexists(p):
                    break
                a = job.ask("notrash", path=p, error=msg)
                if a["action"] == "delete":
                    if _delete(job, p):
                        deleted.append(p)
                    else:
                        skipped += 1
                    break
                if a["action"] == "skip":
                    skipped += 1
                    break
        job.done += 1
        job.progress()
    return {"trashed": trashed, "deleted": deleted, "skipped": skipped}


def trash_dirs(path):
    """the trash folders `path` can be in: (files dir, info dir, top dir or None for the home trash)"""
    data = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    home = os.path.join(data, "Trash")
    out = [(os.path.join(home, "files"), os.path.join(home, "info"), None)]
    top = os.path.dirname(path)
    while top != "/" and not os.path.ismount(top):
        top = os.path.dirname(top)
    uid = os.getuid()
    for t in (os.path.join(top, ".Trash", str(uid)), os.path.join(top, ".Trash-%d" % uid)):
        out.append((os.path.join(t, "files"), os.path.join(t, "info"), top))
    return out


def find_trashed(path):
    """the newest trash entry whose original place is `path`: (files path, info path) or None"""
    best = None
    for files, info, top in trash_dirs(path):
        try:
            names = os.listdir(info)
        except OSError:
            continue
        for n in names:
            if not n.endswith(".trashinfo"):
                continue
            ip = os.path.join(info, n)
            try:
                with open(ip, "rb") as f:
                    text = f.read(65536).decode("utf-8", "replace")
            except OSError:
                continue
            orig = when = None
            for line in text.splitlines():
                if line.startswith("Path="):
                    orig = os.fsdecode(urllib.parse.unquote_to_bytes(line[5:].strip()))
                elif line.startswith("DeletionDate="):
                    when = line[13:].strip()
            if orig is None:
                continue
            if top is not None and not orig.startswith("/"):
                orig = os.path.join(top, orig)
            if os.path.normpath(orig) != path:
                continue
            fp = os.path.join(files, n[:-len(".trashinfo")])
            if not os.path.lexists(fp):
                continue
            if best is None or (when or "") > best[2]:
                best = (fp, ip, when or "")
    return best[:2] if best else None


def run_restore(job, paths):
    """undo of a trash: each path back where it was (a taken place is asked about)"""
    job.total = len(paths)
    restored, missing, skipped = [], [], 0
    for p in paths:
        job.check()
        job.current = os.path.basename(p)
        found = find_trashed(p)
        if not found:
            missing.append(p)
            continue
        fp, ip = found
        target = p
        if os.path.lexists(target):
            a = job.ask("conflict", key="file", src=item(fp), dst=item(target),
                        suggest=free_name(os.path.dirname(target), os.path.basename(target)), folders=False, restore=True)
            if a["action"] != "rename":
                skipped += 1
                continue
            target = os.path.join(os.path.dirname(p), a.get("name") or free_name(os.path.dirname(p), os.path.basename(p)))

        def put_back():
            os.makedirs(os.path.dirname(target), exist_ok=True)
            if same_dev(fp, os.path.dirname(target)):
                _rename_new(fp, target)
            else:
                transfer(job, fp, target, "move", True, [0])
        if job.guard(target, put_back):
            try:
                os.unlink(ip)
            except OSError:
                pass
            restored.append(target)
        else:
            skipped += 1
        job.done += 1
        job.progress()
    return {"restored": restored, "missing": missing, "skipped": skipped}


def trashinfo_date():
    return datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")


# ── Small, quick ones (done in the pool) ──────────────────────────────────────

def rename(path, name, fs=""):
    err = name_error(name, fs)
    if err:
        raise Fail(err, "invalid")
    dst = os.path.join(os.path.dirname(path), name)
    if dst == path:
        return {"path": dst}
    if os.path.lexists(dst):
        # only the case of the name changes on a case-insensitive drive: the same file
        if not (os.path.exists(path) and os.path.samefile(path, dst)):
            raise Fail("“%s” already exists here" % name, "exists")
    try:
        os.rename(path, dst)
    except OSError as e:
        raise from_os(e)
    return {"path": dst, "old": path}


def mkdir(folder, name, fs=""):
    err = name_error(name, fs)
    if err:
        raise Fail(err, "invalid")
    p = os.path.join(folder, name)
    try:
        os.mkdir(p)
    except FileExistsError:
        raise Fail("“%s” already exists here" % name, "exists")
    except OSError as e:
        raise from_os(e)
    return {"path": p}


def newfile(folder, name, template=None, fs=""):
    err = name_error(name, fs)
    if err:
        raise Fail(err, "invalid")
    p = os.path.join(folder, name)
    src = None
    if template:
        try:
            src = os.open(template, os.O_RDONLY | os.O_CLOEXEC)
            if not stat.S_ISREG(os.fstat(src).st_mode):
                raise Fail("That template isn't a file", "invalid")
        except OSError as e:
            raise from_os(e)
    try:
        try:
            fd = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o644)
        except FileExistsError:
            raise Fail("“%s” already exists here" % name, "exists")
        except OSError as e:
            raise from_os(e)
        try:
            if src is not None:
                while True:
                    data = os.read(src, CHUNK)
                    if not data:
                        break
                    view = memoryview(data)
                    while view:
                        view = view[os.write(fd, view):]
        finally:
            os.close(fd)
    finally:
        if src is not None:
            os.close(src)
    return {"path": p}


def templates(GLib):
    """the files in ~/Templates (XDG_TEMPLATES_DIR), one level of subfolders as groups"""
    d = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_TEMPLATES)
    home = os.path.expanduser("~")
    if not d or os.path.normpath(d) == home or not os.path.isdir(d):
        return {"dir": "", "items": []}
    out = []
    for root, sub in ((d, ""), ):
        try:
            entries = sorted(os.scandir(root), key=lambda e: e.name.lower())
        except OSError:
            continue
        for e in entries:
            if e.name.startswith("."):
                continue
            try:
                if e.is_file():
                    out.append({"name": e.name, "path": e.path, "group": sub})
                elif e.is_dir():
                    for f in sorted(os.scandir(e.path), key=lambda x: x.name.lower()):
                        if f.is_file() and not f.name.startswith("."):
                            out.append({"name": f.name, "path": f.path, "group": e.name})
            except OSError:
                continue
            if len(out) >= 200:
                break
    return {"dir": d, "items": out}
