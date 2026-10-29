#!/usr/bin/env python3
"""Mail backend for the quickshell mail app (modules/mail, services/MailStore.qml).

IMAP + SMTP, so most providers work: iCloud, Gmail, Yahoo, Fastmail, GMX / Web.de,
mailbox.org, Posteo, your own server, Proton Mail Bridge (on this computer).
Standard library only. Passwords live in the keyring (secret-tool, service
quickshell-mail, id <account id>), never in the accounts file or a command line.

Usage:  mailsync.py <command>   with the request JSON in $MAIL_REQUEST,
        the answer is JSON on stdout: {"ok": true, ...} or {"ok": false, "error": "..."}

  autoconfig    {email}                     -> {imap, smtp, username, source, provider, hint, url}
  test          {account, password}         -> {folders}   (IMAP and SMTP login both checked)
  folders       {account}                   -> {folders: [{path, name, role, unread, total}]}
  sync          {accounts: [{account, folders: [{path, uidvalidity, uids}]}], limit}
                                            -> {results: [{account, folders: [...], error}]}
  body          {account, folder, uid, cache, allowRemote}
                                            -> {text, html, attachments, headers, remoteBlocked}
  attachment    {account, folder, uid, cache, index, dest}  -> {path}
  flags         {account, folder, uids, add, remove}
  move          {account, folder, uids, to}
  delete        {account, folder, uids, trash}     (to trash, or for good when already there)
  search        {account, folder, query, known}     -> {uids, messages}
  send          {account, message, sentFolder}      -> {messageId}
  view          {account, folder, uid, cache, index}   -> {kind: image|pdf|text|other, path, name, type, pages, pageCount, text}
  export        {accounts, withPasswords, passphrase, path}   -> {path, count, encrypted}
  import-read   {path, passphrase}           -> {encrypted, needPassphrase, accounts: [… no passwords, hasPassword, errors]}
  import        {path, passphrase, pick: {email: newId}}  -> {accounts}   (passwords go straight to the keyring)
  invite        {account, event, method: REQUEST|CANCEL, sentFolder}  -> {messageId}   (iMIP, RFC 6047)
  store-secret  {id, label, password}
  forget-secret {id}

An account: {id, name, email, displayName, username, provider,
             imap: {host, port, security: ssl|starttls|none}, smtp: {…}}
("none" = no TLS, only for this computer: tests, Proton Mail Bridge).
"""

import base64
import email
import email.header
import email.policy
import email.utils
import hashlib
import html
import imaplib
import ipaddress
import json
import mimetypes
import os
import re
import shutil
import smtplib
import socket
import ssl
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from email.headerregistry import Address
from email.message import EmailMessage
from email.utils import format_datetime, getaddresses, make_msgid, parsedate_to_datetime
from html.parser import HTMLParser

SECRET_SERVICE = "quickshell-mail"
TIMEOUT = 30
PREVIEW = 2048           # bytes of the first text part fetched for the list preview
LIMIT = 300              # newest messages kept per folder
LOCAL_HOSTS = ("127.0.0.1", "localhost", "::1")

imaplib.Commands.setdefault("MOVE", ("SELECTED",))
imaplib._MAXLINE = 10_000_000


class MailError(Exception):
    pass


# ── Secrets ──────────────────────────────────────────────────────────────────

def secret_lookup(acc_id):
    fake = os.environ.get("MAIL_FAKE_SECRETS")          # tests only
    if fake:
        return json.loads(fake).get(acc_id, "")
    try:
        r = subprocess.run(["secret-tool", "lookup", "service", SECRET_SERVICE, "id", acc_id],
                           capture_output=True, text=True, timeout=25)
    except subprocess.TimeoutExpired:
        raise MailError("The keyring didn't answer — is it locked? Unlock it and try again")
    return r.stdout.rstrip("\n") if r.returncode == 0 else ""


def secret_store(acc_id, label, password):
    if os.environ.get("MAIL_FAKE_SECRETS"):             # tests only
        return
    try:
        r = subprocess.run(["secret-tool", "store", "--label=" + label, "service", SECRET_SERVICE, "id", acc_id],
                           input=password, capture_output=True, text=True, timeout=25)
    except subprocess.TimeoutExpired:
        raise MailError("The keyring didn't answer — is it locked? Unlock it and try again")
    if r.returncode != 0:
        raise MailError("The keyring didn't take the password: " + (r.stderr.strip() or "secret-tool failed"))


def secret_clear(acc_id):
    if os.environ.get("MAIL_FAKE_SECRETS"):
        return
    try:
        subprocess.run(["secret-tool", "clear", "service", SECRET_SERVICE, "id", acc_id], capture_output=True, timeout=25)
    except subprocess.TimeoutExpired:
        pass


def password_of(account, req=None):
    pw = (req or {}).get("password") or secret_lookup(account["id"])
    if not pw:
        raise MailError("No password in the keyring for " + (account.get("name") or account.get("email") or "this account")
                        + " — edit the account and enter it again")
    return pw


# ── Checks ───────────────────────────────────────────────────────────────────

HOST_RE = re.compile(r"^(?=.{1,253}$)[A-Za-z0-9]([A-Za-z0-9-]{0,62}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,62}[A-Za-z0-9])?)*$|^\d{1,3}(\.\d{1,3}){3}$|^::1$")


def server_of(account, kind):
    s = account.get(kind) or {}
    host = str(s.get("host") or "").strip()
    if not HOST_RE.match(host):
        raise MailError(f"The {kind.upper()} server name isn't valid: {host or '(empty)'}")
    try:
        port = int(s.get("port"))
    except (TypeError, ValueError):
        raise MailError(f"The {kind.upper()} port isn't a number")
    if not 0 < port < 65536:
        raise MailError(f"The {kind.upper()} port is out of range")
    sec = s.get("security") or "ssl"
    if sec not in ("ssl", "starttls", "none"):
        raise MailError(f"Unknown {kind.upper()} security: {sec}")
    if sec == "none" and host not in LOCAL_HOSTS:
        raise MailError("Without encryption only servers on this computer are allowed (like Proton Mail Bridge)")
    return host, port, sec


def tls_context(host):
    ctx = ssl.create_default_context()
    if host in LOCAL_HOSTS:          # local bridges (Proton) use a self-signed certificate
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    return ctx


def friendly(e):
    """network / login exceptions -> one readable line"""
    if isinstance(e, MailError):
        return str(e)
    if isinstance(e, imaplib.IMAP4.error):
        m = str(e)
        m = re.sub(r"^b?['\"]|['\"]$", "", m)
        if re.search(r"AUTHENTICATIONFAILED|Invalid credentials|LOGIN failed|authentication failed|Web login required|Application-specific password",
                     m, re.I):
            return "The server didn't accept the login (" + m.strip() + "). Most providers want an app password here."
        return "IMAP: " + m
    if isinstance(e, smtplib.SMTPAuthenticationError):
        return "The mail server (SMTP) didn't accept the login: " + (e.smtp_error.decode(errors="replace") if isinstance(e.smtp_error, bytes) else str(e.smtp_error))
    if isinstance(e, smtplib.SMTPRecipientsRefused):
        return "Refused recipients: " + ", ".join(e.recipients)
    if isinstance(e, smtplib.SMTPException):
        return "SMTP: " + str(e)
    if isinstance(e, ssl.SSLCertVerificationError):
        return "The server's certificate isn't valid: " + (e.verify_message or str(e))
    if isinstance(e, ssl.SSLError):
        return "Encryption failed (" + str(e.reason or e) + ") — is the security setting / port right?"
    if isinstance(e, TimeoutError) or "timed out" in str(e):
        return "The server didn't answer (timeout)"
    if isinstance(e, ConnectionRefusedError):
        return "Connection refused — wrong port, or the server is down"
    if isinstance(e, OSError) and getattr(e, "errno", None) in (-2, -3, -5):
        return "Server not found — check the name, or the internet connection"
    return str(e) or e.__class__.__name__


# ── Modified UTF-7 (IMAP folder names, RFC 3501 5.1.3) ───────────────────────

def mutf7_decode(s):
    out, i = [], 0
    while i < len(s):
        if s[i] == "&":
            j = s.index("-", i)
            if j == i + 1:
                out.append("&")
            else:
                b = s[i + 1:j].replace(",", "/")
                b += "=" * (-len(b) % 4)
                out.append(base64.b64decode(b).decode("utf-16-be"))
            i = j + 1
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


def mutf7_encode(s):
    out, buf = [], []

    def flush():
        if buf:
            b = base64.b64encode("".join(buf).encode("utf-16-be")).decode().rstrip("=").replace("/", ",")
            out.append("&" + b + "-")
            buf.clear()
    for ch in s:
        if 0x20 <= ord(ch) <= 0x7e:
            flush()
            out.append("&-" if ch == "&" else ch)
        else:
            buf.append(ch)
    flush()
    return "".join(out)


