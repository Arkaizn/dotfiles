from email.utils import parsedate_to_datetime
import email
import email.header
import email.policy
import email.utils
import hashlib
import os
import re
import time

from qsbackend import lazy
_futures = lazy('concurrent.futures')   # (not "futures": functions use that name)
imaplib = lazy('imaplib')
from .common import LIMIT, MailError, PREVIEW, TIMEOUT, friendly, password_of, server_of, tls_context
from .imapproto import mutf7_decode, parse_fetch, parse_list, quote_box, uid_set
from .mime import addresses, decode_header, is_attachment, preview_part, preview_text, walk_structure
from .files import cache_dir, cache_file, cache_path, prune_cache, store_raw


imaplib.Commands.setdefault("MOVE", ("SELECTED",))


imaplib._MAXLINE = 10_000_000


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
    with _futures.ThreadPoolExecutor(max_workers=max(1, min(6, len(entries)))) as ex:
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


PREFETCH = 30                    # newest messages per checked folder fetched ahead


PREFETCH_SIZE = 2 * 1024 * 1024  # … unless bigger than this


PREFETCH_SECONDS = 25            # … and only for this long per account


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


EML_MAX = 100 * 1024 * 1024


def raw_message(req):
    """-> (the message's bytes, its .eml in the cache: inline images / viewed attachments go next to it)
    req: account + folder + uid, or file: an .eml opened from disk (cached by its path, size and time)"""
    if req.get("file"):
        fpath = os.path.abspath(os.path.expanduser(req["file"]))
        try:
            st = os.stat(fpath)
            if st.st_size > EML_MAX:
                raise MailError(f"{os.path.basename(fpath)} is too big for a message ({st.st_size // 1048576} MB)")
            with open(fpath, "rb") as f:
                raw = f.read()
        except OSError as e:
            raise MailError(f"Can't read {os.path.basename(fpath)}: {e.strerror}")
        d = os.path.join(cache_dir(req), "files")
        os.makedirs(d, mode=0o700, exist_ok=True)
        key = hashlib.sha1(f"{fpath}|{st.st_size}|{st.st_mtime_ns}".encode()).hexdigest()
        return raw, os.path.join(d, key + ".eml")
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
