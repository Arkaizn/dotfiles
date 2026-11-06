"""What the file manager tells about files: properties, folder sizes, item
counts, the apps for a type (open with, the default), what the quick preview
shows. Owner changes go through pkexec (the shell's polkit agent asks).
"""
import datetime
import grp
import hashlib
import os
import pwd
import shutil
import stat
import subprocess

from .proto import Fail, from_os

TEXT_MAX = 300_000            # bytes of a text file the preview shows
PREVIEW_IMAGES = ("image/png", "image/jpeg", "image/gif", "image/webp", "image/bmp", "image/svg+xml", "image/tiff", "image/avif")
TEXT_LIKE = ("application/json", "application/xml", "application/x-yaml", "application/javascript", "application/x-shellscript",
             "application/toml", "application/x-desktop", "application/sql", "application/x-php", "application/x-perl")


def _user(uid):
    try:
        return pwd.getpwuid(uid).pw_name
    except KeyError:
        return str(uid)


def _group(gid):
    try:
        return grp.getgrgid(gid).gr_name
    except KeyError:
        return str(gid)


def props(path, item, GdkPixbuf):
    """one file's properties (item: listing's item for it)"""
    try:
        lst = os.lstat(path)
    except OSError as e:
        raise from_os(e)
    out = dict(item or {})
    out["mime"] = out.pop("type", "")          # "type" is the protocol's
    out.update({
        "path": path, "owner": _user(lst.st_uid), "group": _group(lst.st_gid), "mine": lst.st_uid == os.getuid(),
        "atime": int(lst.st_atime), "ctime": int(lst.st_ctime), "lmode": stat.S_IMODE(lst.st_mode),
        "canWrite": os.access(path, os.W_OK),
    })
    if out["mime"].startswith("image/"):
        try:
            fmt, w, h = GdkPixbuf.Pixbuf.get_file_info(path)
            if fmt is not None:
                out["width"], out["height"] = w, h
        except Exception:  # noqa: BLE001
            pass
    return out


def du(job, paths):
    """size of everything below (apparent bytes and on disk), files and folders; hard links counted once"""
    seen = set()
    size = disk = files = dirs = 0
    stack = list(paths)
    while stack:
        job.check()
        p = stack.pop()
        try:
            st = os.lstat(p)
        except OSError:
            continue
        if stat.S_ISDIR(st.st_mode):
            dirs += 1
            try:
                with os.scandir(p) as it:
                    stack.extend(e.path for e in it)
            except OSError:
                pass
        else:
            files += 1
            if st.st_nlink > 1:
                key = (st.st_dev, st.st_ino)
                if key in seen:
                    continue
                seen.add(key)
            size += st.st_size
            disk += st.st_blocks * 512
        if (files + dirs) % 500 == 0:
            job.bytes, job.done = size, files
            job.progress()
    return {"size": size, "disk": disk, "files": files, "dirs": dirs}


def counts(folder, names, hidden, cancelled):
    """how many items each subfolder holds (as the view would show them; at most 100 000 each)"""
    out = {}
    for n in names:
        if cancelled():
            break
        try:
            with os.scandir(os.path.join(folder, n)) as it:
                c = 0
                for e in it:
                    if hidden or not e.name.startswith("."):
                        c += 1
                        if c >= 100000:
                            break
            out[n] = c
        except OSError:
            out[n] = -1
    return {"counts": out}


def preview(path, mime, Gio):
    """what the quick preview shows: an image, PDF pages, text — else "other" (open it)"""
    try:
        st = os.stat(path)
    except OSError as e:
        raise from_os(e)
    out = {"kind": "other", "path": path, "name": os.path.basename(path), "mime": mime, "size": st.st_size,
           "pages": [], "pageCount": 0, "text": ""}
    if not stat.S_ISREG(st.st_mode):
        return out
    if mime in PREVIEW_IMAGES:
        out["kind"] = "image"
    elif mime == "application/pdf":
        from qsbackend import pdfview
        cache = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "quickshell", "files", "preview")
        key = hashlib.sha1(os.fsencode(path) + b"\0" + str(st.st_mtime_ns).encode()).hexdigest()
        base = os.path.join(cache, key)
        os.makedirs(base, mode=0o700, exist_ok=True)
        os.chmod(cache, 0o700)
        try:
            out.update(kind="pdf", **pdfview.render(path, base))
        except pdfview.ViewError as e:
            raise Fail(str(e), "unsupported")
    elif mime.startswith("text/") or mime in TEXT_LIKE or (st.st_size == 0):
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
            try:
                data = os.read(fd, TEXT_MAX + 1)
            finally:
                os.close(fd)
        except OSError as e:
            raise from_os(e)
        if b"\0" in data[:8192]:
            return out                                  # binary after all
        out.update(kind="text", text=data[:TEXT_MAX].decode("utf-8", "replace"), truncated=len(data) > TEXT_MAX)
    return out