def quote_box(path):
    p = mutf7_encode(path)
    return '"' + p.replace("\\", "\\\\").replace('"', '\\"') + '"'


# ── IMAP response parsing (FETCH / LIST with literals) ───────────────────────

class Lit(bytes):
    pass


def chunks_of(data):
    """imaplib's data list -> a flat list of bytes pieces and Lit literals"""
    out = []
    for item in data:
        if item is None:
            continue
        if isinstance(item, tuple):
            out.append(item[0])
            out.append(Lit(item[1]))
        else:
            out.append(item)
    return out


def tokenize(chunks):
    toks = []
    for c in chunks:
        if isinstance(c, Lit):
            toks.append(c)
            continue
        s = c.decode("utf-8", "replace") if isinstance(c, bytes) else c
        i, n = 0, len(s)
        while i < n:
            ch = s[i]
            if ch in " \r\n":
                i += 1
            elif ch in "()":
                toks.append(ch)
                i += 1
            elif ch == '"':
                j, buf = i + 1, []
                while j < n and s[j] != '"':
                    if s[j] == "\\" and j + 1 < n:
                        j += 1
                    buf.append(s[j])
                    j += 1
                toks.append(("str", "".join(buf)))
                i = j + 1
            elif ch == "{":
                j = s.index("}", i)
                i = j + 1          # the literal follows as its own chunk
            else:
                j, depth = i, 0
                while j < n:
                    cj = s[j]
                    if cj == "[":
                        depth += 1
                    elif cj == "]":
                        depth -= 1
                    elif depth == 0 and (cj in " ()\r\n"):
                        break
                    j += 1
                toks.append(("atom", s[i:j]))
                i = j
    return toks


def parse_tokens(toks):
    """-> nested python lists; atoms as str, strings as str, literals as bytes, NIL as None"""
    pos = 0

    def value():
        nonlocal pos
        t = toks[pos]
        pos += 1
        if t == "(":
            items = []
            while toks[pos] != ")":
                items.append(value())
            pos += 1
            return items
        if isinstance(t, Lit):
            return bytes(t)
        kind, v = t
        if kind == "atom" and v.upper() == "NIL":
            return None
        return v
    out = []
    while pos < len(toks):
        if toks[pos] == ")":
            pos += 1
            continue
        out.append(value())
    return out


def parse_fetch(data):
    """FETCH answer -> [{KEY: value}] (keys upper case, BODY[...] kept as written)"""
    vals = parse_tokens(tokenize(chunks_of(data)))
    msgs, i = [], 0
    while i < len(vals):
        if isinstance(vals[i], str) and vals[i].isdigit() and i + 1 < len(vals) and vals[i + 1] == "FETCH":
            i += 2
            continue
        if isinstance(vals[i], list):
            items, d = vals[i], {}
            for k in range(0, len(items) - 1, 2):
                key = items[k]
                if isinstance(key, str):
                    key = re.sub(r"^BODY\.PEEK", "BODY", key.upper())
                    d[key] = items[k + 1]
            msgs.append(d)
        i += 1
    return msgs


def parse_list(data):
    out = []
    for item in data:
        if item is None:
            continue
        vals = parse_tokens(tokenize(chunks_of([item])))
        if len(vals) < 3:
            continue
        flags, delim, name = vals[0] or [], vals[1], vals[2]
        if isinstance(name, bytes):
            name = name.decode("utf-8", "replace")
        out.append({"flags": [f.lower() for f in flags if isinstance(f, str)], "delim": delim or "/", "raw": str(name)})
    return out


def uid_set(uids):
    """[3, 4, 5, 9] -> '3:5,9'"""
    uids = sorted(set(int(u) for u in uids))
    parts, i = [], 0
    while i < len(uids):
        j = i
        while j + 1 < len(uids) and uids[j + 1] == uids[j] + 1:
            j += 1
        parts.append(str(uids[i]) if i == j else f"{uids[i]}:{uids[j]}")
        i = j + 1
    return ",".join(parts)


# ── BODYSTRUCTURE ────────────────────────────────────────────────────────────

def _params(lst):
    d = {}
    if isinstance(lst, list):
        for k in range(0, len(lst) - 1, 2):
            key, val = lst[k], lst[k + 1]
            if isinstance(val, bytes):
                val = val.decode("utf-8", "replace")
            if isinstance(key, str) and isinstance(val, str):
                d[key.lower()] = decode_header(val)
    return d


def walk_structure(bs, section=""):
    """BODYSTRUCTURE -> flat list of leaf parts {section, type, params, encoding, size, disposition, filename, cid}"""
    if not isinstance(bs, list) or not bs:
        return []
    if isinstance(bs[0], list):                         # multipart: children, then subtype …
        parts, n = [], 0
        for child in bs:
            if not isinstance(child, list):
                break
            n += 1
            parts += walk_structure(child, f"{section}.{n}" if section else str(n))
        return parts
    typ = f"{str(bs[0]).lower()}/{str(bs[1]).lower()}" if len(bs) > 1 else "text/plain"
    params = _params(bs[2] if len(bs) > 2 else None)
    cid = str(bs[3] or "").strip("<>") if len(bs) > 3 and isinstance(bs[3], str) else ""
    enc = str(bs[5] or "7bit").lower() if len(bs) > 5 else "7bit"
    try:
        size = int(bs[6]) if len(bs) > 6 else 0
    except (TypeError, ValueError):
        size = 0
    # the disposition comes after the type specific fields: look for (type (params)) where type is a disposition
    disp, dparams = "", {}
    for x in bs[7:]:
        if isinstance(x, list) and len(x) >= 1 and isinstance(x[0], str) and x[0].lower() in ("attachment", "inline"):
            disp, dparams = x[0].lower(), _params(x[1] if len(x) > 1 else None)
            break
    filename = dparams.get("filename") or params.get("name") or ""
    return [{"section": section or "1", "type": typ, "params": params, "encoding": enc, "size": size,
             "disposition": disp, "filename": filename, "cid": cid}]


def is_attachment(p):
    if p["disposition"] == "attachment":
        return True
    if p["type"].startswith("text/") and not p["filename"]:
        return False
    if p["type"].startswith("multipart/") or p["type"] in ("message/delivery-status",):
        return False
    # inline images referenced by the HTML (cid) aren't listed as attachments
    if p["cid"] and p["disposition"] != "attachment" and p["type"].startswith("image/"):
        return False
    return bool(p["filename"]) or not p["type"].startswith("text/")


def preview_part(parts):
    for want in ("text/plain", "text/html"):
        for p in parts:
            if p["type"] == want and p["disposition"] != "attachment":
                return p
    return None


# ── Text helpers ─────────────────────────────────────────────────────────────

def decode_header(v):
    if v is None:
        return ""
    try:
        return str(email.header.make_header(email.header.decode_header(str(v)))).strip()
    except Exception:
        return str(v).strip()


def addresses(v):
    """header value -> [{name, email}]"""
    out = []
    for name, addr in getaddresses([decode_header(v)] if v else []):
        if addr or name:
            out.append({"name": name.strip().strip('"'), "email": addr.strip()})
    return out


def decode_partial(data, encoding, charset):
    """the first bytes of a part (maybe cut in the middle) -> text"""
    if encoding == "base64":
        b = re.sub(rb"[^A-Za-z0-9+/=]", b"", data)
        b = b[: len(b) - len(b) % 4]
        try:
            data = base64.b64decode(b)
        except Exception:
            data = b""
    elif encoding == "quoted-printable":
        import quopri
        data = quopri.decodestring(re.sub(rb"=[0-9A-Fa-f]?$", b"", data))
    try:
        return data.decode(charset or "utf-8", "replace")
    except LookupError:
        return data.decode("utf-8", "replace")


class _TextOut(HTMLParser):
    BLOCK = {"p", "div", "br", "tr", "li", "h1", "h2", "h3", "h4", "h5", "h6", "table", "blockquote", "pre", "hr"}
    SKIP = {"script", "style", "head", "title"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out, self.skip = [], 0

    def handle_starttag(self, tag, attrs):
        if tag in self.SKIP:
            self.skip += 1
        elif tag in self.BLOCK:
            self.out.append("\n")
        if tag == "li":
            self.out.append("• ")

    def handle_endtag(self, tag):
        if tag in self.SKIP:
            self.skip = max(0, self.skip - 1)
        elif tag in self.BLOCK:
            self.out.append("\n")

    def handle_data(self, data):
        if not self.skip:
            self.out.append(data)


def html_to_text(s):
    p = _TextOut()
    try:
        p.feed(s)
        p.close()
    except Exception:
        return re.sub(r"<[^>]+>", " ", s)
    text = "".join(p.out).replace("\xa0", " ")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r" *\n *", "\n", text)
    return re.sub(r"\n{3,}", "\n\n", text).strip()


