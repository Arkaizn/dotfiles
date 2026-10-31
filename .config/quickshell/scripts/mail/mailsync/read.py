import email
import email.header
import email.policy
import email.utils
import hashlib
import mimetypes
import os
import re
import subprocess
from .common import MailError
from .mime import addresses, auth_results, decode_header, free_path, header_block, header_time, html_to_text, message_parts, mime_tree, part_text, safe_name
from .files import atomic_write, cache_dir
from .htmlclean import localize_images, sanitize
from .imap import raw_message


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
                atomic_write(p, part.get_payload(decode=True) or b"")
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
            "date": decode_header(msg.get("Date")), "dateTs": header_time(msg.get("Date")),
            "messageId": (re.findall(r"<[^>]+>", str(msg.get("Message-ID") or "")) or [""])[0],
            "references": re.findall(r"<[^>]+>", str(msg.get("References") or "")),
            "unsubscribe": decode_header(msg.get("List-Unsubscribe")),
        },
        # "Show headers": the header as sent, the servers' checks, the MIME parts
        "source": {"header": header_block(raw), "auth": auth_results(msg), "parts": mime_tree(msg),
                   "returnPath": decode_header(msg.get("Return-Path")).strip("<>"),
                   "sender": addresses(msg.get("Sender"))},
    }


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
    path = free_path(dest, name, req.get("overwrite"))
    with open(path, "wb") as f:
        f.write(part.get_payload(decode=True) or b"")
    return {"path": path}


def save_eml(req):
    """the whole message as an .eml file (opens in any mail app) in req["dest"], named after its subject"""
    raw, _ = raw_message(req)
    msg = email.message_from_bytes(raw, policy=email.policy.default)
    dest = os.path.expanduser(req.get("dest") or "")
    if not dest:
        raise MailError("No folder to save to")
    os.makedirs(dest, exist_ok=True)
    path = free_path(dest, safe_name(decode_header(msg.get("Subject")) or "message")[:120] + ".eml")
    with open(path, "wb") as f:
        f.write(raw)
    return {"path": path}


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
    base = (path[:-4] if path else os.path.join(cache_dir(req), "view")) + f".view{i}"
    os.makedirs(base, mode=0o700, exist_ok=True)
    os.chmod(base, 0o700)
    fpath = os.path.join(base, name)
    data = part.get_payload(decode=True) or b""
    if not os.path.exists(fpath):
        atomic_write(fpath, data)
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