def all_apps(Gio):
    """every app shown in menus (Open with → all apps)"""
    out = []
    for a in Gio.AppInfo.get_all():
        if not a.should_show() or not a.get_id():
            continue
        icon = a.get_icon()
        out.append({"id": a.get_id(), "name": a.get_display_name() or a.get_id(), "icon": icon.to_string() if icon else ""})
    out.sort(key=lambda x: x["name"].lower())
    return {"apps": out}


def apps_for(mime, Gio):
    """the apps that open `mime` (recommended first), and which is the default"""
    default = Gio.AppInfo.get_default_for_type(mime, False)
    did = default.get_id() if default else ""
    seen, out = set(), []
    for a in list(Gio.AppInfo.get_recommended_for_type(mime)) + list(Gio.AppInfo.get_all_for_type(mime)):
        i = a.get_id()
        if not i or i in seen or not a.should_show():
            continue
        seen.add(i)
        icon = a.get_icon()
        out.append({"id": i, "name": a.get_display_name() or i, "icon": icon.to_string() if icon else "", "default": i == did})
    return {"mime": mime, "apps": out, "default": did,
            "description": Gio.content_type_get_description(mime) if mime else ""}


def launch_with(paths, app_id, Gio, ctx):
    app = Gio.DesktopAppInfo.new(app_id)
    if app is None:
        raise Fail("That app isn't installed (any more)", "missing")
    files = [Gio.File.new_for_path(p) for p in paths]
    if len(files) > 1 and not app.supports_files() and not app.supports_uris():
        files = files[:1]
    app.launch(files, ctx)


def set_default(mime, app_id, Gio):
    """the default app for one type; mimeapps.list is backed up first (like Settings → Default apps)"""
    app = Gio.DesktopAppInfo.new(app_id)
    if app is None:
        raise Fail("That app isn't installed (any more)", "missing")
    conf = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    src = os.path.join(conf, "mimeapps.list")
    if os.path.exists(src):
        state = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
        bdir = os.path.join(state, "quickshell", "backups")
        os.makedirs(bdir, exist_ok=True)
        shutil.copy2(src, os.path.join(bdir, "mimeapps.list." + datetime.datetime.now().strftime("%Y%m%d-%H%M%S")))
    app.set_as_default_for_type(mime)
    return {"default": app_id}


def chmod(path, mode):
    st = os.lstat(path)
    if stat.S_ISLNK(st.st_mode):
        raise Fail("A link's own permissions can't be changed", "unsupported")
    if st.st_uid != os.getuid():
        raise Fail("Only the owner can change the permissions", "denied")
    os.chmod(path, mode & 0o7777)
    return {"mode": mode & 0o7777}


def chown(path, owner, group, recursive):
    """as root through pkexec: the polkit agent (the shell's) asks for the password"""
    if not shutil.which("pkexec"):
        raise Fail("pkexec isn't installed", "unsupported")
    for n in (owner, group):
        if not n or not all(c.isalnum() or c in "._-" for c in n) or n.startswith("-"):
            raise Fail("Not a user / group name: " + str(n), "invalid")
    try:
        pwd.getpwnam(owner)
        grp.getgrnam(group)
    except KeyError:
        raise Fail("No such user or group", "invalid")
    argv = ["pkexec", "chown"] + (["-R"] if recursive else []) + ["--", owner + ":" + group, path]
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=300, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        raise Fail("Nobody answered the password prompt", "cancelled")
    if r.returncode == 126:
        raise Fail("Not allowed (the password prompt was cancelled)", "denied")
    if r.returncode == 127:
        raise Fail("No password prompt: is the shell (its polkit agent) running?", "unsupported")
    if r.returncode != 0:
        raise Fail((r.stderr.strip().splitlines() or ["chown failed"])[-1], "io")
    return {"owner": owner, "group": group}