def preview_text(raw, part):
    text = decode_partial(raw, part["encoding"], part["params"].get("charset"))
    if part["type"] == "text/html":
        text = html_to_text(text)
    # quoted replies and signatures don't make a good preview
    lines = [ln for ln in text.splitlines() if not ln.lstrip().startswith(">")]
    return re.sub(r"\s+", " ", " ".join(lines)).strip()[:220]


# ── HTML for Qt's rich text: no scripts / styles, remote content blocked ─────

REMOTE = re.compile(r"^\s*(https?:)?//", re.I)


class _Sanitizer(HTMLParser):
    DROP = {"script", "style", "head", "title", "iframe", "object", "embed", "applet", "form",
            "noscript", "svg", "math", "template", "video", "audio", "canvas"}
    VOID = {"br", "hr", "img", "meta", "link", "input", "col", "area", "base", "wbr", "source"}
    KEEP_ATTRS = {"href", "src", "alt", "title", "width", "height", "align", "valign", "colspan", "rowspan",
                  "border", "cellpadding", "cellspacing", "color", "bgcolor", "face", "size", "style", "dir"}

    HIDDEN = re.compile(r"display\s*:\s*none|mso-hide\s*:\s*all|visibility\s*:\s*hidden", re.I)

    def __init__(self, allow_remote, cids, adapt=False):
        super().__init__(convert_charrefs=False)
        self.allow_remote, self.cids, self.adapt = allow_remote, cids, adapt
        self.out, self.skip, self.blocked = [], 0, 0
        self.hide = None          # [tag, depth]: inside an element hidden by its style (preheaders …)
        self.width = 0            # the widest fixed width (px): what the layout was made for

    def note_width(self, v):
        m = re.fullmatch(r"\s*(\d{2,4})(\.\d+)?\s*(px)?\s*", v or "")
        if m:
            self.width = max(self.width, min(1200, int(m.group(1))))

    def hidden(self, style):
        st = style or ""
        if self.HIDDEN.search(st):
            return True
        return bool(re.search(r"max-height\s*:\s*0", st, re.I) and re.search(r"overflow\s*:\s*hidden", st, re.I))

    def clean_style(self, style):
        if re.search(r"url\s*\(", style, re.I):
            if not self.allow_remote and re.search(r"url\s*\(\s*['\"]?\s*(https?:)?//", style, re.I):
                self.blocked += 1
            style = re.sub(r"url\s*\([^)]*\)", "none", style, flags=re.I)
        style = re.sub(r"expression\s*\(|javascript:|position\s*:\s*(fixed|absolute)", "", style, flags=re.I)
        for m in re.finditer(r"(?:^|;)\s*(?:max-|min-)?width\s*:\s*([\d.]+)px", style, re.I):
            self.note_width(m.group(1))
        # Qt's rich text draws these literally, newsletters use them as tricks: lines on top of
        # each other (line-height below the font size), squeezed text, overlapping blocks
        style = re.sub(r"(^|;)\s*(letter-spacing|margin(-\w+)?)\s*:\s*-[^;]*", r"\1", style, flags=re.I)
        fs = re.search(r"font-size\s*:\s*([\d.]+)px", style, re.I)
        lh = re.search(r"line-height\s*:\s*([\d.]+)px", style, re.I)
        if lh and float(lh.group(1)) < max(12.0, float(fs.group(1)) if fs else 0):
            style = re.sub(r"(^|;)\s*line-height\s*:[^;]*", r"\1", style, flags=re.I)
        if self.adapt:      # dark style: the theme's colors, not the sender's
            style = re.sub(r"(^|;)\s*(color|background(-color|-image)?|border(-\w+)*-color)\s*:[^;]*", r"\1", style, flags=re.I)
        return style

    def handle_starttag(self, tag, attrs, closed=False):
        tag = tag.lower()
        if self.hide is not None:
            if tag == self.hide[0] and tag not in self.VOID and not closed:
                self.hide[1] += 1
            return
        if tag not in self.VOID and not closed and not self.skip and self.hidden(dict((k.lower(), v) for k, v in attrs if k).get("style")):
            self.hide = [tag, 1]
            return
        if tag in self.DROP:
            if tag not in self.VOID and not closed:
                self.skip += 1
            return
        if self.skip or tag in ("meta", "link", "base", "html", "body"):
            return
        kept = []
        for k, v in attrs:
            k = (k or "").lower()
            v = v or ""
            if self.adapt and k in ("color", "bgcolor"):
                continue
            if k.startswith("on") or k not in self.KEEP_ATTRS:
                if k == "background" and REMOTE.match(v) and not self.allow_remote:
                    self.blocked += 1
                continue
            if k == "href" and not re.match(r"^\s*(https?:|mailto:|#)", v, re.I):
                continue
            if k == "src":
                if v.lower().startswith("cid:"):
                    path = self.cids.get(v[4:].strip("<>"))
                    if not path:
                        continue
                    v = "file://" + path
                elif REMOTE.match(v):
                    if not self.allow_remote:
                        self.blocked += 1
                        continue
                    if v.startswith("//"):
                        v = "https:" + v
                # embedded images: only plain bitmap types (no SVG)
                elif not re.match(r"^\s*data:image/(png|jpe?g|gif|webp|bmp)[;,]", v, re.I):
                    continue
            if k == "style":
                v = self.clean_style(v)
            if k == "width" and tag in ("table", "td", "th", "img", "div"):
                self.note_width(v)
            kept.append(f'{k}="{html.escape(v, quote=True)}"')
        if tag == "img" and not any(a.startswith("src=") for a in kept):
            return
        self.out.append(f"<{tag}{' ' if kept else ''}{' '.join(kept)}{' /' if closed else ''}>")

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs, closed=True)

    def handle_endtag(self, tag):
        tag = tag.lower()
        if self.hide is not None:
            if tag == self.hide[0]:
                self.hide[1] -= 1
                if self.hide[1] == 0:
                    self.hide = None
            return
        if tag in self.DROP:
            self.skip = max(0, self.skip - 1)
            return
        if self.skip or tag in self.VOID or tag in ("html", "body"):
            return
        self.out.append(f"</{tag}>")

    def handle_data(self, data):
        if not self.skip and self.hide is None:
            self.out.append(html.escape(data, quote=False))

    def handle_entityref(self, name):
        if not self.skip and self.hide is None:
            self.out.append(f"&{name};")

    def handle_charref(self, name):
        if not self.skip and self.hide is None:
            self.out.append(f"&#{name};")


# ── Remote images (only when allowed): fetched here, not by Qt ──────────────
# Qt would load them inside the shell, with no limits and no cache. Here they
# are fetched in parallel with limits, checked to really be bitmaps, kept on
# disk and reused, and the message points at the local files. Tracking pixels
# (1×1) and addresses on this computer / the local network are never loaded.

IMG_MAX = 5 * 1024 * 1024
IMG_COUNT = 60
IMG_SECONDS = 15
IMG_MAGIC = ((b"\x89PNG\r\n\x1a\n", ".png"), (b"\xff\xd8\xff", ".jpg"), (b"GIF87a", ".gif"), (b"GIF89a", ".gif"), (b"BM", ".bmp"))


def image_kind(head):
    for magic, ext in IMG_MAGIC:
        if head.startswith(magic):
            return ext
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return ".webp"
    return ""


def public_host(host):
    """the name only resolves to addresses on the internet (not this computer / the LAN)"""
    if os.environ.get("MAIL_TEST_LOCAL_IMAGES"):         # tests only: their server is on 127.0.0.1
        return bool(host)
    try:
        infos = socket.getaddrinfo(host, None)
    except OSError:
        return False
    for info in infos:
        ip = ipaddress.ip_address(info[4][0].split("%")[0])
        if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_multicast or ip.is_reserved or ip.is_unspecified:
            return False
    return bool(infos)


