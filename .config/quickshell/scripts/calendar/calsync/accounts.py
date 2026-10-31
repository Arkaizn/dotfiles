from datetime import datetime
from datetime import timezone
import json
import os
import re
from .common import CalError, secret_lookup, secret_store
from .files import gpg_run, write_private


ACCOUNT_TYPES = ("caldav", "ics", "local", "graph")


def clean_cal_account(a):
    if not isinstance(a, dict) or a.get("type") not in ACCOUNT_TYPES:
        return None
    s = lambda k, n: str(a.get(k) or "")[:n]
    out = {"type": a["type"], "name": s("name", 120), "url": s("url", 2000), "username": s("username", 320)}
    if a["type"] == "graph":
        for k in ("tenant", "clientId"):
            v = s(k, 100)
            if v and re.fullmatch(r"[\w.-]+", v):
                out[k] = v
    cals = []
    for c in (a.get("calendars") or [])[:200]:
        if not isinstance(c, dict) or not isinstance(c.get("href"), str) or not c["href"]:
            continue
        col = str(c.get("color") or "")
        cals.append({"href": c["href"][:2000], "name": str(c.get("name") or "")[:200],
                     "color": col if re.fullmatch(r"#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?", col) else "",
                     "readOnly": c.get("readOnly") is True, "enabled": c.get("enabled") is not False,
                     "notify": c.get("notify") is not False})
    out["calendars"] = cals
    out["name"] = out["name"] or out["url"] or out["type"]
    return out


def export_accounts(req):
    with_pw = bool(req.get("withPasswords"))
    pw = str(req.get("passphrase") or "")
    if with_pw and len(pw) < 8:
        raise CalError("The passphrase needs at least 8 characters")
    accs = []
    for a in req.get("accounts") or []:
        clean = clean_cal_account(a)
        if clean is None:
            continue
        if with_pw and a.get("id"):
            secret = secret_lookup(a["id"])
            if secret:
                clean["secret"] = secret
        if clean["type"] == "local":
            path = os.path.expanduser(clean["url"])
            try:
                if os.path.getsize(path) <= 20 * 1024 * 1024:
                    with open(path, encoding="utf-8", errors="replace") as f:
                        clean["data"] = f.read()
            except OSError:
                pass
        accs.append(clean)
    if not accs:
        raise CalError("Pick at least one account")
    payload = json.dumps({"quickshellCalendar": 1, "exported": datetime.now(timezone.utc).isoformat(), "accounts": accs},
                         indent=2, ensure_ascii=False).encode("utf-8")
    if with_pw:
        code, out, err = gpg_run(["--symmetric", "--cipher-algo", "AES256", "--s2k-mode", "3", "--s2k-digest-algo", "SHA512",
                                  "--s2k-count", "65011712", "--armor", "--output", "-"], payload, pw)
        if code != 0 or not out:
            raise CalError("Encrypting failed: " + (err.strip().splitlines() or ["gpg error"])[-1])
        payload = out
    path = write_private(req["path"], payload)
    return {"path": path, "count": len(accs), "encrypted": with_pw}


def read_accounts_export(req):
    path = os.path.expanduser(str(req.get("path") or ""))
    try:
        if os.path.getsize(path) > 64 * 1024 * 1024:
            raise CalError("That file is too big for an accounts export")
        with open(path, "rb") as f:
            data = f.read()
    except OSError as e:
        raise CalError("Can't read the file: " + (e.strerror or str(e)))
    encrypted = data.lstrip().startswith(b"-----BEGIN PGP MESSAGE-----") or data[:1] in (b"\x8c", b"\xc3")
    if encrypted:
        pw = str(req.get("passphrase") or "")
        if not pw:
            return True, None
        code, out, err = gpg_run(["--decrypt"], data, pw)
        if code != 0:
            raise CalError("Wrong passphrase, or the file was changed")
        data = out
    try:
        v = json.loads(data.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        raise CalError("That isn't a calendar accounts export")
    if not isinstance(v, dict) or v.get("quickshellCalendar") != 1 or not isinstance(v.get("accounts"), list):
        raise CalError("That isn't a calendar accounts export")
    return encrypted, v["accounts"][:100]


def import_accounts_read(req):
    encrypted, accs = read_accounts_export(req)
    if accs is None:
        return {"encrypted": True, "needPassphrase": True, "accounts": []}
    out = []
    for i, a in enumerate(accs):
        clean = clean_cal_account(a)
        if clean is None:
            continue
        clean["index"] = i
        clean["hasPassword"] = isinstance(a.get("secret"), str) and a["secret"] != ""
        clean["hasData"] = isinstance(a.get("data"), str) and "BEGIN:VCALENDAR" in a["data"].upper()
        out.append(clean)
    return {"encrypted": encrypted, "needPassphrase": False, "accounts": out}


def import_accounts(req):
    encrypted, accs = read_accounts_export(req)
    if accs is None:
        raise CalError("The file is encrypted: enter its passphrase")
    pick = req.get("pick") or {}
    out = []
    for i, a in enumerate(accs):
        clean = clean_cal_account(a)
        if clean is None or str(i) not in pick:
            continue
        new_id = str(pick[str(i)])
        if not re.fullmatch(r"acc-[A-Za-z0-9-]{1,40}", new_id):
            raise CalError("bad account id")
        stored = False
        if isinstance(a.get("secret"), str) and a["secret"]:
            secret_store(new_id, "Quickshell calendar: " + clean["name"], a["secret"])
            stored = True
        written = False
        # a local calendar: its file, unless there is one already (that one is kept)
        if clean["type"] == "local" and isinstance(a.get("data"), str) and "BEGIN:VCALENDAR" in a["data"].upper():
            path = os.path.expanduser(clean["url"])
            if path and not os.path.exists(path):
                os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
                with open(path, "w", encoding="utf-8") as f:
                    f.write(a["data"])
                written = True
        out.append(dict(clean, id=new_id, passwordStored=stored, dataWritten=written))
    return {"accounts": out}
