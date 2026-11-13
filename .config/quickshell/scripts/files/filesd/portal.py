"""Other apps' Open / Save dialogs: a backend for xdg-desktop-portal's
FileChooser (org.freedesktop.impl.portal.FileChooser), shown as a Files window.

Owned only while the file manager says so (Settings → Files → "Open / Save
dialogs of other apps"). A call becomes an event for the UI:
    {"event": "chooser", "chooser": n, "mode": open | save | folder | saveFiles,
     "multiple", "title", "accept", "folder", "name", "file", "files": [names],
     "filters": [{"name", "globs": [...], "mimes": [...]}], "filter": index | -1,
     "choices": [{"id", "label", "options": [{"id", "label"}], "value"}]}
    {"event": "chooserClosed", "chooser": n}       (the app took its request back)
and the UI answers with the ops
    chooserAck  {chooser}                              "the window is up"
    chooserDone {chooser, ok, paths, choices, filter}  → the reply to the app
An app must never be left without a dialog: no chooserAck within ACK_S seconds
(the UI is broken, or mid-reload) hands the same call to the next backend
(what the portal configuration named before us, then GTK's, then GNOME's).

Files outside the config, written while it's on and removed when off — each
carries MARK, and a file without it (someone else's) is never touched:
    $XDG_DATA_HOME/dbus-1/services/<NAME>.service        starts Files on a call
    $XDG_DATA_HOME/xdg-desktop-portal/portals/quickshell.portal
    $XDG_CONFIG_HOME/xdg-desktop-portal/<the file in effect>   one line:
        org.freedesktop.impl.portal.FileChooser=quickshell
xdg-desktop-portal reads these when it starts (the user restarts it).

Nothing a request carries is run or trusted: texts are capped plain text,
filters are patterns, paths are only ever shown.
"""
import os

from gi.repository import Gio, GLib

from .proto import send

NAME = "org.freedesktop.impl.portal.desktop.quickshell"
PATH = "/org/freedesktop/portal/desktop"
IFACE = "org.freedesktop.impl.portal.FileChooser"
REQUEST = "org.freedesktop.impl.portal.Request"
KEY = "org.freedesktop.impl.portal.FileChooser"
MARK = "# quickshell files (Settings → Files → Open / Save dialogs of other apps)"
PREV = "# quickshell files: before ="
ACK_S = 3
MAX_TEXT = 200
BUILTIN = ("gtk", "gnome", "kde")

XML = """<node>
  <interface name="org.freedesktop.impl.portal.FileChooser">
    <method name="OpenFile">
      <arg type="o" name="handle" direction="in"/><arg type="s" name="app_id" direction="in"/>
      <arg type="s" name="parent_window" direction="in"/><arg type="s" name="title" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="u" name="response" direction="out"/><arg type="a{sv}" name="results" direction="out"/>
    </method>
    <method name="SaveFile">
      <arg type="o" name="handle" direction="in"/><arg type="s" name="app_id" direction="in"/>
      <arg type="s" name="parent_window" direction="in"/><arg type="s" name="title" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="u" name="response" direction="out"/><arg type="a{sv}" name="results" direction="out"/>
    </method>
    <method name="SaveFiles">
      <arg type="o" name="handle" direction="in"/><arg type="s" name="app_id" direction="in"/>
      <arg type="s" name="parent_window" direction="in"/><arg type="s" name="title" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="u" name="response" direction="out"/><arg type="a{sv}" name="results" direction="out"/>
    </method>
  </interface>
  <interface name="org.freedesktop.impl.portal.Request">
    <method name="Close"/>
  </interface>
</node>"""


def _text(v, cap=MAX_TEXT):
    return v.replace("\n", " ").replace("\0", "")[:cap] if isinstance(v, str) else ""


def _bytestring(options, key):
    """an "ay" option (a path, zero-terminated) as a str, "" when it isn't there / isn't one"""
    v = options.lookup_value(key, GLib.VariantType.new("ay"))
    if v is None:
        return ""
    raw = bytes(v.get_data_as_bytes().get_data() or b"").split(b"\0", 1)[0]
    return os.fsdecode(raw) if raw else ""


def _uri(path):
    return Gio.File.new_for_path(path).get_uri()