class _PublicOnly(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        u = urllib.parse.urlsplit(newurl)
        if u.scheme not in ("http", "https") or not public_host(u.hostname or ""):
            return None
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch_image(url, cache):
    """-> local path or "" (cached by URL; only http(s), public hosts, real bitmaps, ≤ IMG_MAX)"""
    key = hashlib.sha1(url.encode("utf-8", "replace")).hexdigest()
    for ext in (".png", ".jpg", ".gif", ".bmp", ".webp"):
        p = os.path.join(cache, "r-" + key + ext)
        if os.path.exists(p):
            os.utime(p)            # recently used: pruned last
            return p
    if os.path.exists(os.path.join(cache, "r-" + key + ".bad")):
        return ""
    u = urllib.parse.urlsplit(url)
    if u.scheme not in ("http", "https") or not public_host(u.hostname or ""):
        return ""
    opener = urllib.request.OpenerDirector()
    for h in (urllib.request.HTTPHandler(), urllib.request.HTTPSHandler(context=ssl.create_default_context()),
              _PublicOnly(), urllib.request.HTTPErrorProcessor()):
        opener.add_handler(h)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0", "Accept": "image/*"})
        with opener.open(req, timeout=8) as r:
            data = r.read(IMG_MAX + 1)
    except Exception:
        return ""
    ext = image_kind(data[:16])
    if len(data) > IMG_MAX or not ext:
        # remembered: not tried again for every message that has it
        os.close(os.open(os.path.join(cache, "r-" + key + ".bad"), os.O_WRONLY | os.O_CREAT, 0o600))
        return ""
    p = os.path.join(cache, "r-" + key + ext)
    store_raw(p, data)
    return p


IMG_TAG = re.compile(r"<img\b[^>]*>", re.I)


def localize_images(out_html, cache):
    """remote <img> → the local copies; tracking pixels and failed ones go"""
    tags = IMG_TAG.findall(out_html)
    def attr(tag, name):
        m = re.search(r'\b' + name + r'="([^"]*)"', tag)
        return html.unescape(m.group(1)) if m else ""
    def tiny(tag):
        dims = [attr(tag, "width"), attr(tag, "height")]
        return any(re.fullmatch(r"\s*[0-2](px)?\s*", d) for d in dims if d)
    urls = []
    for t in tags:
        src = attr(t, "src")
        if REMOTE.match(src) and not tiny(t) and src not in urls:
            urls.append(src)
    urls = urls[:IMG_COUNT]
    got = {}
    if urls and cache:
        os.makedirs(cache, mode=0o700, exist_ok=True)
        deadline = time.monotonic() + IMG_SECONDS
        ex = ThreadPoolExecutor(max_workers=6)
        futures = {u: ex.submit(fetch_image, u, cache) for u in urls}
        for u, f in futures.items():
            try:
                got[u] = f.result(timeout=max(0.1, deadline - time.monotonic()))
            except Exception:
                got[u] = ""
        ex.shutdown(wait=False, cancel_futures=True)       # the slow ones: shown next time (cached by then)
    def swap(m):
        t = m.group(0)
        src = attr(t, "src")
        if not REMOTE.match(src):
            return t
        p = got.get(src, "")
        return t.replace('src="' + html.escape(src, quote=True) + '"', 'src="' + html.escape("file://" + p, quote=True) + '"') if p else ""
    return IMG_TAG.sub(swap, out_html)


def sanitize_html(s, allow_remote=False, cids=None, adapt=False):
    """-> (html, number of remote things blocked). adapt: drop the sender's colors (dark style)"""
    out = sanitize(s, allow_remote, cids, adapt)
    return out["html"], out["blocked"]


def sanitize(s, allow_remote=False, cids=None, adapt=False):
    """-> {html, blocked, width}; width: the layout's fixed width in px (0 = flows), the
    app scales such a message down to fit instead of cutting it off"""
    p = _Sanitizer(allow_remote, cids or {}, adapt)
    try:
        p.feed(s)
        p.close()
    except Exception:
        return {"html": html.escape(html_to_text(s)).replace("\n", "<br>"), "blocked": 0, "width": 0}
    return {"html": "".join(p.out), "blocked": p.blocked, "width": p.width}


# ── Autoconfig (like Thunderbird: presets, ISPDB, the provider's own file) ───

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


# ── IMAP connection ──────────────────────────────────────────────────────────

class Imap:
    def __init__(self, account, req=None):
        host, port, sec = server_of(account, "imap")
        if sec == "ssl":
            self.c = imaplib.IMAP4_SSL(host, port, ssl_context=tls_context(host), timeout=TIMEOUT)
        else:
            self.c = imaplib.IMAP4(host, port, timeout=TIMEOUT)
            if sec == "starttls":
                self.c.starttls(ssl_context=tls_context(host))
        user = account.get("username") or account.get("email")
        self.c.login(user, password_of(account, req))
        self.selected = None
        self.caps = {c.upper() for c in self.c.capabilities}

    def close(self):
        try:
            self.c.logout()
        except Exception:
            pass

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.close()

    def ok(self, typ, data, what):
        if typ != "OK":
            msg = b" ".join(d for d in data if isinstance(d, bytes)).decode("utf-8", "replace") if data else ""
            raise MailError(f"{what}: {msg or typ}")
        return data

    def select(self, path, readonly=False):
        typ, data = self.c.select(quote_box(path), readonly=readonly)
        self.ok(typ, data, "Can't open folder " + path)
        self.selected = path
        uv = self.c.untagged_responses.get("UIDVALIDITY", [b"0"])[-1]
        exists = int(data[0] or 0)
        return int(uv), exists

    def uid(self, cmd, *args):
        typ, data = self.c.uid(cmd, *args)
        return self.ok(typ, data, cmd)

    def folders(self):
        data = self.ok(*self.c.list(), "LIST")
        out = []
        for f in parse_list(data):
            if "\\noselect" in f["flags"] or "\\nonexistent" in f["flags"]:
                continue
            path = mutf7_decode(f["raw"])
            out.append({"path": path, "name": path.split(f["delim"])[-1] if f["delim"] else path,
                        "delim": f["delim"], "role": role_of(path, f["flags"]),
                        "depth": path.count(f["delim"]) if f["delim"] else 0})
        # special folders first, then by name; a subfolder right under its parent
        rank = {f["path"]: ROLE_ORDER.index(f["role"]) if f["role"] in ROLE_ORDER else 99 for f in out}

        def key(f):
            if not f["delim"]:
                return [(rank[f["path"]], f["path"].lower())]
            parts = f["path"].split(f["delim"])
            return [(rank.get(p, 99), p.lower()) for p in (f["delim"].join(parts[:i + 1]) for i in range(len(parts)))]
        out.sort(key=key)
        return out

    def status(self, path):
        typ, data = self.c.status(quote_box(path), "(MESSAGES UNSEEN)")
        if typ != "OK" or not data or data[0] is None:
            return 0, 0
        s = data[0].decode("utf-8", "replace") if isinstance(data[0], bytes) else str(data[0])
        m1, m2 = re.search(r"MESSAGES (\d+)", s), re.search(r"UNSEEN (\d+)", s)
        return int(m1.group(1)) if m1 else 0, int(m2.group(1)) if m2 else 0


ROLE_ORDER = ["inbox", "drafts", "sent", "archive", "all", "flagged", "junk", "trash", ""]
ROLE_FLAGS = {"\\sent": "sent", "\\drafts": "drafts", "\\trash": "trash", "\\junk": "junk",
              "\\archive": "archive", "\\all": "all", "\\flagged": "flagged"}
ROLE_NAMES = {"sent": ["sent", "sent items", "sent messages", "sent mail", "gesendet", "gesendete objekte", "gesendete elemente"],
              "drafts": ["drafts", "draft", "entwürfe"],
              "trash": ["trash", "deleted", "deleted items", "deleted messages", "bin", "papierkorb", "gelöschte elemente"],
              "junk": ["junk", "spam", "junk e-mail", "junk email", "bulk mail", "spamverdacht"],
              "archive": ["archive", "archives", "archiv"]}


def role_of(path, flags):
    if path.upper() == "INBOX":
        return "inbox"
    for f in flags:
        if f in ROLE_FLAGS:
            return ROLE_FLAGS[f]
    leaf = re.split(r"[/.]", path)[-1].lower()
    for role, names in ROLE_NAMES.items():
        if leaf in names:
            return role
    return ""


def special(folders, role):
    return next((f["path"] for f in folders if f["role"] == role), "")


# ── Messages ─────────────────────────────────────────────────────────────────

HEADER_FIELDS = "FROM TO CC REPLY-TO SUBJECT DATE MESSAGE-ID IN-REPLY-TO REFERENCES LIST-UNSUBSCRIBE"


def summary(d, header_bytes):
    h = email.message_from_bytes(header_bytes or b"", policy=email.policy.compat32)
    flags = [f for f in (d.get("FLAGS") or []) if isinstance(f, str)]
    parts = walk_structure(d.get("BODYSTRUCTURE"))
    atts = [p for p in parts if is_attachment(p)]
    try:
        date_ms = int(parsedate_to_datetime(h.get("Date")).timestamp() * 1000)
    except Exception:
        date_ms = 0
    if not date_ms and d.get("INTERNALDATE"):
        try:
            date_ms = int(time.mktime(imaplib.Internaldate2tuple(b'INTERNALDATE "' + d["INTERNALDATE"].encode() + b'"')) * 1000)
        except Exception:
            date_ms = 0
    refs = re.findall(r"<[^>]+>", decode_header(h.get("References")) + " " + decode_header(h.get("In-Reply-To")))
    return {
        "uid": int(d.get("UID") or 0),
        "subject": decode_header(h.get("Subject")),
        "from": (addresses(h.get("From")) or [{"name": "", "email": ""}])[0],
        "to": addresses(h.get("To")),
        "cc": addresses(h.get("Cc")),
        "replyTo": addresses(h.get("Reply-To")),
        "date": date_ms,
        "messageId": (re.findall(r"<[^>]+>", decode_header(h.get("Message-ID"))) or [""])[0],
        "refs": refs[-20:],
        "seen": "\\Seen" in flags, "flagged": "\\Flagged" in flags, "answered": "\\Answered" in flags,
        "forwarded": "$Forwarded" in flags, "junk": "$Junk" in flags or "Junk" in flags,
        "size": int(d.get("RFC822.SIZE") or 0),
        "attachments": len(atts),
        "unsubscribe": bool(h.get("List-Unsubscribe")),
        "preview": "",
        "_part": preview_part(parts),
    }


def fetch_summaries(im, uids):
    """headers + flags + a preview for these uids (any order) -> [summary]"""
    out = []
    uids = sorted(uids)
    for i in range(0, len(uids), 100):
        batch = uids[i:i + 100]
        data = im.uid("FETCH", uid_set(batch),
                      f"(UID FLAGS INTERNALDATE RFC822.SIZE BODYSTRUCTURE BODY.PEEK[HEADER.FIELDS ({HEADER_FIELDS})])")
        for d in parse_fetch(data):
            if "UID" not in d:
                continue
            hb = next((v for k, v in d.items() if k.startswith("BODY[HEADER")), b"")
            out.append(summary(d, hb if isinstance(hb, bytes) else str(hb or "").encode()))
    # previews: one FETCH per distinct section ("1", "1.1", …)
    by_section = {}
    for s in out:
        if s["_part"]:
            by_section.setdefault(s["_part"]["section"], []).append(s)
    for section, group in by_section.items():
        for i in range(0, len(group), 100):
            batch = group[i:i + 100]
            data = im.uid("FETCH", uid_set([s["uid"] for s in batch]), f"(UID BODY.PEEK[{section}]<0.{PREVIEW}>)")
            raw = {}
            for d in parse_fetch(data):
                v = next((v for k, v in d.items() if k.startswith("BODY[")), b"")
                raw[int(d.get("UID") or 0)] = v if isinstance(v, bytes) else str(v or "").encode()
            for s in batch:
                if s["uid"] in raw:
                    s["preview"] = preview_text(raw[s["uid"]], s["_part"])
    for s in out:
        s.pop("_part", None)
    return out


def sync_folder(im, path, known, limit, sizes=None):
    """known: {uidvalidity, uids} from the cache -> {path, uidvalidity, uids, new, flags, total, unread}"""
    uv, exists = im.select(path, readonly=True)
    known_uids = set(known.get("uids") or []) if int(known.get("uidvalidity") or 0) == uv else set()
    window = {}
    if exists:
        start = max(1, exists - limit + 1)
        typ, data = im.c.fetch(f"{start}:*", "(UID FLAGS RFC822.SIZE)")
        im.ok(typ, data, "FETCH")
        for d in parse_fetch(data):
            if "UID" in d:
                window[int(d["UID"])] = [f for f in (d.get("FLAGS") or []) if isinstance(f, str)]
                if sizes is not None:
                    sizes[int(d["UID"])] = int(d.get("RFC822.SIZE") or 0)
    new = [u for u in window if u not in known_uids]
    msgs = fetch_summaries(im, new) if new else []
    flags = {str(u): {"seen": "\\Seen" in f, "flagged": "\\Flagged" in f, "answered": "\\Answered" in f,
                      "forwarded": "$Forwarded" in f} for u, f in window.items() if u in known_uids}
    unread = sum(1 for f in window.values() if "\\Seen" not in f)
    total = exists
    if exists > limit:
        total, unread = im.status(path)
    return {"path": path, "uidvalidity": uv, "uids": sorted(window), "new": msgs, "flags": flags,
            "total": total, "unread": unread}


def sync_account(entry, limit, cache=""):
    account = entry["account"]
    res = {"account": account["id"], "folders": [], "error": "", "folderList": None}
    try:
        with Imap(account) as im:
            if entry.get("listFolders"):
                fl = im.folders()
                for f in fl:
                    f["total"], f["unread"] = im.status(f["path"])
                res["folderList"] = fl
            ahead = []
            for f in entry.get("folders") or []:
                try:
                    sizes = {}
                    r = sync_folder(im, f["path"], f, limit, sizes)
                    res["folders"].append(r)
                    if f.get("prefetch", True):
                        ahead.append((f["path"], r["uidvalidity"], sizes))
                except MailError as e:
                    res["folders"].append({"path": f["path"], "error": str(e)})
            # opening the newest messages then needs no connection at all
            if cache:
                deadline = time.monotonic() + PREFETCH_SECONDS
                for path, uv, sizes in ahead:
                    try:
                        if im.selected != path:
                            im.select(path, readonly=True)
                        prefetch(im, account["id"], path, uv, sizes, cache, deadline)
                    except Exception:
                        break        # only a head start: the check itself worked
    except Exception as e:
        res["error"] = friendly(e)
    return res


def sync(req):
    limit = int(req.get("limit") or LIMIT)
    cache = req.get("cache") or ""
    entries = req.get("accounts") or []
    with ThreadPoolExecutor(max_workers=max(1, min(6, len(entries)))) as ex:
        results = list(ex.map(lambda e: sync_account(e, limit, cache), entries))
    if cache:
        prune_cache(cache)
    return {"results": results}


def folders(req):
    with Imap(req["account"], req) as im:
        fl = im.folders()
        for f in fl:
            f["total"], f["unread"] = im.status(f["path"])
        return {"folders": fl}


def create_folder(req):
    """A new folder: name (one level), inside parent ("" = top level). Answers the new
    path and the account's folder list as it is now on the server."""
    name = str(req.get("name") or "").strip()
    parent = str(req.get("parent") or "")
    if not name:
        raise MailError("The folder needs a name")
    if len(name) > 200 or any(ord(ch) < 32 or ord(ch) == 127 for ch in name):
        raise MailError("That name can't be used for a folder")
    with Imap(req["account"], req) as im:
        fl = im.folders()
        delim = next((f["delim"] for f in fl if f["path"] == parent), "") if parent else ""
        delim = delim or next((f["delim"] for f in fl if f["delim"]), "/")
        if delim in name:
            raise MailError(f"A folder name can't contain {delim!r}")
        if parent and not any(f["path"] == parent for f in fl):
            raise MailError("The folder to put it in is gone")
        path = parent + delim + name if parent else name
        # Gmail etc. keep top-level folders next to INBOX, some servers only inside it
        if any(f["path"].lower() == path.lower() for f in fl):
            raise MailError(f"There is already a folder {name!r}")
        im.ok(*im.c.create(quote_box(path)), "CREATE")
        try:
            im.c.subscribe(quote_box(path))
        except Exception:
            pass             # not every server keeps subscriptions; the folder is there anyway
        fl = im.folders()
        for f in fl:
            f["total"], f["unread"] = im.status(f["path"])
        return {"path": path, "folders": fl}


def test_login(req):
    account = req["account"]
    try:
        with Imap(account, req) as im:
            fl = im.folders()
    except Exception as e:
        raise MailError(friendly(e))
    try:
        s = smtp_connect(account, req)
        s.quit()
    except Exception as e:
        raise MailError("Receiving works, sending doesn't: " + friendly(e))
    return {"folders": fl}


# ── Full message ─────────────────────────────────────────────────────────────

def cache_file(cache, acc_id, folder, uidvalidity, uid):
    d = os.path.expanduser(cache or "")
    if not d:
        return ""
    os.makedirs(d, mode=0o700, exist_ok=True)
    # UIDVALIDITY in the key: after a folder reset the same UID is another message
    key = hashlib.sha1(f"{acc_id}|{folder}|{int(uidvalidity or 0)}|{int(uid)}".encode()).hexdigest()
    return os.path.join(d, key + ".eml")


def cache_path(req):
    return cache_file(req.get("cache"), req["account"]["id"], req["folder"], req.get("uidvalidity"), req["uid"])


def store_raw(path, raw):
    fd = os.open(path + ".tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(raw)
    os.replace(path + ".tmp", path)


CACHE_MAX = 400 * 1024 * 1024    # bodies/ (messages, their inline images, viewed pages) at most this big
PREFETCH = 30                    # newest messages per checked folder fetched ahead
PREFETCH_SIZE = 2 * 1024 * 1024  # … unless bigger than this
PREFETCH_SECONDS = 25            # … and only for this long per account


def prune_cache(cache):
    """oldest first until the cache is under CACHE_MAX"""
    d = os.path.expanduser(cache or "")
    if not d or not os.path.isdir(d):
        return
    entries = []
    for name in os.listdir(d):
        p = os.path.join(d, name)
        try:
            if os.path.isdir(p):
                size = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(p) for f in fs)
            else:
                size = os.path.getsize(p)
            entries.append((os.path.getmtime(p), size, p))
        except OSError:
            continue
    total = sum(e[1] for e in entries)
    for _, size, p in sorted(entries):
        if total <= CACHE_MAX:
            break
        try:
            shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)
            total -= size
        except OSError:
            pass


def prefetch(im, acc_id, folder, uidvalidity, sizes, cache, deadline):
    """the newest messages' full source into the cache, in a few batches over this connection"""
    want = []
    for uid in sorted(sizes, reverse=True)[:PREFETCH]:
        if sizes[uid] > PREFETCH_SIZE:
            continue
        p = cache_file(cache, acc_id, folder, uidvalidity, uid)
        if p and not os.path.exists(p):
            want.append((uid, p))
    for i in range(0, len(want), 8):
        if time.monotonic() > deadline:
            return
        batch = dict(want[i:i + 8])
        data = im.uid("FETCH", uid_set(list(batch)), "(UID BODY.PEEK[])")
        for d in parse_fetch(data):
            raw = next((v for k, v in d.items() if k.startswith("BODY[")), None)
            uid = int(d.get("UID") or 0)
            if isinstance(raw, bytes) and uid in batch:
                store_raw(batch[uid], raw)


def raw_message(req):
    path = cache_path(req)
    if path and os.path.exists(path):
        with open(path, "rb") as f:
            return f.read(), path
    with Imap(req["account"]) as im:
        im.select(req["folder"], readonly=True)
        data = im.uid("FETCH", str(int(req["uid"])), "(UID BODY.PEEK[])")
        msgs = parse_fetch(data)
        raw = next((v for k, v in (msgs[0] if msgs else {}).items() if k.startswith("BODY[")), None)
        if raw is None:
            raise MailError("The message isn't on the server any more")
    if path:
        store_raw(path, raw)
    return raw, path


def message_parts(msg):
    """-> (text, html, attachments [part], inline {cid: part})"""
    text = html_part = None
    atts, inline = [], {}
    for part in msg.walk():
        if part.is_multipart():
            continue
        ctype = part.get_content_type()
        disp = (part.get_content_disposition() or "")
        fname = part.get_filename()
        cid = (part.get("Content-ID") or "").strip().strip("<>")
        if ctype == "text/plain" and disp != "attachment" and not fname and text is None:
            text = part
        elif ctype == "text/html" and disp != "attachment" and not fname and html_part is None:
            html_part = part
        elif cid and ctype.startswith("image/") and disp != "attachment":
            inline[cid] = part
        elif ctype not in ("text/plain", "text/html") or disp == "attachment" or fname:
            atts.append(part)
    return text, html_part, atts, inline


def part_text(part):
    try:
        return part.get_content()
    except Exception:
        payload = part.get_payload(decode=True) or b""
        return payload.decode(part.get_content_charset() or "utf-8", "replace")


def body(req):
    raw, path = raw_message(req)
    msg = email.message_from_bytes(raw, policy=email.policy.default)
    text, html_part, atts, inline = message_parts(msg)
    cids = {}
    if inline and path:
        idir = path[:-4] + ".inline"
        os.makedirs(idir, mode=0o700, exist_ok=True)
        for cid, part in inline.items():
            ext = mimetypes.guess_extension(part.get_content_type()) or ".bin"
            p = os.path.join(idir, hashlib.sha1(cid.encode()).hexdigest()[:16] + ext)
            if not os.path.exists(p):
                with open(p, "wb") as f:
                    f.write(part.get_payload(decode=True) or b"")
            cids[cid] = p
    out_html, blocked, width = "", 0, 0
    if html_part is not None:
        clean = sanitize(part_text(html_part), bool(req.get("allowRemote")), cids, req.get("style") == "dark")
        out_html, blocked, width = clean["html"], clean["blocked"], clean["width"]
        if req.get("allowRemote"):
            out_html = localize_images(out_html, os.path.expanduser(req.get("cache") or ""))
    out_text = part_text(text) if text is not None else (html_to_text(part_text(html_part)) if html_part is not None else "")
    return {
        "text": out_text.replace("\r\n", "\n"),
        "html": out_html,
        "remoteBlocked": blocked,
        "htmlWidth": width,
        "attachments": [{"index": i, "name": decode_header(p.get_filename()) or f"attachment-{i + 1}",
                         "type": p.get_content_type(), "size": len(p.get_payload(decode=True) or b"")}
                        for i, p in enumerate(atts)],
        "headers": {
            "from": addresses(msg.get("From")), "to": addresses(msg.get("To")), "cc": addresses(msg.get("Cc")),
            "replyTo": addresses(msg.get("Reply-To")), "subject": decode_header(msg.get("Subject")),
            "date": decode_header(msg.get("Date")),
            "messageId": (re.findall(r"<[^>]+>", str(msg.get("Message-ID") or "")) or [""])[0],
            "references": re.findall(r"<[^>]+>", str(msg.get("References") or "")),
            "unsubscribe": decode_header(msg.get("List-Unsubscribe")),
        },
    }


def safe_name(name):
    name = re.sub(r"[/\\\x00-\x1f]", "_", name)
    name = re.sub(r"\.{2,}", ".", name).strip(" .") or "attachment"
    return name[:180]


def attachment(req):
    raw, _ = raw_message(req)
    msg = email.message_from_bytes(raw, policy=email.policy.default)
    _, _, atts, _ = message_parts(msg)
    i = int(req["index"])
    if not 0 <= i < len(atts):
        raise MailError("No such attachment")
    part = atts[i]
    dest = os.path.expanduser(req.get("dest") or "")
    if not dest:
        raise MailError("No folder to save to")
    os.makedirs(dest, exist_ok=True)
    name = safe_name(decode_header(part.get_filename()) or f"attachment-{i + 1}")
    path = os.path.join(dest, name)
    base, ext = os.path.splitext(path)
    n = 1
    while os.path.exists(path) and not req.get("overwrite"):
        path = f"{base} ({n}){ext}"
        n += 1
    with open(path, "wb") as f:
        f.write(part.get_payload(decode=True) or b"")
    return {"path": path}


# ── Changes ──────────────────────────────────────────────────────────────────

FLAG_NAMES = {"seen": "\\Seen", "flagged": "\\Flagged", "answered": "\\Answered", "forwarded": "$Forwarded",
              "junk": "$Junk", "notjunk": "$NotJunk"}


def flags(req):
    add = [FLAG_NAMES[f] for f in req.get("add") or [] if f in FLAG_NAMES]
    remove = [FLAG_NAMES[f] for f in req.get("remove") or [] if f in FLAG_NAMES]
    with Imap(req["account"]) as im:
        im.select(req["folder"])
        s = uid_set(req["uids"])
        if add:
            im.uid("STORE", s, "+FLAGS.SILENT", "(" + " ".join(add) + ")")
        if remove:
            im.uid("STORE", s, "-FLAGS.SILENT", "(" + " ".join(remove) + ")")
    return {}


def move_uids(im, uids, to):
    s = uid_set(uids)
    if "MOVE" in im.caps:
        im.uid("MOVE", s, quote_box(to))
        return
    im.uid("COPY", s, quote_box(to))
    im.uid("STORE", s, "+FLAGS.SILENT", "(\\Deleted)")
    if "UIDPLUS" in im.caps:
        im.uid("EXPUNGE", s)
    else:
        im.ok(*im.c.expunge(), "EXPUNGE")


def move(req):
    if not req.get("to"):
        raise MailError("No folder to move to")
    with Imap(req["account"]) as im:
        im.select(req["folder"])
        move_uids(im, req["uids"], req["to"])
    return {}


def delete(req):
    with Imap(req["account"]) as im:
        im.select(req["folder"])
        trash = req.get("trash") or ""
        if trash and trash != req["folder"]:
            move_uids(im, req["uids"], trash)
        else:
            s = uid_set(req["uids"])
            im.uid("STORE", s, "+FLAGS.SILENT", "(\\Deleted)")
            if "UIDPLUS" in im.caps:
                im.uid("EXPUNGE", s)
            else:
                im.ok(*im.c.expunge(), "EXPUNGE")
    return {}


def search(req):
    q = str(req.get("query") or "").strip()
    if not q:
        return {"uids": [], "messages": []}
    with Imap(req["account"]) as im:
        im.select(req["folder"], readonly=True)
        im.c.literal = q.encode("utf-8")
        typ, data = im.c.uid("SEARCH", "CHARSET", "UTF-8", "TEXT")
        if typ != "OK":       # servers without UTF-8 search: ASCII only
            im.c.literal = None
            typ, data = im.c.uid("SEARCH", None, "TEXT", '"' + re.sub(r'["\\]', " ", q.encode("ascii", "ignore").decode()) + '"')
            im.ok(typ, data, "SEARCH")
        uids = sorted({int(u) for u in (data[0] or b"").split()}, reverse=True)[:200]
        known = set(req.get("known") or [])
        msgs = fetch_summaries(im, [u for u in uids if u not in known])
    return {"uids": uids, "messages": msgs}


# ── Sending ──────────────────────────────────────────────────────────────────

def smtp_connect(account, req=None):
    host, port, sec = server_of(account, "smtp")
    if sec == "ssl":
        s = smtplib.SMTP_SSL(host, port, context=tls_context(host), timeout=TIMEOUT)
    else:
        s = smtplib.SMTP(host, port, timeout=TIMEOUT)
        s.ehlo()
        if sec == "starttls":
            s.starttls(context=tls_context(host))
            s.ehlo()
    if s.has_extn("auth"):
        s.login(account.get("username") or account.get("email"), password_of(account, req))
    return s


def addr_list(items):
    out = []
    for a in items or []:
        if isinstance(a, dict):
            name, mail = str(a.get("name") or ""), str(a.get("email") or "").strip()
        else:
            name, mail = "", str(a).strip()
        if not mail:
            continue
        if not re.fullmatch(r"[^@\s<>,;]+@[^@\s<>,;]+", mail):
            raise MailError(f"Not an email address: {mail}")
        if re.search(r"[\r\n]", name):
            name = ""
        out.append((name, mail))
    return out


def build_message(account, m):
    msg = EmailMessage()
    me = account.get("email")
    msg["From"] = Address(display_name=account.get("displayName") or "", addr_spec=me) if me else me
    to, cc, bcc = addr_list(m.get("to")), addr_list(m.get("cc")), addr_list(m.get("bcc"))
    if not (to or cc or bcc):
        raise MailError("Add at least one recipient")
    if to:
        msg["To"] = [Address(display_name=n, addr_spec=a) for n, a in to]
    if cc:
        msg["Cc"] = [Address(display_name=n, addr_spec=a) for n, a in cc]
    subject = re.sub(r"[\r\n]+", " ", str(m.get("subject") or ""))
    msg["Subject"] = subject
    msg["Date"] = format_datetime(email.utils.localtime())
    msg["Message-ID"] = make_msgid(domain=(me or "localhost").split("@")[-1])
    msg["User-Agent"] = "Quickshell Mail"
    if m.get("inReplyTo"):
        msg["In-Reply-To"] = m["inReplyTo"]
        refs = [r for r in (m.get("references") or []) if re.fullmatch(r"<[^<>\s]+>", r)][-20:]
        msg["References"] = " ".join(refs + ([m["inReplyTo"]] if m["inReplyTo"] not in refs else []))
    msg.set_content(str(m.get("text") or "").replace("\r\n", "\n"))
    if m.get("html"):
        add_html(msg, str(m["html"]), m.get("inlineDir") or "", me)
    for p in m.get("attachments") or []:
        path = os.path.expanduser(p)
        if not os.path.isfile(path):
            raise MailError(f"Attachment not found: {p}")
        ctype = mimetypes.guess_type(path)[0] or "application/octet-stream"
        main, sub = ctype.split("/", 1)
        with open(path, "rb") as f:
            msg.add_attachment(f.read(), maintype=main, subtype=sub, filename=os.path.basename(path))
    return msg, [a for _, a in to + cc + bcc]


def add_html(msg, body, inline_dir, me):
    """the composer's HTML as the alternative to the text; pictures pasted into it (files in
    the composer's own folder only — any other local path is dropped) go along as cid: parts"""
    root = os.path.realpath(os.path.expanduser(inline_dir)) + os.sep if inline_dir else ""
    body = re.sub(r'<meta name="qrichtext"[^>]*>', "", body)
    # the composer's fonts with fallbacks other mail apps know
    for fam, stack in (("Noto Sans Mono", "'Noto Sans Mono', Consolas, 'Courier New', monospace"),
                       ("Noto Serif", "'Noto Serif', Georgia, 'Times New Roman', serif"),
                       ("Noto Sans", "'Noto Sans', Arial, Helvetica, sans-serif")):
        body = re.sub(r"font-family:\s*'" + fam + r"'(?=\s*[;\"])", "font-family:" + stack, body)
    parts, n = {}, 0

    def swap(mt):
        nonlocal n
        src = html.unescape(mt.group(2))
        path = urllib.parse.unquote(src[7:]) if src.startswith("file://") else ""
        real = os.path.realpath(path) if path else ""
        if not (root and real.startswith(root) and os.path.isfile(real)):
            return ""                                   # not ours: the picture is left out
        with open(real, "rb") as f:
            data = f.read()
        ext = image_kind(data[:16])
        if not ext:
            return ""
        if real not in parts:
            n += 1
            parts[real] = (make_msgid(idstring=f"img{n}", domain=(me or "localhost").split("@")[-1]), data, ext)
        return mt.group(1) + "cid:" + parts[real][0][1:-1] + mt.group(3)

    body = re.sub(r'(<img\b[^>]*?\bsrc=")([^"]*)("[^>]*>)', lambda mt: swap(mt) or "", body, flags=re.I)
    msg.add_alternative(body, subtype="html")
    if parts:
        html_part = msg.get_payload()[-1]
        for real, (cid, data, ext) in parts.items():
            sub = {".jpg": "jpeg"}.get(ext, ext[1:])
            html_part.add_related(data, maintype="image", subtype=sub, cid=cid, filename=os.path.basename(real))


def send(req):
    account, m = req["account"], req["message"]
    msg, rcpts = build_message(account, m)
    try:
        s = smtp_connect(account)
        try:
            s.send_message(msg, from_addr=account.get("email"), to_addrs=rcpts)
        finally:
            try:
                s.quit()
            except Exception:
                pass
    except Exception as e:
        raise MailError(friendly(e))
    warning = ""
    sent = req.get("sentFolder") or ""
    if sent and account.get("provider") != "gmail":       # Gmail files sent mail itself
        try:
            with Imap(account) as im:
                im.ok(*im.c.append(quote_box(sent), "(\\Seen)", imaplib.Time2Internaldate(time.time()), msg.as_bytes()), "APPEND")
        except Exception as e:
            warning = "Sent, but not saved in " + sent + ": " + friendly(e)
    reply = m.get("replyTo")       # {folder, uid, flag: answered|forwarded}
    if reply and reply.get("uid"):
        try:
            flags({"account": account, "folder": reply["folder"], "uids": [reply["uid"]], "add": [reply.get("flag") or "answered"]})
        except Exception:
            pass
    return {"messageId": msg["Message-ID"], "warning": warning}


# ── Viewing attachments ──────────────────────────────────────────────────────

VIEW_PAGES = 60          # PDF pages rendered at most
TEXT_TYPES = ("text/", "application/json", "application/xml", "application/x-yaml", "application/javascript")
IMAGE_TYPES = ("image/png", "image/jpeg", "image/gif", "image/webp", "image/bmp", "image/svg+xml", "image/tiff")


def view(req):
    raw, path = raw_message(req)
    msg = email.message_from_bytes(raw, policy=email.policy.default)
    _, _, atts, _ = message_parts(msg)
    i = int(req["index"])
    if not 0 <= i < len(atts):
        raise MailError("No such attachment")
    part = atts[i]
    name = safe_name(decode_header(part.get_filename()) or f"attachment-{i + 1}")
    ctype = part.get_content_type()
    guessed = mimetypes.guess_type(name)[0] or ""
    if ctype == "application/octet-stream" and guessed:
        ctype = guessed
    base = (path[:-4] if path else os.path.join(os.path.expanduser(req.get("cache") or "/tmp"), "view")) + f".view{i}"
    os.makedirs(base, mode=0o700, exist_ok=True)
    os.chmod(base, 0o700)
    fpath = os.path.join(base, name)
    data = part.get_payload(decode=True) or b""
    if not os.path.exists(fpath):
        fd = os.open(fpath, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "wb") as f:
            f.write(data)
    out = {"kind": "other", "path": fpath, "name": name, "type": ctype, "size": len(data), "pages": [], "pageCount": 0, "text": ""}
    if ctype in IMAGE_TYPES:
        out["kind"] = "image"
    elif ctype == "application/pdf" or data[:5] == b"%PDF-":
        out.update(kind="pdf", **render_pdf(fpath, base))
    elif ctype.startswith(TEXT_TYPES) or ctype == "text/calendar":
        text = data[:300_000].decode(part.get_content_charset() or "utf-8", "replace")
        out.update(kind="text", text=text, truncated=len(data) > 300_000)
    return out


def render_pdf(fpath, base):
    """pages as PNGs, rendered by poppler (no scripting), at most VIEW_PAGES, with a timeout"""
    pdir = os.path.join(base, "pages")
    pages = sorted(f for f in os.listdir(pdir)) if os.path.isdir(pdir) else []
    count = 0
    try:
        info = subprocess.run(["pdfinfo", "--", fpath], capture_output=True, text=True, timeout=20)
        m = re.search(r"^Pages:\s+(\d+)", info.stdout, re.M)
        count = int(m.group(1)) if m else 0
    except (OSError, subprocess.TimeoutExpired):
        pass
    if not pages:
        os.makedirs(pdir, mode=0o700, exist_ok=True)
        last = min(count or VIEW_PAGES, VIEW_PAGES)
        try:
            r = subprocess.run(["pdftoppm", "-png", "-r", "110", "-f", "1", "-l", str(last), "--", fpath, os.path.join(pdir, "p")],
                               capture_output=True, text=True, timeout=90)
        except FileNotFoundError:
            raise MailError("pdftoppm isn't installed (sudo pacman -S poppler)")
        except subprocess.TimeoutExpired:
            raise MailError("The PDF took too long to render")
        pages = sorted(os.listdir(pdir))
        if r.returncode != 0 and not pages:
            raise MailError("The PDF couldn't be shown: " + (r.stderr.strip().splitlines() or ["damaged file"])[-1])
    return {"pages": [os.path.join(pdir, p) for p in pages], "pageCount": count or len(pages)}


# ── Moving accounts to another device ────────────────────────────────────────

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


def gpg_run(args, data, passphrase):
    r, w = os.pipe()
    try:
        p = subprocess.Popen(["gpg", "--batch", "--quiet", "--no-tty", "--yes", "--no-symkey-cache",
                              "--pinentry-mode", "loopback", "--passphrase-fd", str(r)] + args,
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, pass_fds=(r,))
    except FileNotFoundError:
        os.close(r)
        os.close(w)
        raise MailError("GnuPG (gpg) isn't installed")
    os.close(r)
    with os.fdopen(w, "w") as f:
        f.write(passphrase + "\n")
    out, err = p.communicate(data, timeout=60)
    return p.returncode, out, err.decode("utf-8", "replace")


def write_private(path, data):
    path = os.path.expanduser(path)
    d = os.path.dirname(path) or "."
    if not os.path.isdir(d):
        raise MailError("The folder doesn't exist: " + d)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(data)
    os.chmod(path, 0o600)
    return path


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


# ── Calendar invitations (iTIP over mail: RFC 5546, RFC 6047) ────────────────

def ics_text(v):
    v = re.sub(r"[\x00-\x08\x0b-\x1f\x7f]", "", str(v or ""))
    return v.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\r\n", "\n").replace("\r", "\n").replace("\n", "\\n")


def ics_param(v):
    return '"' + re.sub(r'[\x00-\x1f\x7f"]', "", str(v or "")).strip()[:120] + '"'


def ics_fold(line):
    b = line.encode("utf-8")
    if len(b) <= 75:
        return line
    out, cur = [], b""
    for ch in line:
        c = ch.encode("utf-8")
        if len(cur) + len(c) > (75 if not out else 74):
            out.append(cur.decode("utf-8"))
            cur = b""
        cur += c
    out.append(cur.decode("utf-8"))
    return "\r\n ".join(out)


def ics_when(name, ms_, all_day):
    from datetime import datetime, timezone, timedelta
    if all_day:
        d = datetime.fromtimestamp(ms_ / 1000).date()
        return f"{name};VALUE=DATE:{d.strftime('%Y%m%d')}"
    return f"{name}:" + datetime.fromtimestamp(ms_ / 1000, timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def invitation_ics(ev, method):
    if method not in ("REQUEST", "CANCEL"):
        raise MailError("unknown invitation method")
    uid = str(ev.get("uid") or "")
    if not re.fullmatch(r"[^\s\r\n]{1,255}", uid):
        raise MailError("The event has no valid UID")
    org = ev.get("organizer") or {}
    org_mail = addr_list([org])[0][1] if org.get("email") else ""
    if not org_mail:
        raise MailError("No organizer address")
    attendees = addr_list(ev.get("attendees") or [])
    if not attendees:
        raise MailError("No guests to invite")
    from datetime import datetime, timezone
    lines = ["BEGIN:VCALENDAR", "PRODID:-//Quickshell//Calendar//EN", "VERSION:2.0", "CALSCALE:GREGORIAN", f"METHOD:{method}",
             "BEGIN:VEVENT", f"UID:{uid}", "DTSTAMP:" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ"),
             f"SEQUENCE:{max(0, int(ev.get('sequence') or 0))}",
             ics_when("DTSTART", int(ev["start"]), bool(ev.get("allDay"))), ics_when("DTEND", int(ev["end"]), bool(ev.get("allDay"))),
             "SUMMARY:" + ics_text(ev.get("title") or "(No title)")]
    rule = str(ev.get("rrule") or "").strip()
    if rule:
        if not re.fullmatch(r"(RRULE:)?[A-Z]+=[A-Za-z0-9=;,:+-]+", rule) or "FREQ=" not in rule:
            raise MailError("The repeat rule isn't valid")
        lines.append("RRULE:" + re.sub(r"^RRULE:", "", rule))
    if ev.get("location"):
        lines.append("LOCATION:" + ics_text(ev["location"]))
    if ev.get("description"):
        lines.append("DESCRIPTION:" + ics_text(ev["description"]))
    lines.append(f"ORGANIZER;CN={ics_param(org.get('name') or org_mail)}:mailto:{org_mail}")
    for name, mail in attendees:
        lines.append(f"ATTENDEE;CN={ics_param(name or mail)};CUTYPE=INDIVIDUAL;ROLE=REQ-PARTICIPANT;"
                     f"PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:{mail}")
    lines += ["STATUS:" + ("CANCELLED" if method == "CANCEL" else "CONFIRMED"), "TRANSP:OPAQUE", "END:VEVENT", "END:VCALENDAR"]
    return "\r\n".join(ics_fold(ln) for ln in lines) + "\r\n", [m for _, m in attendees]


def human_when(ev):
    from datetime import datetime
    s, e = datetime.fromtimestamp(int(ev["start"]) / 1000), datetime.fromtimestamp(int(ev["end"]) / 1000)
    if ev.get("allDay"):
        return s.strftime("%A, %d %B %Y") + " (all day)"
    same = s.date() == e.date()
    return s.strftime("%A, %d %B %Y, %H:%M") + " – " + (e.strftime("%H:%M") if same else e.strftime("%A, %d %B %Y, %H:%M"))


def invite(req):
    account, ev = req["account"], req["event"]
    method = req.get("method") or "REQUEST"
    ev = dict(ev, organizer={"name": account.get("displayName") or "", "email": account.get("email")})
    ics, rcpts = invitation_ics(ev, method)
    title = re.sub(r"[\r\n]+", " ", str(ev.get("title") or "(No title)"))[:200]
    when = human_when(ev)
    if method == "CANCEL":
        subject, intro = "Cancelled: " + title, "This event was cancelled."
    else:
        subject = ("Updated invitation: " if int(ev.get("sequence") or 0) > 0 else "Invitation: ") + title + " @ " + when
        intro = "You're invited."
    text = "\n".join([intro, "", title, when] + ([str(ev["location"])] if ev.get("location") else [])
                     + (["", str(ev["description"])] if ev.get("description") else [])
                     + ["", "Organizer: " + (ev["organizer"]["name"] or "") + " <" + ev["organizer"]["email"] + ">"])
    msg, _ = build_message(account, {"to": [{"name": "", "email": m} for m in rcpts], "subject": subject, "text": text})
    # Outlook / Apple Mail / Gmail look for a text/calendar part with the method
    msg.add_alternative(ics.encode("utf-8"), maintype="text", subtype="calendar",
                        params={"method": method, "charset": "utf-8"}, cte="base64")
    msg.add_attachment(ics.encode("utf-8"), maintype="application", subtype="ics",
                       filename="invite.ics" if method == "REQUEST" else "cancel.ics")
    try:
        s = smtp_connect(account)
        try:
            s.send_message(msg, from_addr=account.get("email"), to_addrs=rcpts)
        finally:
            try:
                s.quit()
            except Exception:
                pass
    except Exception as e:
        raise MailError(friendly(e))
    warning = ""
    sent = req.get("sentFolder") or ""
    if sent and account.get("provider") != "gmail":
        try:
            with Imap(account) as im:
                im.ok(*im.c.append(quote_box(sent), "(\\Seen)", imaplib.Time2Internaldate(time.time()), msg.as_bytes()), "APPEND")
        except Exception as e:
            warning = "Sent, but not saved in " + sent + ": " + friendly(e)
    return {"messageId": msg["Message-ID"], "warning": warning, "recipients": rcpts}


# ── Main ─────────────────────────────────────────────────────────────────────

COMMANDS = {
    "autoconfig": autoconfig, "test": test_login, "folders": folders, "sync": sync, "body": body,
    "attachment": attachment, "view": view, "export": export_accounts, "import-read": import_read,
    "import": import_accounts, "invite": invite, "flags": flags, "move": move, "create-folder": create_folder, "delete": delete, "search": search, "send": send,
    "store-secret": lambda r: (secret_store(r["id"], r.get("label") or "Quickshell mail", r["password"]), {})[1],
    "forget-secret": lambda r: (secret_clear(r["id"]), {})[1],
}


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd not in COMMANDS:
        print(json.dumps({"ok": False, "error": f"unknown command {cmd!r}"}))
        return 2
    try:
        req = json.loads(os.environ.get("MAIL_REQUEST") or "{}")
        res = COMMANDS[cmd](req)
        print(json.dumps(dict(res, ok=True)))
    except Exception as e:
        print(json.dumps({"ok": False, "error": friendly(e)}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
