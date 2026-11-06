"""Compress and extract (jobs: progress, cancel, questions — ops.Job).

zip and tar.* go through Python's own zipfile / tarfile; 7z (and rar,
encrypted zips we write) through the 7z program, whose password prompt gets
the password typed into a pty — never on its command line, where `ps` shows it.
An archive is unpacked into a new folder named after it (never over anything),
and nothing inside may point outside that folder: absolute names, "..",
links out of it are refused.
"""
import os
import pty
import select
import shutil
import stat
import subprocess
import tarfile
import time
import zipfile

from . import ops
from .proto import Fail

FORMATS = ("zip", "tar.xz", "tar.gz", "tar.zst", "7z")
TAR_EXTS = (".tar", ".tar.gz", ".tgz", ".tar.xz", ".txz", ".tar.bz2", ".tbz2", ".tar.zst", ".tzst")
SEVEN = (".7z", ".rar", ".iso")


def kind_of(path):
    low = path.lower()
    if low.endswith(".zip") or low.endswith(".jar") or low.endswith(".apk"):
        return "zip"
    if low.endswith(TAR_EXTS):
        return "tar"
    if low.endswith(SEVEN):
        return "7z"
    return ""


def stem(name):
    low = name.lower()
    for ext in sorted(TAR_EXTS + (".zip", ".7z", ".rar", ".jar", ".apk"), key=len, reverse=True):
        if low.endswith(ext):
            return name[:-len(ext)] or name
    return os.path.splitext(name)[0] or name


def _safe_member(name):
    n = name.replace("\\", "/")
    return not (n.startswith("/") or n == ".." or n.startswith("../") or "/../" in n or n.endswith("/..") or "\0" in n)


def _pty_run(job, argv, password, cwd, ask=None):
    """argv in a pty; a password prompt gets the password (none yet: ask() asks the UI while
    the program waits at its prompt — it ignores SIGTERM there); cancel kills it. (code, last lines)"""
    pid, fd = pty.fork()
    if pid == 0:
        try:
            os.chdir(cwd)
            os.execvp(argv[0], argv)
        finally:
            os._exit(127)
    out, asked = b"", 0
    try:
        while True:
            if job.cancelled.is_set():
                os.kill(pid, 9)
                raise Fail("cancelled", "cancelled")
            r, _, _ = select.select([fd], [], [], 0.2)
            if fd in r:
                try:
                    chunk = os.read(fd, 4096)
                except OSError:
                    break
                if not chunk:
                    break
                out = (out + chunk)[-8192:]
                tail = out[-200:].lower()
                if b"password" in tail and tail.rstrip().endswith(b":") and asked < 3:
                    if password is None:
                        try:
                            password = ask() if ask else None
                        except Fail:
                            os.kill(pid, 9)
                            raise
                        if password is None:
                            os.kill(pid, 9)
                            raise Fail("needs a password", "denied")
                    os.write(fd, password.encode() + b"\n")
                    asked += 1
                    out += b"\n"
                m = [x for x in out.decode("utf-8", "replace").replace("\r", "\n").split("\n") if "%" in x]
                if m:
                    try:
                        job.done = int(m[-1].strip().split("%")[0].split()[-1])
                        job.total = 100
                        job.progress()
                    except (ValueError, IndexError):
                        pass
    finally:
        try:
            _, status = os.waitpid(pid, 0)
        except ChildProcessError:
            status = 0
        os.close(fd)
    lines = [x for x in out.decode("utf-8", "replace").replace("\r", "\n").split("\n") if x.strip()]
    return os.waitstatus_to_exitcode(status), lines[-3:]


def _need_password(job, path):
    a = job.ask("password", path=path, message="“%s” is encrypted" % os.path.basename(path), needPassword=True,
                needUser=False, needDomain=False, anonymous=False, canSave=False)
    return a.get("password") or ""


# ── Extract ───────────────────────────────────────────────────────────────────

