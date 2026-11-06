"""The sidebar's places: home + XDG folders, GTK bookmarks, mounted drives.

Bookmarks stay the flat list in ~/.config/gtk-3.0/bookmarks (GTK file dialogs
read it too). Changes to it, to user-dirs.dirs and to the mounts send a
"places" event; the UI asks again. Free space is looked up for local file
systems only: statvfs on a dead network share would hang.
"""
import os
import re
import urllib.parse

from gi.repository import Gio, GLib

from .proto import Fail, send

XDG = [
    ("Desktop", GLib.UserDirectory.DIRECTORY_DESKTOP, "desktop"),
    ("Documents", GLib.UserDirectory.DIRECTORY_DOCUMENTS, "documents"),
    ("Downloads", GLib.UserDirectory.DIRECTORY_DOWNLOAD, "downloads"),
    ("Music", GLib.UserDirectory.DIRECTORY_MUSIC, "music"),
    ("Pictures", GLib.UserDirectory.DIRECTORY_PICTURES, "pictures"),
    ("Videos", GLib.UserDirectory.DIRECTORY_VIDEOS, "videos"),
]
NETWORK_FS = {"nfs", "nfs4", "cifs", "smb3", "smbfs", "sshfs", "fuse.sshfs", "fuse.gvfsd-fuse",
              "fuse.rclone", "davfs", "fuse.davfs2", "9p", "afs", "ceph", "glusterfs"}


def config_home():
    return os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")


def bookmarks_file():
    return os.path.join(config_home(), "gtk-3.0", "bookmarks")


def fs_types():
    """mount point → file system type"""
    out = {}
    try:
        with open("/proc/self/mounts", "rb") as f:
            for line in f.read().splitlines():
                parts = line.split()
                if len(parts) >= 3:
                    # the kernel writes spaces etc. as octal escapes (\040)
                    raw = re.sub(rb"\\([0-7]{3})", lambda m: bytes([int(m.group(1), 8) & 0xFF]), parts[1])
                    out[raw.decode("utf-8", "surrogateescape")] = parts[2].decode("ascii", "replace")
    except OSError:
        pass
    return out


def local_fs(path, types):
    """is the file system holding `path` a local one (statvfs can't hang)?"""
    p = path
    while True:
        if p in types:
            return types[p] not in NETWORK_FS
        if p == "/":
            return True
        p = os.path.dirname(p)


def fs_type(path, types):
    """the file system type holding `path` ("" if unknown)"""
    p = path
    while True:
        if p in types:
            return types[p]
        if p == "/":
            return ""
        p = os.path.dirname(p)


def space(path):
    st = os.statvfs(path)
    return {"size": st.f_blocks * st.f_frsize, "free": st.f_bavail * st.f_frsize}


def read_bookmarks():
    out = []
    try:
        with open(bookmarks_file(), "rb") as f:
            data = f.read(1 << 20).decode("utf-8", "surrogateescape")
    except OSError:
        return out
    for line in data.splitlines():
        uri, _, label = line.strip().partition(" ")
        if not uri or len(out) >= 500:
            continue
        b = {"uri": uri, "label": label.strip()}
        if uri.startswith("file://"):
            path = urllib.parse.unquote(urllib.parse.urlsplit(uri).path, errors="surrogateescape")
            b["path"] = path
            b["name"] = b["label"] or os.path.basename(path.rstrip("/")) or "/"
            b["missing"] = not os.path.isdir(path)
        else:
            sp = urllib.parse.urlsplit(uri)
            last = os.path.basename(urllib.parse.unquote(sp.path).rstrip("/"))
            b["name"] = b["label"] or ((sp.hostname or uri) + (" › " + last if last else ""))
            b["remote"] = True
        out.append(b)
    return out


def edit_bookmarks(change):
    """change(lines) → lines: the GTK bookmarks file rewritten whole (atomically); lines are
    "uri[ label]" as GTK writes them, the ones we don't touch kept as they are"""
    path = bookmarks_file()
    try:
        with open(path, "rb") as f:
            lines = f.read(1 << 20).decode("utf-8", "surrogateescape").splitlines()
    except FileNotFoundError:
        lines = []
    lines = change([l for l in lines if l.strip()])
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".qsfm-tmp"
    with open(tmp, "wb") as f:
        f.write(("\n".join(lines) + ("\n" if lines else "")).encode("utf-8", "surrogateescape"))
    os.replace(tmp, path)
    return {}


def _uri_of(line):
    return line.strip().partition(" ")[0]


SERVER_SCHEMES = ("smb", "sftp", "ssh", "ftp", "ftps", "dav", "davs", "nfs", "afp")


