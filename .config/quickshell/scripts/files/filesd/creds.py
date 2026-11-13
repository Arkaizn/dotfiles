"""The logins GVfs keeps in the keyring (servers you ticked "Remember" for):
listed so one can be picked for a connection — also to another server.

Only attributes are read here (user, domain, server, protocol). A password is
loaded in one place, secret_of(), by the backend itself when a login was
picked, and goes straight into the mount operation: never to the UI, a file,
a command line or a log.

    logins()        -> [{id, user, domain, server, protocol, share}]   (id: the keyring item's path)
    secret_of(id)   -> (user, domain, password)    raises Fail
"""
import re

from .proto import Fail

SCHEMA = "org.gnome.keyring.NetworkPassword"
_ID = re.compile(r"^/org/freedesktop/secrets/collection/[A-Za-z0-9_]+/[A-Za-z0-9_]+$")
MAX = 100


def _secret():
    import gi
    try:
        gi.require_version("Secret", "1")
        from gi.repository import Secret
    except (ValueError, ImportError):
        raise Fail("The keyring library isn't installed (libsecret)", "unsupported")
    return Secret


def _schema(Secret):
    A = Secret.SchemaAttributeType
    return Secret.Schema.new(SCHEMA, Secret.SchemaFlags.NONE, {
        "user": A.STRING, "domain": A.STRING, "server": A.STRING, "protocol": A.STRING,
        "object": A.STRING, "authtype": A.STRING, "port": A.INTEGER})


def logins():
    """every saved network login, newest first; a locked keyring's are listed too (attributes
    are readable), nothing is unlocked and nothing asks"""
    Secret = _secret()
    from gi.repository import GLib
    try:
        items = Secret.password_search_sync(_schema(Secret), {}, Secret.SearchFlags.ALL, None)
    except GLib.Error as e:
        raise Fail(e.message.split("\n")[0] or "The keyring isn't reachable", "unsupported")
    out, seen = [], set()
    for it in sorted(items, key=lambda i: -(i.get_modified() or 0)):
        a = it.get_attributes() or {}
        user = a.get("user") or ""
        path = it.get_object_path() if hasattr(it, "get_object_path") else ""
        if not user or not _ID.match(path or ""):
            continue
        key = (user, a.get("domain") or "", a.get("server") or "", a.get("protocol") or "")
        if key in seen:                    # (GVfs keeps one per share: one line per user and server)
            continue
        seen.add(key)
        out.append({"id": path, "user": user, "domain": key[1], "server": key[2], "protocol": key[3],
                    "share": a.get("object") or ""})
        if len(out) >= MAX:
            break
    return out


def secret_of(item_id):
    """the login behind an id from logins(): only a network login's, whatever the id says"""
    if not isinstance(item_id, str) or not _ID.match(item_id):
        raise Fail("not a saved login", "invalid")
    Secret = _secret()
    from gi.repository import GLib
    try:
        # found again among the network logins (so an id can only ever name one of those)
        items = Secret.password_search_sync(_schema(Secret), {}, Secret.SearchFlags.ALL, None)
        item = next((i for i in items if hasattr(i, "get_object_path") and i.get_object_path() == item_id), None)
        if item is None:
            raise Fail("That saved login isn't in the keyring any more", "missing")
        a = item.get_attributes() or {}
        if not a.get("user"):
            raise Fail("not a saved login", "invalid")
        if item.get_locked():
            item.get_service().unlock_sync([item], None)          # the keyring's own prompt
        value = item.retrieve_secret_sync(None)
        text = value.get_text() if value is not None else None
    except GLib.Error as e:
        raise Fail(e.message.split("\n")[0] or "The keyring didn't give that login", "denied")
    if text is None:
        raise Fail("The keyring didn't give that login (locked?)", "denied")
    return a["user"], a.get("domain") or "", text