def parse(method, title, options):
    """the request as the UI gets it (see the header); `options` an a{sv} variant"""
    o = options.unpack() if options is not None else {}

    def flag(k):
        return o.get(k) is True

    filters = []
    for f in (o.get("filters") or [])[:100]:
        try:
            name, rules = f
            globs = [_text(p, 100) for kind, p in rules if kind == 0][:50]
            mimes = [_text(p, 100) for kind, p in rules if kind == 1][:50]
            filters.append({"name": _text(name), "globs": [g for g in globs if g], "mimes": [m for m in mimes if m]})
        except (TypeError, ValueError):
            continue
    current = -1
    cf = o.get("current_filter")
    if cf:
        current = next((i for i, f in enumerate(filters) if f["name"] == _text(cf[0])), -1)
    choices = []
    for c in (o.get("choices") or [])[:20]:
        try:
            cid, label, opts, value = c
            choices.append({"id": _text(cid), "label": _text(label),
                            "options": [{"id": _text(a), "label": _text(b)} for a, b in opts][:50], "value": _text(value)})
        except (TypeError, ValueError):
            continue
    folder = _bytestring(options, "current_folder") if options is not None else ""
    if not folder.startswith("/"):
        folder = ""
    req = {"mode": "open", "multiple": flag("multiple"), "title": _text(title), "accept": _text(o.get("accept_label")).replace("_", ""),
           "folder": os.path.normpath(folder) if folder else "", "name": "", "file": "", "files": [],
           "filters": filters, "filter": current, "choices": choices}
    if method == "OpenFile":
        if flag("directory"):
            req["mode"] = "folder"
    elif method == "SaveFile":
        req["mode"] = "save"
        req["multiple"] = False
        name = o.get("current_name")
        req["name"] = _text(name, 255).replace("/", "") if isinstance(name, str) else ""
        f = _bytestring(options, "current_file")
        if f.startswith("/"):
            req["file"] = os.path.normpath(f)
    else:
        req["mode"] = "saveFiles"
        req["multiple"] = False
        v = options.lookup_value("files", GLib.VariantType.new("aay")) if options is not None else None
        names = []
        for i in range(min(v.n_children(), 1000) if v is not None else 0):
            raw = bytes(v.get_child_value(i).get_data_as_bytes().get_data() or b"").split(b"\0", 1)[0]
            n = os.path.basename(os.fsdecode(raw))
            if n and n not in (".", ".."):
                names.append(n)
        req["files"] = names
    return req


def results(req, raw_filters, ok, paths, choices, flt):
    """(response, a{sv}) for the app. response: 0 = chosen, 1 = cancelled"""
    if not ok or not paths:
        return GLib.Variant("(ua{sv})", (1, {}))
    if req["mode"] == "saveFiles":
        folder = paths[0]
        paths = [os.path.join(folder, n) for n in req["files"]] or [folder]
    out = {"uris": GLib.Variant("as", [_uri(p) for p in paths])}
    known = {c["id"]: c for c in req["choices"]}
    picked = []
    for cid, value in (choices or {}).items():
        c = known.get(cid)
        if c is None or not isinstance(value, str):
            continue
        allowed = [o["id"] for o in c["options"]] or ["true", "false"]
        if value in allowed:
            picked.append((cid, value))
    if picked:
        out["choices"] = GLib.Variant("a(ss)", picked)
    if isinstance(flt, int) and 0 <= flt < len(raw_filters):
        out["current_filter"] = raw_filters[flt]
    if req["mode"] in ("save", "saveFiles"):
        out["writable"] = GLib.Variant("b", True)
    return GLib.Variant("(ua{sv})", (0, out))


# ── The files outside the config ──────────────────────────────────────────────

def _data_home():
    return os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")


def _config_home():
    return os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")


def _read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read(1 << 20)
    except (OSError, UnicodeDecodeError):
        return None


def _write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".qsfm-tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


def _own_file(path, text):
    """a whole file of ours: written (text) or removed (None); never one without our mark"""
    current = _read(path)
    if current is None and os.path.lexists(path):
        return
    if current is not None and MARK not in current:
        return
    if text is None:
        if current is not None:
            os.unlink(path)
    elif current != text:
        _write(path, text)


def _desktops():
    return [d.strip().lower() for d in (os.environ.get("XDG_CURRENT_DESKTOP") or "").split(":") if d.strip()]


def conf_in_effect():
    """(path of the portal configuration xdg-desktop-portal uses, whether it's in the user's
    config folder). Its order: per folder <desktop>-portals.conf, then portals.conf; the user's
    config folder first, then the system's"""
    user = os.path.join(_config_home(), "xdg-desktop-portal")
    dirs = [user] + [os.path.join(d, "xdg-desktop-portal") for d in (os.environ.get("XDG_CONFIG_DIRS") or "/etc/xdg").split(":") if d]
    dirs += ["/etc/xdg-desktop-portal", os.path.join(_data_home(), "xdg-desktop-portal")]
    dirs += [os.path.join(d, "xdg-desktop-portal") for d in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":") if d]
    names = [d + "-portals.conf" for d in _desktops()] + ["portals.conf"]
    for d in dirs:
        for n in names:
            p = os.path.join(d, n)
            if os.path.isfile(p):
                return p, d == user
    return None, False


