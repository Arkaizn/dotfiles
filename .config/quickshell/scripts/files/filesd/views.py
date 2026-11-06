"""The sidebar's views that aren't folders: Recent (GTK's recently-used.xbel,
shared with every GTK / Qt app), the trash (every trash folder of the
freedesktop spec: the home one and .Trash-<uid> on mounted drives), and the
custom actions (executable scripts in ~/.local/share/quickshell/files/scripts,
like Nautilus scripts: they get the selected paths as arguments).
"""
import datetime
import os
import shutil
import stat
import subprocess
import time
import urllib.parse
import xml.etree.ElementTree as ET

from . import listing, ops
from .proto import Fail

XBEL_NS = {"bookmark": "http://www.freedesktop.org/standards/desktop-bookmarks",
           "mime": "http://www.freedesktop.org/standards/shared-mime-info"}
RECENT_MAX = 200
XBEL_MAX = 8 << 20


def data_home():
    return os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")


def xbel_path():
    return os.path.join(data_home(), "recently-used.xbel")


# ── Recent ────────────────────────────────────────────────────────────────────

def recent():
    """the newest files in recently-used.xbel that still exist (local ones)"""
    try:
        if os.path.getsize(xbel_path()) > XBEL_MAX:
            return {"items": []}
        root = ET.parse(xbel_path()).getroot()
    except (OSError, ET.ParseError):
        return {"items": []}
    seen, out = set(), []
    entries = []
    for b in root.findall("bookmark"):
        href = b.get("href") or ""
        when = b.get("visited") or b.get("modified") or b.get("added") or ""
        entries.append((when, href))
    entries.sort(reverse=True)
    for when, href in entries:
        p = ops.path_from_uri(href)
        if not p or p in seen:
            continue
        seen.add(p)
        it = listing.item_for(p)
        if it is None:
            continue
        it["path"] = p
        it["loc"] = os.path.dirname(p)
        out.append(it)
        if len(out) >= RECENT_MAX:
            break
    return {"items": out}


def add_recent(path, mime):
    """note a file opened here, the way GTK does (other apps' Recent sees it)"""
    for k, v in XBEL_NS.items():
        ET.register_namespace(k, v)
    p = xbel_path()
    try:
        if os.path.exists(p) and os.path.getsize(p) > XBEL_MAX:
            return {}
        tree = ET.parse(p) if os.path.exists(p) else ET.ElementTree(ET.Element("xbel", {"version": "1.0"}))
    except ET.ParseError:
        return {}                                  # someone else's broken file: leave it alone
    root = tree.getroot()
    href = ops.uri(path)
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
    b = next((x for x in root.findall("bookmark") if x.get("href") == href), None)
    if b is None:
        b = ET.SubElement(root, "bookmark", {"href": href, "added": now})
    b.set("modified", now)
    b.set("visited", now)
    bm = "{%s}" % XBEL_NS["bookmark"]
    mi = "{%s}" % XBEL_NS["mime"]
    # (an element without children counts as false: compare with None)
    info = b.find("info")
    if info is None:
        info = ET.SubElement(b, "info")
    meta = info.find("metadata")
    if meta is None:
        meta = ET.SubElement(info, "metadata", {"owner": "http://freedesktop.org"})
    if meta.find(mi + "mime-type") is None:
        ET.SubElement(meta, mi + "mime-type", {"type": mime or "application/octet-stream"})
    apps = meta.find(bm + "applications")
    if apps is None:
        apps = ET.SubElement(meta, bm + "applications")
    app = next((a for a in apps.findall(bm + "application") if a.get("name") == "Files"), None)
    if app is None:
        app = ET.SubElement(apps, bm + "application", {"name": "Files", "exec": "'files.sh %u'", "count": "0"})
    app.set("modified", now)
    app.set("count", str(int(app.get("count") or 0) + 1))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + ".qsfm-tmp"
    tree.write(tmp, encoding="utf-8", xml_declaration=True)
    os.chmod(tmp, 0o600)
    os.replace(tmp, p)
    return {}


# ── Trash ─────────────────────────────────────────────────────────────────────

def _trash_dirs(Gio):
    """every trash folder: home, and .Trash-<uid> / .Trash/<uid> on mounted drives"""
    out = [(os.path.join(data_home(), "Trash"), None)]
    uid = os.getuid()
    for m in Gio.VolumeMonitor.get().get_mounts():
        top = m.get_root().get_path()
        if not top:
            continue
        for t in (os.path.join(top, ".Trash-%d" % uid), os.path.join(top, ".Trash", str(uid))):
            if os.path.isdir(os.path.join(t, "files")):
                out.append((t, top))
    return out


