from email.utils import format_datetime
import email
import email.header
import email.policy
import email.utils
import json
import os
import re
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from .common import MailError, secret_lookup, secret_store, server_of
from .files import gpg_run, write_private


PRESETS = {
    "icloud": {"domains": ["icloud.com", "me.com", "mac.com"],
               "imap": ("imap.mail.me.com", 993, "ssl"), "smtp": ("smtp.mail.me.com", 587, "starttls"),
               "hint": "iCloud needs an app-specific password: account.apple.com → Sign-In and Security → App-Specific Passwords (two-factor authentication must be on).",
               "url": "https://account.apple.com/account/manage"},
    "gmail": {"domains": ["gmail.com", "googlemail.com"],
              "imap": ("imap.gmail.com", 993, "ssl"), "smtp": ("smtp.gmail.com", 465, "ssl"),
              "hint": "Gmail needs an app password (2-Step Verification must be on): Google Account → Security → App passwords.",
              "url": "https://myaccount.google.com/apppasswords"},
    "yahoo": {"domains": ["yahoo.com", "yahoo.de", "yahoo.co.uk", "yahoo.fr", "ymail.com", "rocketmail.com"],
              "imap": ("imap.mail.yahoo.com", 993, "ssl"), "smtp": ("smtp.mail.yahoo.com", 465, "ssl"),
              "hint": "Yahoo needs an app password: Account security → Generate app password.",
              "url": "https://login.yahoo.com/account/security"},
    "fastmail": {"domains": ["fastmail.com", "fastmail.fm", "messagingengine.com"],
                 "imap": ("imap.fastmail.com", 993, "ssl"), "smtp": ("smtp.fastmail.com", 465, "ssl"),
                 "hint": "Fastmail needs an app password: Settings → Privacy & Security → App passwords.",
                 "url": "https://app.fastmail.com/settings/security/devicekeys"},
    "gmx": {"domains": ["gmx.de", "gmx.net", "gmx.at", "gmx.ch", "gmx.com"],
            "imap": ("imap.gmx.net", 993, "ssl"), "smtp": ("mail.gmx.net", 587, "starttls"),
            "hint": "GMX: switch on \"POP3/IMAP access\" in the web mail settings first.", "url": "https://www.gmx.net"},
    "webde": {"domains": ["web.de"],
              "imap": ("imap.web.de", 993, "ssl"), "smtp": ("smtp.web.de", 587, "starttls"),
              "hint": "Web.de: switch on \"POP3/IMAP access\" in the web mail settings first.", "url": "https://web.de"},
    "mailboxorg": {"domains": ["mailbox.org"],
                   "imap": ("imap.mailbox.org", 993, "ssl"), "smtp": ("smtp.mailbox.org", 465, "ssl"),
                   "hint": "", "url": ""},
    "posteo": {"domains": ["posteo.de", "posteo.net"],
               "imap": ("posteo.de", 993, "ssl"), "smtp": ("posteo.de", 587, "starttls"), "hint": "", "url": ""},
    "proton": {"domains": ["proton.me", "protonmail.com", "protonmail.ch", "pm.me"],
               "imap": ("127.0.0.1", 1143, "starttls"), "smtp": ("127.0.0.1", 1025, "starttls"),
               "hint": "Proton Mail works through Proton Mail Bridge on this computer: use the bridge password it shows, not your Proton password.",
               "url": "https://proton.me/mail/bridge"},
}


MICROSOFT = ("outlook.com", "hotmail.com", "live.com", "msn.com", "outlook.de", "hotmail.de")


def server(host, port, sec):
    return {"host": host, "port": port, "security": sec}


def preset_for(domain):
    for name, p in PRESETS.items():
        if domain in p["domains"]:
            return name, p
    return None, None