def server_uri(uri):
    """a server address as a bookmark keeps it: one of the schemes, no spaces / newlines, never a password"""
    scheme = uri.split(":", 1)[0].lower()
    if scheme not in SERVER_SCHEMES or not uri.lower().startswith(scheme + "://") or len(uri) > 2048 \
            or any(c in uri for c in " \n\r\t\0"):
        raise Fail("Not a server address (smb://, sftp://, ftp://, dav://, nfs://)", "invalid")
    return re.sub(r"^([a-z][a-z0-9+.-]*://)([^@/]*?):[^@/]*@", r"\1\2@", uri, flags=re.I)


def uri_for_path(path, file_uri):
    """a folder's bookmark address: inside a mounted server (GVfs' FUSE folder) its server
    address, so the bookmark reconnects after a reboot; else file://"""
    gvfs = "/run/user/%d/gvfs/" % os.getuid()
    if path.startswith(gvfs):
        try:
            u = Gio.File.new_for_path(path).get_uri()
            if not u.startswith("file:"):
                return server_uri(u)
        except Exception:
            pass
    return file_uri(path)


def bookmark_add(uri, label):
    def change(lines):
        if any(_uri_of(l) == uri for l in lines):
            return lines
        return lines + [uri + (" " + label if label else "")]
    return edit_bookmarks(change)


def bookmark_remove(uri):
    return edit_bookmarks(lambda lines: [l for l in lines if _uri_of(l) != uri])


def bookmark_rename(uri, label):
    return edit_bookmarks(lambda lines: [(uri + (" " + label if label else "")) if _uri_of(l) == uri else l for l in lines])


def bookmark_order(uris):
    """the bookmarks in this order (the sidebar's drag); lines not named keep their place at the end"""
    def change(lines):
        by = {_uri_of(l): l for l in lines}
        first = [by[u] for u in uris if u in by]
        named = set(uris)
        return first + [l for l in lines if _uri_of(l) not in named]
    return edit_bookmarks(change)


def bookmark_move(uri, step):
    def change(lines):
        i = next((k for k, l in enumerate(lines) if _uri_of(l) == uri), -1)
        j = i + step
        if i < 0 or j < 0 or j >= len(lines):
            return lines
        lines[i], lines[j] = lines[j], lines[i]
        return lines
    return edit_bookmarks(change)


def _icon(gicon):
    return gicon.to_string() if gicon is not None else ""


def collect(volumes):
    """everything but free space (main thread: Gio's volume monitor lives here)"""
    home = os.path.expanduser("~")
    xdg = []
    for name, d, kind in XDG:
        p = GLib.get_user_special_dir(d)
        if p and os.path.normpath(p) != home and os.path.isdir(p):
            xdg.append({"name": os.path.basename(p) or name, "path": p, "kind": kind})
    mounts = []
    for m in volumes.get_mounts():
        if m.is_shadowed():
            continue
        root = m.get_root()
        mounts.append({
            "name": m.get_name(), "uri": root.get_uri(), "path": root.get_path(),
            "icon": _icon(m.get_symbolic_icon()), "canUnmount": m.can_unmount(), "canEject": m.can_eject(),
        })
    return {"home": home, "xdg": xdg, "bookmarks": read_bookmarks(), "mounts": mounts,
            "root": {"name": "Computer", "path": "/"}}


def add_space(result):
    """free space of / and each local mount (worker thread)"""
    types = fs_types()
    for m in [result["root"]] + result["mounts"]:
        p = m.get("path")
        if p and local_fs(p, types):
            try:
                m.update(space(p))
            except OSError:
                pass
    return result


class Watcher:
    """sends {"event": "places"} when any of the sources change"""
    def __init__(self, volumes):
        self.monitors = []
        self.timer = 0
        for p in (bookmarks_file(), os.path.join(config_home(), "user-dirs.dirs")):
            m = Gio.File.new_for_path(p).monitor_file(Gio.FileMonitorFlags.WATCH_MOVES, None)
            m.connect("changed", lambda *_: self.poke(reload_dirs=True))
            self.monitors.append(m)
        for sig in ("mount-added", "mount-removed", "mount-changed", "volume-added", "volume-removed", "volume-changed"):
            volumes.connect(sig, lambda *_: self.poke())

    def poke(self, reload_dirs=False):
        if reload_dirs:
            GLib.reload_user_special_dirs_cache()
        if not self.timer:
            self.timer = GLib.timeout_add(250, self._send)

    def _send(self):
        self.timer = 0
        send({"event": "places"})
        return False