def extract(job, path, dest, password=None):
    kind = kind_of(path)
    if not kind:
        raise Fail("Not an archive this can open (zip, tar, 7z, rar)", "unsupported")
    if not os.path.isdir(dest):
        raise Fail("The target isn't a folder", "notdir")
    name = stem(os.path.basename(path))
    out = os.path.join(dest, name if not os.path.lexists(os.path.join(dest, name)) else ops.free_name(dest, name))
    # a hidden folder first, renamed when everything is in (a failed one leaves nothing half)
    tmp = os.path.join(dest, ".%s.%d.qsfm-part" % (name[:150], job.rid))
    os.mkdir(tmp, 0o700)
    try:
        if kind == "zip":
            _unzip(job, path, tmp, password)
        elif kind == "tar":
            _untar(job, path, tmp)
        else:
            _un7z(job, path, tmp, password)
        _check_tree(tmp)
        # one folder inside with the archive's name: that's the result, not a folder in a folder
        inner = os.listdir(tmp)
        os.chmod(tmp, 0o755)
        if len(inner) == 1 and os.path.isdir(os.path.join(tmp, inner[0])) and not os.path.islink(os.path.join(tmp, inner[0])):
            target = os.path.join(dest, inner[0] if not os.path.lexists(os.path.join(dest, inner[0])) else ops.free_name(dest, inner[0]))
            os.rename(os.path.join(tmp, inner[0]), target)
            os.rmdir(tmp)
            return {"path": target}
        os.rename(tmp, out)
        return {"path": out}
    except BaseException:
        shutil.rmtree(tmp, ignore_errors=True)
        raise


def _check_tree(root):
    """nothing in it may lead out of it (a link to ../../.bashrc …)"""
    real = os.path.realpath(root)
    for d, dirs, files in os.walk(root):
        for n in dirs + files:
            p = os.path.join(d, n)
            if os.path.islink(p):
                t = os.path.realpath(p)
                if not (t == real or t.startswith(real + "/")):
                    os.unlink(p)


def _unzip(job, path, out, password):
    with zipfile.ZipFile(path) as z:
        infos = z.infolist()
        job.total = len(infos)
        job.total_bytes = sum(i.file_size for i in infos)
        if any(i.flag_bits & 1 for i in infos) and password is None:
            # AES zips (7z wrote them) Python can't read: 7z does
            password = _need_password(job, path)
        for i in infos:
            job.check()
            if not _safe_member(i.filename):
                raise Fail("The archive has a name that leads outside it: " + i.filename[:80], "invalid")
            job.current = i.filename
            try:
                z.extract(i, out, pwd=password.encode() if password else None)
            except RuntimeError as e:
                if "password" in str(e).lower():
                    raise Fail("Wrong password", "denied")
                raise Fail(str(e), "io")
            except NotImplementedError:
                return _un7z(job, path, out, password)
            # zipfile keeps no modes: an executable bit from the archive (unix entries)
            mode = (i.external_attr >> 16) & 0o777
            if mode and not i.is_dir():
                os.chmod(os.path.join(out, i.filename), mode & 0o755 | 0o600)
            job.done += 1
            job.bytes += i.file_size
            job.progress()


def _untar(job, path, out):
    with tarfile.open(path) as t:
        members = t.getmembers()
        job.total = len(members)
        job.total_bytes = sum(m.size for m in members)
        for m in members:
            job.check()
            job.current = m.name
            # "data": no absolute names, no "..", no links out, no devices, no setuid
            t.extract(m, out, filter="data")
            job.done += 1
            job.bytes += m.size
            job.progress()


