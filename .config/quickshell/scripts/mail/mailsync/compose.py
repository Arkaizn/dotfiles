from email.headerregistry import Address
from email.message import EmailMessage
from email.utils import format_datetime
from email.utils import make_msgid
import email
import email.header
import email.policy
import email.utils
import html
import mimetypes
import os
import re
import time
import urllib.parse
import urllib.request

from qsbackend import lazy
imaplib = lazy('imaplib')
smtplib = lazy('smtplib')
from .common import MailError, TIMEOUT, friendly, password_of, server_of, tls_context
from .imapproto import quote_box
from .htmlclean import image_kind
from .imap import Imap, flags


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