def conf_set(text, on):
    """the configuration's text with FileChooser → quickshell (on) or as it was before (off).
    What was there is kept in a comment, so off puts exactly that back"""
    before, kept = None, []
    for line in text.split("\n"):
        s = line.strip()
        if s == MARK:
            continue
        if s.startswith(PREV):
            before = s[len(PREV):].strip()
            continue
        kept.append(line)
    out, in_pref, value = [], False, ""
    for line in kept:
        s = line.strip()
        if s.startswith("["):
            in_pref = s == "[preferred]"
        elif in_pref and "=" in s and s.split("=", 1)[0].strip() == KEY:
            value = s.split("=", 1)[1].strip()
            continue
        out.append(line)
    if before is None:                     # not ours yet: what's there now is the "before"
        before = "" if value.rstrip(";") == "quickshell" else value
    block = [MARK, PREV + " " + before, KEY + "=quickshell"] if on else ([KEY + "=" + before] if before else [])
    while out and out[-1].strip() == "":
        out.pop()
    start = next((i for i, l in enumerate(out) if l.strip() == "[preferred]"), -1)
    if start < 0:
        if not block:
            return "\n".join(out) + "\n" if out else ""
        out.append("[preferred]")
        start = len(out) - 1
    end = next((i for i in range(start + 1, len(out)) if out[i].strip().startswith("[")), len(out))
    while end > start + 1 and out[end - 1].strip() == "":
        end -= 1
    out[end:end] = block
    return "\n".join(out) + "\n"


def fallbacks():
    """the backends a call is handed to when our window doesn't come up: what the
    configuration named for file dialogs before us, its default, then the usual ones"""
    names = []
    p, _ = conf_in_effect()
    text = _read(p) if p else None
    for line in (text or "").split("\n"):
        s = line.strip()
        v = None
        if s.startswith(PREV):
            v = s[len(PREV):].strip()
        elif s.split("=", 1)[0].strip() in (KEY, "default") and "=" in s:
            v = s.split("=", 1)[1]
        for n in (v or "").split(";"):
            n = n.strip()
            if n and n.replace("-", "").replace("_", "").isalnum() and n not in ("quickshell", "none", "*") and n not in names:
                names.append(n)
    for n in BUILTIN:
        if n not in names:
            names.append(n)
    return ["org.freedesktop.impl.portal.desktop." + n for n in names]