def parse_autoconfig(xml_text, address):
    """Thunderbird clientConfig XML -> {imap, smtp, username} (None if no IMAP in it)"""
    root = ET.fromstring(xml_text)
    local, _, domain = address.partition("@")

    def fill(v):
        return (v or "").replace("%EMAILADDRESS%", address).replace("%EMAILLOCALPART%", local).replace("%EMAILDOMAIN%", domain)

    def read(el):
        sock = (el.findtext("socketType") or "").upper()
        return {"host": fill(el.findtext("hostname")).strip(), "port": int(el.findtext("port") or 0),
                "security": {"SSL": "ssl", "STARTTLS": "starttls"}.get(sock, "none")}, fill(el.findtext("username"))
    imap = smtp = None
    user = ""
    for el in root.iter("incomingServer"):
        if el.get("type") == "imap":
            imap, user = read(el)
            break
    for el in root.iter("outgoingServer"):
        if el.get("type") == "smtp":
            smtp, _ = read(el)
            break
    if not imap or not smtp:
        return None
    # never take a plain-text server from a file on the network
    if imap["security"] == "none" or smtp["security"] == "none":
        return None
    return {"imap": imap, "smtp": smtp, "username": user or address}


def fetch_text(url, timeout=8):
    req = urllib.request.Request(url, headers={"User-Agent": "quickshell-mail"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read(512 * 1024).decode("utf-8", "replace")


def autoconfig(req):
    address = str(req.get("email") or "").strip()
    if not re.fullmatch(r"[^@\s]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", address):
        raise MailError("Enter a full email address")
    domain = address.split("@", 1)[1].lower()
    if domain in MICROSOFT:
        raise MailError("Outlook.com / Hotmail need a Microsoft sign-in, which this app can't do yet")
    name, p = preset_for(domain)
    if p:
        return {"imap": server(*p["imap"]), "smtp": server(*p["smtp"]), "username": address,
                "source": "built in", "provider": name, "hint": p["hint"], "url": p["url"]}
    for source, url in (("Thunderbird's list", f"https://autoconfig.thunderbird.net/v1.1/{domain}"),
                        ("the provider", f"https://autoconfig.{domain}/mail/config-v1.1.xml?emailaddress={address}")):
        if os.environ.get("MAIL_NO_NETWORK"):
            break
        try:
            cfg = parse_autoconfig(fetch_text(url), address)
        except Exception:
            cfg = None
        if cfg:
            # Google Workspace / Microsoft hosted domains end up at their servers
            if cfg["imap"]["host"].endswith("gmail.com") or cfg["imap"]["host"].endswith("googlemail.com"):
                name = "gmail"
            return dict(cfg, source=source, provider=name or "",
                        hint=PRESETS[name]["hint"] if name else "", url=PRESETS[name]["url"] if name else "")
    return {"imap": server("imap." + domain, 993, "ssl"), "smtp": server("smtp." + domain, 465, "ssl"),
            "username": address, "source": "guessed", "provider": "", "hint": "Guessed from the address — check the servers.", "url": ""}


ACCOUNT_FIELDS = ("email", "name", "displayName", "username", "provider", "imap", "smtp", "signature", "color", "notify")


def clean_account(a):
    """an account from a file -> (clean dict, errors). Same checks as a typed one."""
    errs = []
    if not isinstance(a, dict):
        return None, ["not an object"]
    e = str(a.get("email") or "").strip()
    if not re.fullmatch(r"[^@\s<>,;\"]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", e):
        errs.append("bad email address")
    out = {"email": e}
    for k, limit in (("name", 120), ("displayName", 120), ("username", 320), ("signature", 4000)):
        v = a.get(k, "")
        if not isinstance(v, str) or len(v) > limit:
            errs.append(f"{k}: text up to {limit} characters")
            v = ""
        out[k] = v
    out["name"] = out["name"] or e
    out["username"] = out["username"] or e
    prov = a.get("provider") or ""
    out["provider"] = prov if prov in PRESETS or prov == "" else ""
    col = str(a.get("color") or "")
    out["color"] = col if re.fullmatch(r"#[0-9a-fA-F]{6}", col) else ""
    out["notify"] = a.get("notify") is not False
    for kind in ("imap", "smtp"):
        try:
            host, port, sec = server_of(a, kind)
            out[kind] = {"host": host, "port": port, "security": sec}
        except MailError as ex:
            errs.append(str(ex))
    return out, errs


def export_accounts(req):
    with_pw = bool(req.get("withPasswords"))
    pw = str(req.get("passphrase") or "")
    if with_pw and len(pw) < 8:
        raise MailError("The passphrase needs at least 8 characters")
    accs = []
    for a in req.get("accounts") or []:
        clean, errs = clean_account(a)
        if errs:
            raise MailError(f"{a.get('email', '?')}: " + "; ".join(errs))
        if with_pw:
            secret = secret_lookup(a["id"])
            if secret:
                clean["password"] = secret
        accs.append(clean)
    if not accs:
        raise MailError("Pick at least one account")
    payload = json.dumps({"quickshellMail": 1, "exported": format_datetime(email.utils.localtime()), "accounts": accs},
                         indent=2, ensure_ascii=False).encode("utf-8")
    if with_pw:
        code, out, err = gpg_run(["--symmetric", "--cipher-algo", "AES256", "--s2k-mode", "3", "--s2k-digest-algo", "SHA512",
                                  "--s2k-count", "65011712", "--armor", "--output", "-"], payload, pw)
        if code != 0 or not out:
            raise MailError("Encrypting failed: " + (err.strip().splitlines() or ["gpg error"])[-1])
        payload = out
    path = write_private(req["path"], payload)
    return {"path": path, "count": len(accs), "encrypted": with_pw}


def read_export(req):
    path = os.path.expanduser(str(req.get("path") or ""))
    try:
        if os.path.getsize(path) > 4 * 1024 * 1024:
            raise MailError("That file is too big for an accounts export")
        with open(path, "rb") as f:
            data = f.read()
    except OSError as e:
        raise MailError("Can't read the file: " + (e.strerror or str(e)))
    encrypted = data.lstrip().startswith(b"-----BEGIN PGP MESSAGE-----") or data[:1] in (b"\x8c", b"\xc3")
    if encrypted:
        pw = str(req.get("passphrase") or "")
        if not pw:
            return True, None
        code, out, err = gpg_run(["--decrypt"], data, pw)
        if code != 0:
            raise MailError("Wrong passphrase, or the file was changed")
        data = out
    try:
        v = json.loads(data.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        raise MailError("That isn't a mail accounts export")
    if not isinstance(v, dict) or v.get("quickshellMail") != 1 or not isinstance(v.get("accounts"), list):
        raise MailError("That isn't a mail accounts export")
    return encrypted, v["accounts"][:100]


def import_read(req):
    encrypted, accs = read_export(req)
    if accs is None:
        return {"encrypted": True, "needPassphrase": True, "accounts": []}
    out = []
    for a in accs:
        clean, errs = clean_account(a)
        if clean is None:
            continue
        clean["hasPassword"] = bool(isinstance(a, dict) and isinstance(a.get("password"), str) and a["password"])
        clean["errors"] = errs
        out.append(clean)
    return {"encrypted": encrypted, "needPassphrase": False, "accounts": out}


def import_accounts(req):
    encrypted, accs = read_export(req)
    if accs is None:
        raise MailError("The file is encrypted: enter its passphrase")
    pick = req.get("pick") or {}
    out = []
    for a in accs:
        clean, errs = clean_account(a)
        if clean is None or errs or clean["email"] not in pick:
            continue
        new_id = str(pick[clean["email"]])
        if not re.fullmatch(r"mail-[A-Za-z0-9-]{1,40}", new_id):
            raise MailError("bad account id")
        stored = False
        if isinstance(a.get("password"), str) and a["password"]:
            secret_store(new_id, "Quickshell mail: " + clean["email"], a["password"])
            stored = True
        out.append(dict(clean, id=new_id, passwordStored=stored))
    return {"accounts": out}