def trash_list(Gio):
    items = []
    for t, top in _trash_dirs(Gio):
        info_dir, files_dir = os.path.join(t, "info"), os.path.join(t, "files")
        try:
            names = os.listdir(info_dir)
        except OSError:
            continue
        for n in names:
            if not n.endswith(".trashinfo"):
                continue
            fp = os.path.join(files_dir, n[:-10])
            try:
                lst = os.lstat(fp)
            except OSError:
                continue
            orig, when = "", ""
            try:
                with open(os.path.join(info_dir, n), "rb") as f:
                    for line in f.read(65536).decode("utf-8", "replace").splitlines():
                        if line.startswith("Path="):
                            orig = os.fsdecode(urllib.parse.unquote_to_bytes(line[5:].strip()))
                        elif line.startswith("DeletionDate="):
                            when = line[13:].strip()
            except OSError:
                pass
            if top and orig and not orig.startswith("/"):
                orig = os.path.join(top, orig)
            it = listing.make_item(files_dir, n[:-10], lst)
            it.update({"name": os.path.basename(orig) or it["name"], "path": fp, "info": os.path.join(info_dir, n),
                       "orig": orig, "loc": os.path.dirname(orig), "deleted": when})
            items.append(it)
    return {"items": items}


def _in_trash(fp, info, Gio):
    """only entries of a real trash folder (never any path the UI names)"""
    for t, _ in _trash_dirs(Gio):
        if os.path.dirname(fp) == os.path.join(t, "files") and os.path.dirname(info) == os.path.join(t, "info") \
                and os.path.basename(info) == os.path.basename(fp) + ".trashinfo":
            return True
    return False


def trash_restore(job, entries, Gio):
    restored, skipped = [], 0
    job.total = len(entries)
    for e in entries:
        job.check()
        fp, info, orig = e["file"], e["info"], e["orig"]
        if not _in_trash(fp, info, Gio) or not orig.startswith("/"):
            skipped += 1
            continue
        target = orig
        if os.path.lexists(target):
            a = job.ask("conflict", key="file", src=ops.item(fp), dst=ops.item(target),
                        suggest=ops.free_name(os.path.dirname(target), os.path.basename(target)), folders=False, restore=True)
            if a["action"] != "rename":
                skipped += 1
                continue
            target = os.path.join(os.path.dirname(orig), a.get("name") or ops.free_name(os.path.dirname(orig), os.path.basename(orig)))

        def back():
            os.makedirs(os.path.dirname(target), exist_ok=True)
            if ops.same_dev(fp, os.path.dirname(target)):
                ops._rename_new(fp, target)
            else:
                ops.transfer(job, fp, target, "move", True, [0])
        if job.guard(target, back):
            try:
                os.unlink(info)
            except OSError:
                pass
            restored.append(target)
        else:
            skipped += 1
        job.done += 1
        job.progress()
    return {"restored": restored, "skipped": skipped}


def trash_delete(job, entries, Gio):
    """for good: the files and their info files"""
    paths = []
    for e in entries:
        if _in_trash(e["file"], e["info"], Gio):
            paths.append((e["file"], e["info"]))
    for fp, _ in paths:
        job.total += ops._count(fp)
    deleted = 0
    for fp, info in paths:
        job.check()
        if ops._delete(job, fp):
            try:
                os.unlink(info)
            except OSError:
                pass
            deleted += 1
    return {"deleted": deleted}


def trash_empty(job, Gio):
    entries = [{"file": it["path"], "info": it["info"]} for it in trash_list(Gio)["items"]]
    res = trash_delete(job, entries, Gio)
    # what's left in files/ without an info file (other programs' leftovers) stays
    return res


# ── Custom actions (scripts) ──────────────────────────────────────────────────

def scripts_dir():
    return os.path.join(data_home(), "quickshell", "files", "scripts")


def scripts():
    d = scripts_dir()
    out = []
    try:
        for e in sorted(os.scandir(d), key=lambda e: e.name.lower()):
            if e.name.startswith("."):
                continue
            try:
                st = e.stat()
            except OSError:
                continue
            if stat.S_ISREG(st.st_mode) and st.st_mode & 0o100 and st.st_uid == os.getuid() and not st.st_mode & 0o022:
                out.append({"name": e.name, "path": e.path})
    except OSError:
        pass
    return {"dir": d, "scripts": out}


def run_script(script, paths, cwd, env):
    """a script from the folder (yours, not writable by others) with the paths as arguments"""
    if os.path.dirname(script) != scripts_dir():
        raise Fail("Not one of your scripts", "denied")
    st = os.stat(script)
    if not (stat.S_ISREG(st.st_mode) and st.st_mode & 0o100 and st.st_uid == os.getuid() and not st.st_mode & 0o022):
        raise Fail("The script isn't executable, or others can change it", "denied")
    env = dict(env, NAUTILUS_SCRIPT_SELECTED_FILE_PATHS="\n".join(paths) + "\n", NAUTILUS_SCRIPT_CURRENT_URI=ops.uri(cwd))
    subprocess.Popen([script] + paths, cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
    return {}
