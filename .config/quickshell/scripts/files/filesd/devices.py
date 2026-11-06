"""Drives, servers and the network through Gio / GVfs (main thread: Gio's
volume monitor and mount operations live on the loop).

A mount that needs something (a LUKS passphrase, a server's user and
password, which of a few choices) asks the UI like an operation does:
    {"id": n, "type": "ask", "kind": "password", "message", "user", "domain",
     "needUser", "needDomain", "needPassword", "anonymous", "canSave"}
    {"id": n, "type": "ask", "kind": "question", "message", "choices": [...]}
answered with "answer" {target, action: ok | cancel, user?, domain?, password?,
anonymous?, remember?, choice?}. A remembered password goes to the keyring by
GVfs itself (Gio.PasswordSave.PERMANENTLY): never through argv or a file.

A mounted server is browsed through GVfs' FUSE folder (/run/user/<uid>/gvfs/…),
so listings, copies and the rest work on it like on any folder.
"""
import os
import re
import subprocess

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

from .proto import Fail, send

SCHEMES = ("smb", "sftp", "ssh", "ftp", "ftps", "dav", "davs", "nfs", "afp", "afc", "mtp", "gphoto2", "network", "google-drive")


def volume_id(v):
    return v.get_uuid() or v.get_identifier("unix-device") or v.get_identifier("class") or v.get_name()


def volumes(monitor):
    """drives / partitions / phones that aren't mounted yet (mounted ones are in places' mounts)"""
    out = []
    for v in monitor.get_volumes():
        if v.get_mount() is not None:
            continue
        icon = v.get_symbolic_icon()
        out.append({"id": volume_id(v), "name": v.get_name(), "canMount": v.can_mount(), "canEject": v.can_eject(),
                    "icon": icon.to_string() if icon else "",
                    "device": v.get_identifier("unix-device") or "",
                    "encrypted": "crypto" in (v.get_identifier("class") or "") or "luks" in (icon.to_string() if icon else "").lower()})
    return out


class Asker(Gio.MountOperation):
    """a MountOperation whose questions go to the UI as "ask" lines. The virtual methods
    are overridden (do_*), not the signals connected: GIO's own default handlers run after
    connected ones and answer "unhandled" at once — the mount then fails with "Password
    dialog cancelled" before anyone could type"""
    def __init__(self, rid):
        super().__init__()
        self.rid = rid

    def do_ask_password(self, message, user, domain, flags):
        send({"id": self.rid, "type": "ask", "kind": "password", "message": message or "",
              "user": user or "", "domain": domain or "",
              "needUser": bool(flags & Gio.AskPasswordFlags.NEED_USERNAME),
              "needDomain": bool(flags & Gio.AskPasswordFlags.NEED_DOMAIN),
              "needPassword": bool(flags & Gio.AskPasswordFlags.NEED_PASSWORD),
              "anonymous": bool(flags & Gio.AskPasswordFlags.ANONYMOUS_SUPPORTED),
              "canSave": bool(flags & Gio.AskPasswordFlags.SAVING_SUPPORTED)})

    def do_ask_question(self, message, choices):
        send({"id": self.rid, "type": "ask", "kind": "question", "message": message or "", "choices": list(choices)})

    def do_show_processes(self, message, pids, choices):
        # "still in use by …": the UI gets the question with the choices (force / cancel)
        send({"id": self.rid, "type": "ask", "kind": "question", "message": message or "", "choices": list(choices)})

    def give(self, a):
        if a.get("action") == "cancel":
            self.reply(Gio.MountOperationResult.ABORTED)
            return
        if "choice" in a:
            self.set_choice(int(a["choice"]))
        if a.get("anonymous"):
            self.set_anonymous(True)
        if isinstance(a.get("user"), str):
            self.set_username(a["user"])
        if isinstance(a.get("domain"), str):
            self.set_domain(a["domain"])
        if isinstance(a.get("password"), str):
            self.set_password(a["password"])
        self.set_password_save(Gio.PasswordSave.PERMANENTLY if a.get("remember") else Gio.PasswordSave.NEVER)
        self.reply(Gio.MountOperationResult.HANDLED)


def _message(e):
    return e.message.split("\n")[0] if hasattr(e, "message") else str(e)


def mount_volume(monitor, vid, rid, asks, done):
    v = next((x for x in monitor.get_volumes() if volume_id(x) == vid), None)
    if v is None:
        raise Fail("That drive isn't there any more", "missing")
    op = Asker(rid)
    asks[rid] = op

    def cb(vol, res):
        asks.pop(rid, None)
        try:
            vol.mount_finish(res)
            m = vol.get_mount()
            done({"path": m.get_root().get_path() if m else None, "name": vol.get_name()})
        except GLib.Error as e:
            done(None, Fail(_message(e), "cancelled" if e.matches(Gio.io_error_quark(), Gio.IOErrorEnum.FAILED_HANDLED) else "io"))
    v.mount(Gio.MountMountFlags.NONE, op, None, cb)


