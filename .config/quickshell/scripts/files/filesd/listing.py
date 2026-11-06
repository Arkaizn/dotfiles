"""Folder listings: one item shape for list / info / watch, sorting, content types.

Local folders go through os.scandir in a worker thread (50 000 entries in
~0.4 s; Gio's enumerator takes ~1.4 s from Python). The sort here must give
the same order as modules/files/lib/FmSort.js, which places live changes into
the sorted list: keep the two in step (tests on both sides use the same names).
"""
import grp
import os
import pwd
import re
import stat

from gi.repository import Gio

SNIFF_MAX = 200           # files without an extension whose first bytes are read, per listing
_by_ext = {}              # extension → content type (the guess by name is ~6 µs; 50 000 add up)
_digits = re.compile(r"([0-9]+)")     # ASCII digits only, like FmSort.js
_users, _groups = {}, {}               # uid / gid → name (the Owner / Group columns)


def user_name(uid):
    n = _users.get(uid)
    if n is None:
        try:
            n = pwd.getpwuid(uid).pw_name
        except KeyError:
            n = str(uid)
        _users[uid] = n
    return n


def group_name(gid):
    n = _groups.get(gid)
    if n is None:
        try:
            n = grp.getgrgid(gid).gr_name
        except KeyError:
            n = str(gid)
        _groups[gid] = n
    return n


def is_hidden(name, hidden_names):
    # like GTK: dot files, backups ("x~") and the names in the folder's .hidden
    return name.startswith(".") or name.endswith("~") or name in hidden_names


def read_hidden(folder):
    try:
        with open(os.path.join(folder, ".hidden"), "rb") as f:
            data = f.read(1 << 20)
    except OSError:
        return frozenset()
    return frozenset(n for n in data.decode("utf-8", "surrogateescape").split("\n") if n)


def _special_type(mode):
    if stat.S_ISDIR(mode):
        return "inode/directory"
    if stat.S_ISFIFO(mode):
        return "inode/fifo"
    if stat.S_ISSOCK(mode):
        return "inode/socket"
    if stat.S_ISBLK(mode):
        return "inode/blockdevice"
    if stat.S_ISCHR(mode):
        return "inode/chardevice"
    return None


def _sniff(path):
    """the first bytes of a regular file (never follows a link, never waits on it)"""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_NOCTTY | os.O_CLOEXEC)
    except OSError:
        return None
    try:
        return os.read(fd, 4096)
    except OSError:
        return None
    finally:
        os.close(fd)


def content_type(name, st, path=None, budget=None):
    """by name (cached per extension); a file without one by its first bytes,
    while `budget` (a one-element list) lasts"""
    t = _special_type(st.st_mode)
    if t:
        return t
    dot = name.rfind(".")
    ext = name[dot:] if dot > 0 else ""
    # .tar.gz and friends are one type: keep the part before too
    if ext and name[:dot].lower().endswith(".tar"):
        ext = name[name[:dot].rfind("."):]
    if ext:
        t = _by_ext.get(ext)
        if t is None:
            t = _by_ext[ext] = Gio.content_type_guess(name, None)[0]
        return t
    if st.st_size == 0:
        return "application/x-zerosize"
    t, uncertain = Gio.content_type_guess(name, None)
    if uncertain and path and budget and budget[0] > 0 and stat.S_ISREG(st.st_mode):
        budget[0] -= 1
        data = _sniff(path)
        if data:
            t = Gio.content_type_guess(name, data)[0]
    return t


def make_item(folder, name, lst, hidden_names=frozenset(), budget=None):
    """an item from the entry's lstat; links show their target's kind and size"""
    path = os.path.join(folder, name)
    link = stat.S_ISLNK(lst.st_mode)
    st, broken, target = lst, False, None
    if link:
        try:
            target = os.readlink(path)
        except OSError:
            target = ""
        try:
            st = os.stat(path)
        except OSError:
            broken = True
    mode = st.st_mode
    is_dir = stat.S_ISDIR(mode)
    item = {
        "name": name, "dir": is_dir, "size": 0 if is_dir else st.st_size, "mtime": int(st.st_mtime),
        "type": "inode/symlink" if broken else content_type(name, st, path, budget),
        "hidden": is_hidden(name, hidden_names), "link": link, "mode": stat.S_IMODE(mode),
        "owner": user_name(lst.st_uid), "group": group_name(lst.st_gid),
    }
    if stat.S_ISREG(mode) and mode & 0o111:
        item["exec"] = True
    # a badge: you can't change it (a folder: can't add to it)
    if not os.access(path, os.W_OK):
        item["ro"] = True
    if link:
        item["target"] = target
        if broken:
            item["broken"] = True
    return item


def item_for(path):
    """the item of one path, or None when it's gone"""
    folder, name = os.path.split(path)
    try:
        lst = os.lstat(path)
    except OSError:
        return None
    return make_item(folder or "/", name or "/", lst, read_hidden(folder) if name else frozenset())


def scan(folder, cancelled):
    """every entry of a folder as items, unsorted; None when cancelled"""
    hidden_names = read_hidden(folder)
    budget = [SNIFF_MAX]
    out = []
    with os.scandir(folder) as it:
        for i, e in enumerate(it):
            if i % 1000 == 0 and cancelled():
                return None
            try:
                lst = e.stat(follow_symlinks=False)
            except OSError:
                continue            # gone between readdir and stat
            out.append(make_item(folder, e.name, lst, hidden_names, budget))
    return out


def dirs(folder, cancelled, limit):
    """the names of a folder's subfolders (links to folders too), sorted by name,
    for the address bar's completion: (names, more) — `more` when there were over `limit`"""
    out = []
    with os.scandir(folder) as it:
        for i, e in enumerate(it):
            if i % 1000 == 0 and cancelled():
                return None, False
            try:
                if not e.is_dir():          # follows links: a link to a folder completes too
                    continue
            except OSError:
                continue
            out.append(e.name)
            if len(out) > limit:
                break
    more = len(out) > limit
    out = sorted(out[:limit], key=lambda n: (name_key(n), n))
    return out, more


# ── Sorting (same rules as FmSort.js) ─────────────────────────────────────────

def name_key(name):
    """natural order, case-insensitive: "file2" before "file10" """
    parts = _digits.split(name.lower())
    key = []
    for i, p in enumerate(parts):
        if i % 2:
            d = p.lstrip("0") or "0"
            key.append((len(d), d))         # numbers by value, without int() on huge ones
        else:
            key.append((p,))
    return key


def sort_items(items, by="name", reverse=False, dirs_first=True):
    if by == "size":
        k = lambda r: (r["size"], name_key(r["name"]), r["name"])
    elif by == "mtime":
        k = lambda r: (r["mtime"], name_key(r["name"]), r["name"])
    elif by == "type":
        k = lambda r: (r["type"], name_key(r["name"]), r["name"])
    else:
        k = lambda r: (name_key(r["name"]), r["name"])
    items.sort(key=k, reverse=reverse)
    if dirs_first:
        # stable: folders keep their order among themselves, in front even when reversed
        items.sort(key=lambda r: not r["dir"])
    return items
