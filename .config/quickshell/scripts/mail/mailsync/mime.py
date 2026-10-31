from email.utils import getaddresses
from html.parser import HTMLParser
import base64
import email
import email.header
import email.policy
import email.utils
import os
import re


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


def header_time(v):
    """a Date header -> ms since 1970 (0: none / unreadable)"""
    try:
        return int(email.utils.parsedate_to_datetime(str(v)).timestamp() * 1000) if v else 0
    except Exception:
        return 0


def header_block(raw):
    """the message's header lines as sent (folded lines kept), at most 64 KB"""
    end = raw.find(b"\r\n\r\n")
    if end < 0:
        end = raw.find(b"\n\n")
    head = raw[:end] if end >= 0 else raw
    return head[:65536].decode("utf-8", "replace").replace("\r\n", "\n")


def auth_results(msg):
    """the receiving servers' checks (Authentication-Results; the topmost, i.e. your own
    provider's, wins) -> {"spf": "pass", "dkim": "fail", "dmarc": "none", …}"""
    out = {}
    for h in msg.get_all("Authentication-Results") or []:
        for k in ("spf", "dkim", "dmarc"):
            m = re.search(r"\b" + k + r"\s*=\s*([a-z]+)", str(h), re.I)
            if m and k not in out:
                out[k] = m.group(1).lower()
    return out


def mime_tree(msg, depth=0, out=None):
    """how the message is built: [{depth, type, name, size, disposition, charset}], parents first"""
    out = [] if out is None else out
    if len(out) >= 200:
        return out
    multi = msg.is_multipart()
    out.append({"depth": depth, "type": msg.get_content_type(),
                "name": "" if multi else decode_header(msg.get_filename()),
                "size": 0 if multi else len(msg.get_payload(decode=True) or b""),
                "disposition": msg.get_content_disposition() or "", "charset": msg.get_content_charset() or ""})
    if multi:
        for part in msg.get_payload():
            mime_tree(part, depth + 1, out)
    return out


def safe_name(name):
    name = re.sub(r"[/\\\x00-\x1f]", "_", name)
    name = re.sub(r"\.{2,}", ".", name).strip(" .") or "attachment"
    return name[:180]


def free_path(dest, name, overwrite=False):
    """dest/name, or "name (1).ext", "name (2).ext", … when taken"""
    path = os.path.join(dest, name)
    base, ext = os.path.splitext(path)
    n = 1
    while os.path.exists(path) and not overwrite:
        path = f"{base} ({n}){ext}"
        n += 1
    return path