def _mount_for(monitor, uri):
    for m in monitor.get_mounts():
        if m.get_root().get_uri() == uri:
            return m
    return None


def unmount(monitor, uri, eject, rid, asks, done):
    m = _mount_for(monitor, uri)
    if m is None:
        raise Fail("That isn't mounted (any more)", "missing")
    op = Asker(rid)
    asks[rid] = op
    loop = ""
    vol = m.get_volume()
    if vol is not None:
        dev = vol.get_identifier("unix-device") or ""
        if re.match(r"^/dev/loop\d+$", dev):
            loop = dev

    def cb(obj, res):
        asks.pop(rid, None)
        try:
            (obj.eject_with_operation_finish if eject else obj.unmount_with_operation_finish)(res)
        except GLib.Error as e:
            done(None, Fail(_message(e), "io"))
            return
        if loop:
            # a disk image we set up (mountImage): the loop device goes too
            subprocess.run(["udisksctl", "loop-delete", "--no-user-interaction", "-b", loop], capture_output=True, timeout=20)
        done({})
    if eject and m.can_eject():
        m.eject_with_operation(Gio.MountUnmountFlags.NONE, op, None, cb)
    else:
        m.unmount_with_operation(Gio.MountUnmountFlags.NONE, op, None, cb)


def connect(uri, rid, asks, done):
    """a server (smb://, sftp://, …): mounted through GVfs; answers its FUSE folder"""
    scheme = uri.split(":", 1)[0].lower()
    if scheme not in SCHEMES or len(uri) > 2048 or "\0" in uri or "\n" in uri:
        raise Fail("Not a server address (smb://, sftp://, ftp://, dav://, nfs://)", "invalid")
    f = Gio.File.new_for_uri(uri)
    op = Asker(rid)
    asks[rid] = op

    def finish():
        p = f.get_path()
        if not p:
            done(None, Fail("Mounted, but GVfs' folder for it is missing (is gvfsd-fuse running?)", "unsupported"))
            return
        done({"path": p, "uri": uri})

    def cb(obj, res):
        asks.pop(rid, None)
        try:
            obj.mount_enclosing_volume_finish(res)
        except GLib.Error as e:
            if not e.matches(Gio.io_error_quark(), Gio.IOErrorEnum.ALREADY_MOUNTED):
                done(None, Fail(_message(e), "cancelled" if e.matches(Gio.io_error_quark(), Gio.IOErrorEnum.FAILED_HANDLED) else "io"))
                return
        finish()
    f.mount_enclosing_volume(Gio.MountMountFlags.NONE, op, None, cb)


def network(done):
    """what's on the network (network:/// — GVfs' dns-sd / wsdd / smb browsing)"""
    root = Gio.File.new_for_uri("network:///")
    attrs = "standard::display-name,standard::target-uri,standard::symbolic-icon,standard::name"

    def got(obj, res):
        try:
            en = obj.enumerate_children_finish(res)
        except GLib.Error as e:
            done(None, Fail(_message(e) or "Network browsing isn't available (gvfs-dnssd / gvfs-wsdd / gvfs-smb)", "unsupported"))
            return
        # (an enumerator made async must be read async too)
        def page(en, res):
            try:
                infos = en.next_files_finish(res)
            except GLib.Error as e:
                done(None, Fail(_message(e), "io"))
                return
            out = []
            for info in infos:
                target = info.get_attribute_string("standard::target-uri") or ""
                icon = info.get_symbolic_icon()
                out.append({"name": info.get_display_name(), "uri": target or root.get_child(info.get_name()).get_uri(),
                            "icon": icon.to_string() if icon else ""})
            en.close_async(GLib.PRIORITY_DEFAULT, None, None)
            done({"items": out})
        en.next_files_async(500, GLib.PRIORITY_DEFAULT, None, page)
    root.enumerate_children_async(attrs, Gio.FileQueryInfoFlags.NONE, GLib.PRIORITY_DEFAULT, None, got)


def mount_image(path):
    """an .iso / .img read-only through udisks (no root: udisks' own rules); answers where it went"""
    try:
        r = subprocess.run(["udisksctl", "loop-setup", "--no-user-interaction", "-r", "-f", path],
                           capture_output=True, text=True, timeout=30)
    except FileNotFoundError:
        raise Fail("udisksctl isn't installed (udisks2)", "unsupported")
    m = re.search(r"(/dev/loop\d+)", r.stdout)
    if r.returncode != 0 or not m:
        raise Fail((r.stderr.strip().splitlines() or ["couldn't set it up"])[-1], "io")
    dev = m.group(1)
    r = subprocess.run(["udisksctl", "mount", "--no-user-interaction", "-b", dev], capture_output=True, text=True, timeout=30)
    at = re.search(r" at (/.+?)\.?$", r.stdout.strip())
    if r.returncode != 0 or not at:
        subprocess.run(["udisksctl", "loop-delete", "--no-user-interaction", "-b", dev], capture_output=True, timeout=20)
        raise Fail((r.stderr.strip().splitlines() or ["couldn't mount it"])[-1], "io")
    return {"path": at.group(1), "device": dev}