def _un7z(job, path, out, password):
    if not shutil.which("7z"):
        raise Fail("7z isn't installed (sudo pacman -S 7zip)", "unsupported")
    # the names first: none may lead outside
    # (-pdummy: a listing never waits at a password prompt; header-encrypted ones just list nothing)
    r = subprocess.run(["7z", "l", "-slt", "-pdummy", "--", path], capture_output=True, text=True, timeout=120, stdin=subprocess.DEVNULL)
    for line in r.stdout.splitlines():
        if line.startswith("Path = ") and not _safe_member(line[7:]) and line[7:] != path:
            raise Fail("The archive has a name that leads outside it: " + line[7:87], "invalid")
    while True:
        holder = {}

        def ask():
            holder["pw"] = _need_password(job, path)
            return holder["pw"]
        code, tail = _pty_run(job, ["7z", "x", "-y", "-bsp1", "-o" + out, "--", path], password, out, ask)
        password = holder.get("pw", password)
        text = " ".join(tail).lower()
        if code != 0 and "wrong password" in text:
            password = None                       # asked again at the next prompt
            for n in os.listdir(out):
                p = os.path.join(out, n)
                shutil.rmtree(p) if os.path.isdir(p) and not os.path.islink(p) else os.unlink(p)
            continue
        if code != 0:
            raise Fail(tail[-1] if tail else "7z failed", "io")
        return


# ── Compress ──────────────────────────────────────────────────────────────────

def compress(job, paths, dest, name, fmt, password=None):
    if fmt not in FORMATS:
        raise Fail("format: " + ", ".join(FORMATS), "invalid")
    err = ops.name_error(name)
    if err:
        raise Fail(err, "invalid")
    target = os.path.join(dest, name + "." + fmt)
    if os.path.lexists(target):
        raise Fail("“%s” already exists here" % os.path.basename(target), "exists")
    base = os.path.dirname(paths[0])
    tmp = os.path.join(dest, ".%s.%d.qsfm-part" % (name[:150], job.rid))
    try:
        if password:
            _7z_add(job, tmp, paths, base, fmt, password)
        elif fmt == "zip":
            _zip(job, tmp, paths, base)
        elif fmt == "7z":
            _7z_add(job, tmp, paths, base, fmt, None)
        else:
            _tar(job, tmp, paths, base, fmt)
        ops._rename_new(tmp, target)
    except BaseException:
        if os.path.lexists(tmp):
            os.unlink(tmp)
        raise
    return {"path": target}


def _walk(paths):
    for p in paths:
        yield p
        if os.path.isdir(p) and not os.path.islink(p):
            for d, dirs, files in os.walk(p):
                dirs.sort()
                for n in sorted(dirs) + sorted(files):
                    yield os.path.join(d, n)


def _zip(job, tmp, paths, base):
    all_ = list(_walk(paths))
    job.total = len(all_)
    with zipfile.ZipFile(tmp, "x", zipfile.ZIP_DEFLATED) as z:
        for p in all_:
            job.check()
            job.current = os.path.basename(p)
            z.write(p, os.path.relpath(p, base))
            job.done += 1
            job.progress()


def _tar(job, tmp, paths, base, fmt):
    mode = {"tar.xz": "x:xz", "tar.gz": "x:gz", "tar.zst": "x:zst"}[fmt]
    job.total = len(paths)
    try:
        t = tarfile.open(tmp, mode)
    except tarfile.CompressionError:
        raise Fail("This Python can't write ." + fmt + " — pick another format", "unsupported")
    with t:
        for p in paths:
            job.check()
            job.current = os.path.basename(p)
            t.add(p, os.path.relpath(p, base))
            job.done += 1
            job.progress()


def _7z_add(job, tmp, paths, base, fmt, password):
    if not shutil.which("7z"):
        raise Fail("7z isn't installed (sudo pacman -S 7zip)", "unsupported")
    argv = ["7z", "a", "-t" + ("zip" if fmt == "zip" else "7z"), "-bsp1"]
    if password:
        argv.append("-p")                         # asks on the pty (twice)
        if fmt == "7z":
            argv.append("-mhe=on")                # names hidden too
        if fmt == "zip":
            argv.append("-mem=AES256")
    argv += ["--", tmp] + [os.path.relpath(p, base) for p in paths]
    code, tail = _pty_run(job, argv, password, base)
    if code != 0:
        raise Fail(tail[-1] if tail else "7z failed", "io")