class Chooser:
    def __init__(self, launcher):
        self.launcher = launcher          # files.sh: what D-Bus starts when an app asks and Files isn't running
        self.own = 0
        self.conn = None
        self.reg = 0
        self.node = Gio.DBusNodeInfo.new_for_xml(XML)
        self.next = 1
        self.open = {}                    # n → {"inv", "method", "params", "handle", "req", "filters", "reg", "timer", "passed"}
        self.problem = ""

    # ── on / off ──

    def set(self, on):
        try:
            self._files(on)
            self.problem = ""
        except OSError as e:
            self.problem = "Couldn't write the portal files: " + (e.strerror or str(e))
        if on and not self.own:
            self.own = Gio.bus_own_name(Gio.BusType.SESSION, NAME, Gio.BusNameOwnerFlags.NONE, self._acquired, None, None)
        elif not on and self.own:
            for n in list(self.open):
                self._reply(n, GLib.Variant("(ua{sv})", (2, {})))
            if self.conn is not None and self.reg:
                self.conn.unregister_object(self.reg)
            self.reg = 0
            Gio.bus_unown_name(self.own)
            self.own = 0
        return {"on": bool(self.own), "problem": self.problem}

    def _files(self, on):
        service = os.path.join(_data_home(), "dbus-1", "services", NAME + ".service")
        _own_file(service, "%s\n[D-BUS Service]\nName=%s\nExec=%s --start\n" % (MARK, NAME, self.launcher) if on else None)
        portal = os.path.join(_data_home(), "xdg-desktop-portal", "portals", "quickshell.portal")
        _own_file(portal, "%s\n[portal]\nDBusName=%s\nInterfaces=%s\n" % (MARK, NAME, IFACE) if on else None)
        path, mine = conf_in_effect()
        if mine:
            text = _read(path)
            if text is not None:
                new = conf_set(text, on)
                if new != text:
                    _write(path, new)
        elif on:
            # none of the user's own yet: a copy of the one in effect (it would be shadowed
            # otherwise), named for this desktop, plus our line
            base = _read(path) if path else None
            name = (_desktops() or [""])[0]
            target = os.path.join(_config_home(), "xdg-desktop-portal", (name + "-" if name else "") + "portals.conf")
            if not os.path.lexists(target):
                _write(target, conf_set(base or "[preferred]\ndefault=*\n", True))
        self._reload_bus()

    def _reload_bus(self):
        """the session bus reads service files again (a new one is seen only then)"""
        try:
            bus = self.conn or Gio.bus_get_sync(Gio.BusType.SESSION, None)
            bus.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "ReloadConfig",
                     None, None, Gio.DBusCallFlags.NONE, 3000, None, None)
        except GLib.Error:
            pass

    def _acquired(self, conn, name):
        self.conn = conn
        self.reg = conn.register_object(PATH, self.node.interfaces[0], self._call)

    # ── a request ──

    def _call(self, conn, sender, path, iface, method, params, inv):
        try:
            handle = params.get_child_value(0).get_string()
            title = params.get_child_value(3).get_string()
            options = params.get_child_value(4)
            req = parse(method, title, options)
            fv = options.lookup_value("filters", GLib.VariantType.new("a(sa(us))"))
            raw_filters = [fv.get_child_value(i) for i in range(min(fv.n_children(), 100))] if fv is not None else []
        except Exception:  # noqa: BLE001  (a request we can't read: not ours to answer wrongly)
            inv.return_value(GLib.Variant("(ua{sv})", (2, {})))
            return
        n = self.next
        self.next += 1
        entry = {"inv": inv, "method": method, "params": params, "handle": handle, "req": req,
                 "filters": raw_filters, "reg": 0, "timer": 0, "passed": ""}
        try:
            entry["reg"] = conn.register_object(handle, self.node.interfaces[1],
                                                lambda c, s, p, i, m, a, v, n=n: self._close(n, v))
        except GLib.Error:
            pass
        self.open[n] = entry
        entry["timer"] = GLib.timeout_add_seconds(ACK_S, self._late, n)
        send({"event": "chooser", "chooser": n, **req})

    def ack(self, n):
        e = self.open.get(n)
        if e is None or e["passed"]:
            return False
        if e["timer"]:
            GLib.source_remove(e["timer"])
            e["timer"] = 0
        return True

    def done(self, n, ok, paths, choices, flt):
        e = self.open.get(n)
        if e is None or e["passed"]:
            return False
        self._reply(n, results(e["req"], e["filters"], ok, paths, choices, flt))
        return True

    def _reply(self, n, value):
        e = self.open.pop(n, None)
        if e is None:
            return
        if e["timer"]:
            GLib.source_remove(e["timer"])
        if e["reg"] and self.conn is not None:
            self.conn.unregister_object(e["reg"])
        try:
            e["inv"].return_value(value)
        except Exception:  # noqa: BLE001
            pass

    def _close(self, n, inv):
        """the app took its request back"""
        inv.return_value(None)
        e = self.open.get(n)
        if e is None:
            return
        if e["passed"]:
            self.conn.call(e["passed"], e["handle"], REQUEST, "Close", None, None, Gio.DBusCallFlags.NONE, 3000, None, None)
            return
        send({"event": "chooserClosed", "chooser": n})
        self._reply(n, GLib.Variant("(ua{sv})", (1, {})))

    # ── no window came up: the next backend gets the call ──

    def _late(self, n):
        e = self.open.get(n)
        if e is None:
            return False
        e["timer"] = 0
        send({"event": "chooserClosed", "chooser": n})
        self._pass(n, fallbacks())
        return False

    def _pass(self, n, names):
        e = self.open.get(n)
        if e is None:
            return
        if not names or self.conn is None:
            self._reply(n, GLib.Variant("(ua{sv})", (2, {})))
            return
        e["passed"] = names[0]         # (a Close from the app is passed on to it: _close)

        def got(conn, res):
            try:
                value = conn.call_finish(res)
            except GLib.Error:
                self._pass(n, names[1:])
                return
            self._reply(n, value)
        self.conn.call(names[0], PATH, IFACE, e["method"], e["params"], GLib.VariantType.new("(ua{sv})"),
                       Gio.DBusCallFlags.NONE, GLib.MAXINT32, None, got)
