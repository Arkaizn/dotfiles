#!/usr/bin/env python3
"""Calendar backend for the quickshell calendar app (modules/calendar).

Speaks the standard protocols, so most providers work:
  caldav  CalDAV server: iCloud (https://caldav.icloud.com + app-specific
          password), Nextcloud, Fastmail, mailbox.org, Radicale, Baïkal, …
  ics     read-only .ics / webcal:// subscription (Google's and Outlook's
          "secret iCal address", holiday calendars, …)
  local   a .ics file on disk, read/write
  graph   Microsoft 365 work / school account (Exchange Online) through
          Microsoft Graph, read/write; signed in with a device code

Only the standard library + python-dateutil. Passwords (and Microsoft's
sign-in tokens) live in the keyring (secret-tool), never in the accounts file.

Usage:  calsync.py <command>   with the request JSON in $CAL_REQUEST,
        the answer is JSON on stdout: {"ok": true, ...} or {"ok": false, "error": "..."}

  discover      {type, url, username, password}  -> {calendars: [{href, name, color, readOnly}]}
  sync          {accounts, start, end}           -> {events: [...], errors: [...]}
  save          {account, calendar, event}       -> {}
  delete        {account, calendar, event, occurrence: bool}
  set-color     {account, calendar, color}       -> {}   (CalDAV: writes the calendar's color)
  store-secret  {id, label, password}
  forget-secret {id}
  graph-login   {id, tenant, clientId}  -> first line {step: "code", userCode, url, expiresIn},
                                           then waits for the sign-in and answers like discover
                                           (+ username); the tokens go to the keyring under id
  rediscover    {account}               -> like discover, with the account's keyring login
  import-read   {paths}                 -> {sources, total, upcoming, recurring, first, last, preview, errors}
  import        {paths, target, duplicates, upcomingOnly, alarms}
                                        -> lines {step: "progress", done, total}, then
                                           {imported, replaced, skipped, failed, created, newCalendars}
  import-undo   {account, calendar, created}  -> {removed}
"""

import base64
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
import uuid
import xml.etree.ElementTree as ET
import zipfile
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta, timezone
from urllib.parse import quote, unquote, urlencode, urljoin, urlparse
from zoneinfo import ZoneInfo

from dateutil import tz as dtz
from dateutil.rrule import rrulestr

LOCAL = dtz.tzlocal()
UTC = timezone.utc
SECRET_SERVICE = "quickshell-calendar"

NS = {
    "d": "DAV:",
    "c": "urn:ietf:params:xml:ns:caldav",
    "a": "http://apple.com/ns/ical/",
    "cs": "http://calendarserver.org/ns/",
}


class CalError(Exception):
    pass


# ── HTTP ─────────────────────────────────────────────────────────────────────

class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None  # handled by hand, so PROPFIND/REPORT keep their method + auth


_opener = urllib.request.build_opener(_NoRedirect)


def http(method, url, user=None, password=None, body=None, headers=None, depth=None, timeout=25):
    h = {"User-Agent": "quickshell-calendar/1.0"}
    if headers:
        h.update(headers)
    if depth is not None:
        h["Depth"] = str(depth)
    if user:
        token = base64.b64encode(f"{user}:{password or ''}".encode()).decode()
        h["Authorization"] = "Basic " + token
    data = body.encode() if isinstance(body, str) else body
    if data is not None and "Content-Type" not in h:
        h["Content-Type"] = "application/xml; charset=utf-8"

    for _ in range(8):
        req = urllib.request.Request(url, data=data, headers=h, method=method)
        try:
            with _opener.open(req, timeout=timeout) as r:
                return r.status, r.headers, r.read(), url
        except urllib.error.HTTPError as e:
            loc = e.headers.get("Location") if e.headers else None
            if e.code in (301, 302, 303, 307, 308) and loc:
                url = urljoin(url, loc)
                if e.code == 303:
                    method, data = "GET", None
                continue
            return e.code, e.headers, e.read(), url
        except urllib.error.URLError as e:
            raise CalError(f"Can't reach {urlparse(url).netloc or url}: {e.reason}")
        except TimeoutError:
            raise CalError(f"{urlparse(url).netloc} took too long to answer")
    raise CalError("Too many redirects")


def check_auth(status):
    if status == 401:
        raise CalError("Wrong username or password (iCloud needs an app-specific password)")
    if status == 403:
        raise CalError("Access denied by the server")


def normalize_url(url):
    url = (url or "").strip()
    if url.startswith("webcal://"):
        url = "https://" + url[len("webcal://"):]
    if url and "://" not in url:
        url = "https://" + url
    return url


# ── Secrets ──────────────────────────────────────────────────────────────────

def secret_lookup(acc_id):
    try:
        out = subprocess.run(["secret-tool", "lookup", "service", SECRET_SERVICE, "account", acc_id],
                             capture_output=True, text=True, timeout=10)
        return out.stdout.rstrip("\n") if out.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired):
        return ""


def secret_store(acc_id, label, password):
    out = subprocess.run(["secret-tool", "store", "--label", label, "service", SECRET_SERVICE, "account", acc_id],
                         input=password, capture_output=True, text=True, timeout=30)
    if out.returncode != 0:
        raise CalError("Couldn't save the password in the keyring: " + (out.stderr.strip() or "secret-tool failed"))


def secret_clear(acc_id):
    subprocess.run(["secret-tool", "clear", "service", SECRET_SERVICE, "account", acc_id],
                   capture_output=True, timeout=10)


def credentials(account):
    return account.get("username") or None, secret_lookup(account["id"]) if account.get("username") else None


# ── CalDAV discovery ─────────────────────────────────────────────────────────

PROPFIND_PRINCIPAL = """<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:"><d:prop><d:current-user-principal/></d:prop></d:propfind>"""

PROPFIND_HOME = """<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><c:calendar-home-set/></d:prop></d:propfind>"""

PROPFIND_CALENDARS = """<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"
            xmlns:a="http://apple.com/ns/ical/" xmlns:cs="http://calendarserver.org/ns/">
  <d:prop>
    <d:resourcetype/><d:displayname/><a:calendar-color/>
    <c:supported-calendar-component-set/><d:current-user-privilege-set/>
  </d:prop>
</d:propfind>"""


def xml_root(body):
    try:
        return ET.fromstring(body)
    except ET.ParseError:
        raise CalError("The server sent an answer that isn't CalDAV")


def first_href(root, path):
    el = root.find(f".//{path}/d:href", NS)
    return el.text.strip() if el is not None and el.text else None


def discover(req):
    url = normalize_url(req.get("url"))
    user, pw = req.get("username"), req.get("password")
    if not url:
        raise CalError("Enter the server address")

    principal = None
    for cand in (url, urljoin(url, "/.well-known/caldav")):
        status, _, body, final = http("PROPFIND", cand, user, pw, PROPFIND_PRINCIPAL, depth=0)
        check_auth(status)
        if status == 207:
            href = first_href(xml_root(body), "d:current-user-principal")
            if href:
                principal = urljoin(final, href)
                break
    if principal is None:
        principal = url  # some servers: the address already is the home / a calendar

    status, _, body, final = http("PROPFIND", principal, user, pw, PROPFIND_HOME, depth=0)
    check_auth(status)
    home = None
    if status == 207:
        href = first_href(xml_root(body), "c:calendar-home-set")
        home = urljoin(final, href) if href else None
    home = home or principal

    status, _, body, final = http("PROPFIND", home, user, pw, PROPFIND_CALENDARS, depth=1)
    check_auth(status)
    if status != 207:
        raise CalError(f"No calendars found (server answered {status})")

    calendars = []
    for resp in xml_root(body).findall("d:response", NS):
        href_el = resp.find("d:href", NS)
        if href_el is None or resp.find(".//d:resourcetype/c:calendar", NS) is None:
            continue
        comps = [c.get("name") for c in resp.findall(".//c:supported-calendar-component-set/c:comp", NS)]
        if comps and "VEVENT" not in comps:
            continue  # reminders / tasks only
        name_el = resp.find(".//d:displayname", NS)
        color_el = resp.find(".//a:calendar-color", NS)
        privs = resp.find(".//d:current-user-privilege-set", NS)
        writable = True
        if privs is not None and len(privs):
            writable = any(privs.find(f".//d:{p}", NS) is not None for p in ("write", "write-content", "all"))
        color = (color_el.text or "").strip() if color_el is not None else ""
        if re.fullmatch(r"#[0-9a-fA-F]{8}", color):
            color = color[:7]  # Apple sends #rrggbbaa
        href = urljoin(final, href_el.text.strip())
        calendars.append({
            "href": href,
            "name": (name_el.text or "").strip() if name_el is not None and name_el.text else href.rstrip("/").rsplit("/", 1)[-1],
            "color": color if re.fullmatch(r"#[0-9a-fA-F]{6}", color) else "",
            "readOnly": not writable,
        })
    if not calendars:
        raise CalError("Signed in, but there are no event calendars on this account")
    return {"calendars": calendars}


def discover_ics(req):
    url = normalize_url(req.get("url"))
    status, _, body, _ = http("GET", url, req.get("username"), req.get("password"))
    check_auth(status)
    if status != 200 or b"BEGIN:VCALENDAR" not in body[:4096].upper():
        raise CalError(f"That link isn't a calendar (.ics) feed (status {status})")
    text = body.decode("utf-8", "replace")
    name = re.search(r"^X-WR-CALNAME:(.*)$", unfold_text(text), re.M)
    color = re.search(r"^X-APPLE-CALENDAR-COLOR:(#[0-9a-fA-F]{6})", unfold_text(text), re.M)
    return {"calendars": [{
        "href": url,
        "name": unescape(name.group(1).strip()) if name else urlparse(url).netloc,
        "color": color.group(1) if color else "",
        "readOnly": True,
    }]}


def discover_local(req):
    path = os.path.expanduser(req.get("url") or "")
    if not path:
        raise CalError("Enter a file path")
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        with open(path, "w") as f:
            f.write(new_calendar_text())
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    if "BEGIN:VCALENDAR" not in text.upper():
        raise CalError("That file isn't an .ics calendar")
    name = re.search(r"^X-WR-CALNAME:(.*)$", unfold_text(text), re.M)
    return {"calendars": [{
        "href": path,
        "name": unescape(name.group(1).strip()) if name else os.path.splitext(os.path.basename(path))[0],
        "color": "",
        "readOnly": not os.access(path, os.W_OK),
    }]}


# ── iCalendar parsing ────────────────────────────────────────────────────────

def unfold_text(text):
    return re.sub(r"\r?\n[ \t]", "", text)


def unescape(v):
    return re.sub(r"\\([\\;,nN])", lambda m: "\n" if m.group(1) in "nN" else m.group(1), v)


def escape(v):
    return (v or "").replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\r\n", "\\n").replace("\n", "\\n")


def parse_line(line):
    """'NAME;P1=a;P2="b:c":value' -> (NAME, {P1: a, P2: b:c}, value)"""
    i, in_q = 0, False
    while i < len(line):
        ch = line[i]
        if ch == '"':
            in_q = not in_q
        elif ch == ":" and not in_q:
            break
        i += 1
    head, value = line[:i], line[i + 1:]
    parts = re.findall(r'(?:[^;"]|"[^"]*")+', head)
    name = parts[0].upper() if parts else ""
    params = {}
    for p in parts[1:]:
        if "=" in p:
            k, v = p.split("=", 1)
            params[k.upper()] = v.strip('"')
    return name, params, value


class Component:
    def __init__(self, name):
        self.name = name
        self.props = []  # (name, params, value)
        self.subs = []

    def get(self, name):
        for n, p, v in self.props:
            if n == name:
                return p, v
        return None, None

    def all(self, name):
        return [(p, v) for n, p, v in self.props if n == name]


def parse_ics(text):
    root = Component("ROOT")
    stack = [root]
    for raw in unfold_text(text).splitlines():
        if not raw.strip():
            continue
        name, params, value = parse_line(raw)
        if name == "BEGIN":
            c = Component(value.strip().upper())
            stack[-1].subs.append(c)
            stack.append(c)
        elif name == "END":
            if len(stack) > 1:
                stack.pop()
        else:
            stack[-1].props.append((name, params, value))
    return root


WINDOWS_TZ = {
    "W. Europe Standard Time": "Europe/Berlin", "Central Europe Standard Time": "Europe/Budapest",
    "Romance Standard Time": "Europe/Paris", "Central European Standard Time": "Europe/Warsaw",
    "GMT Standard Time": "Europe/London", "Greenwich Standard Time": "Atlantic/Reykjavik",
    "E. Europe Standard Time": "Europe/Chisinau", "FLE Standard Time": "Europe/Kiev",
    "GTB Standard Time": "Europe/Bucharest", "Russian Standard Time": "Europe/Moscow",
    "Eastern Standard Time": "America/New_York", "Central Standard Time": "America/Chicago",
    "Mountain Standard Time": "America/Denver", "Pacific Standard Time": "America/Los_Angeles",
    "Tokyo Standard Time": "Asia/Tokyo", "China Standard Time": "Asia/Shanghai",
    "India Standard Time": "Asia/Kolkata", "AUS Eastern Standard Time": "Australia/Sydney",
    "UTC": "UTC", "Coordinated Universal Time": "UTC",
}

_tz_cache = {}


def resolve_tz(tzid):
    if not tzid:
        return LOCAL
    if tzid in _tz_cache:
        return _tz_cache[tzid]
    zone = None
    for cand in (tzid, WINDOWS_TZ.get(tzid)):
        if not cand:
            continue
        try:
            zone = ZoneInfo(cand)
            break
        except Exception:
            pass
    if zone is None:  # e.g. "/mozilla.org/20050126_1/Europe/Berlin"
        m = re.search(r"([A-Za-z]+/[A-Za-z_\-]+(?:/[A-Za-z_\-]+)?)$", tzid)
        if m:
            try:
                zone = ZoneInfo(m.group(1))
            except Exception:
                zone = None
    _tz_cache[tzid] = zone or LOCAL
    return _tz_cache[tzid]


def parse_dt(params, value):
    """-> (aware datetime, all_day). All-day dates become local midnight."""
    value = value.strip()
    if (params or {}).get("VALUE", "").upper() == "DATE" or re.fullmatch(r"\d{8}", value):
        d = datetime.strptime(value[:8], "%Y%m%d")
        return d.replace(tzinfo=LOCAL), True
    utc = value.endswith("Z")
    d = datetime.strptime(value.rstrip("Z")[:15], "%Y%m%dT%H%M%S")
    return d.replace(tzinfo=UTC if utc else resolve_tz((params or {}).get("TZID"))), False


def parse_duration(v):
    m = re.fullmatch(r"([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?", (v or "").strip())
    if not m:
        return None
    sign = -1 if m.group(1) == "-" else 1
    w, d, h, mi, s = (int(x or 0) for x in m.groups()[1:])
    return sign * timedelta(weeks=w, days=d, hours=h, minutes=mi, seconds=s)


def ms(dt):
    return int(dt.timestamp() * 1000)


def alarms_of(ev, start, end):
    """Reminder times (ms) of one occurrence, from the event's VALARMs."""
    out = set()
    for al in ev.subs:
        if al.name != "VALARM":
            continue
        _, action = al.get("ACTION")
        if action and action.strip().upper() == "NONE":   # Apple's "no alert" placeholder
            continue
        tp, tv = al.get("TRIGGER")
        if tv is None:
            continue
        tp = tp or {}
        try:
            if tp.get("VALUE", "").upper() == "DATE-TIME" or re.match(r"^\d{8}T", tv.strip()):
                t = parse_dt(tp, tv)[0]
            else:
                d = parse_duration(tv)
                if d is None:
                    continue
                t = (end if tp.get("RELATED", "").upper() == "END" else start) + d
            # dismissed on another device already
            _, ack = al.get("ACKNOWLEDGED")
            if ack and parse_dt({}, ack)[0] >= t:
                continue
        except ValueError:
            continue
        out.add(ms(t))
    return sorted(out)


def fix_until(rule, start):
    """dateutil wants UNTIL in UTC when DTSTART has a timezone."""
    def repl(m):
        val = m.group(1)
        if val.endswith("Z"):
            return m.group(0)
        if len(val) == 8:
            u = datetime.strptime(val, "%Y%m%d").replace(hour=23, minute=59, second=59, tzinfo=start.tzinfo)
        else:
            u = datetime.strptime(val[:15], "%Y%m%dT%H%M%S").replace(tzinfo=start.tzinfo)
        return "UNTIL=" + u.astimezone(UTC).strftime("%Y%m%dT%H%M%SZ")
    return re.sub(r"UNTIL=([0-9TZ]+)", repl, rule)


def person(params, value):
    """ORGANIZER / ATTENDEE -> {name, email, status}"""
    mail = re.sub(r"^mailto:", "", (value or "").strip(), flags=re.I)
    return {"name": (params or {}).get("CN", ""), "email": mail, "status": (params or {}).get("PARTSTAT", "").upper()}


def event_fields(ev):
    def text(name):
        _, v = ev.get(name)
        return unescape(v) if v is not None else ""
    op, ov = ev.get("ORGANIZER")
    seq = text("SEQUENCE")
    return {
        "uid": text("UID"),
        "title": text("SUMMARY") or "(No title)",
        "location": text("LOCATION"),
        "description": text("DESCRIPTION"),
        "url": text("URL"),
        "status": text("STATUS").upper(),
        "organizer": person(op, ov) if ov else None,
        "attendees": [person(p, v) for p, v in ev.all("ATTENDEE")],
        "sequence": int(seq) if seq.isdigit() else 0,
    }


EMAIL_RE = re.compile(r"[^@\s<>,;:\"]+@[^@\s<>,;:\"]+\.[^@\s<>,;:\"]+")


def people_lines(ev):
    """ORGANIZER + ATTENDEE lines for ev["organizer"] / ev["attendees"]; SCHEDULE-AGENT=CLIENT:
    the app sends the invitations itself, so iCloud & co. don't send a second one"""
    def cn(name, mail):
        n = re.sub(r'[\x00-\x1f\x7f"]', "", str(name or "")).strip()[:120]
        return '"' + (n or mail) + '"'
    org = ev.get("organizer") or {}
    att = [a for a in ev.get("attendees") or [] if EMAIL_RE.fullmatch(str(a.get("email") or "").strip())]
    if not att:
        return None, None
    mail = str(org.get("email") or "").strip()
    if not EMAIL_RE.fullmatch(mail):
        raise CalError("The organizer's address isn't valid")
    org_line = fold(f"ORGANIZER;CN={cn(org.get('name'), mail)};SCHEDULE-AGENT=CLIENT:mailto:{mail}")
    lines = []
    for a in att:
        m = a["email"].strip()
        stat = a.get("status") if a.get("status") in ("ACCEPTED", "DECLINED", "TENTATIVE") else "NEEDS-ACTION"
        lines.append(fold(f"ATTENDEE;CN={cn(a.get('name'), m)};ROLE=REQ-PARTICIPANT;PARTSTAT={stat};RSVP=TRUE;"
                          f"SCHEDULE-AGENT=CLIENT:mailto:{m}"))
    return org_line, lines


def times_of(ev):
    sp, sv = ev.get("DTSTART")
    if sv is None:
        return None
    start, all_day = parse_dt(sp, sv)
    ep, evv = ev.get("DTEND")
    if evv is not None:
        end, _ = parse_dt(ep, evv)
    else:
        _, dv = ev.get("DURATION")
        dur = parse_duration(dv)
        end = start + (dur if dur is not None else (timedelta(days=1) if all_day else timedelta(0)))
    if end < start:
        end = start
    return start, end, all_day


def expand_calendar(text, rstart, rend):
    """All event occurrences overlapping [rstart, rend) -> list of dicts."""
    root = parse_ics(text)
    vevents = [c for cal in root.subs if cal.name == "VCALENDAR" for c in cal.subs if c.name == "VEVENT"]
    masters, overrides = [], {}
    for ev in vevents:
        rp, rv = ev.get("RECURRENCE-ID")
        if rv is not None:
            rid, _ = parse_dt(rp, rv)
            overrides[(event_fields(ev)["uid"], ms(rid))] = ev
        else:
            masters.append(ev)

    out = []

    def emit(ev, start, end, all_day, recurring, occurrence, rule=""):
        f = event_fields(ev)
        if f["status"] == "CANCELLED" or end <= rstart and not (end == start and rstart <= start < rend) or start >= rend:
            return
        out.append(dict(f, start=ms(start), end=ms(end), allDay=all_day, recurring=recurring,
                        occurrence=ms(occurrence), alarms=alarms_of(ev, start, end), rrule=rule))

    for ev in masters:
        t = times_of(ev)
        if t is None:
            continue
        start, end, all_day = t
        dur = end - start
        uid = event_fields(ev)["uid"]
        rules = [v for _, v in ev.all("RRULE")]
        rdates = ev.all("RDATE")
        rule_text = rules[0].strip() if rules else ""
        if not rules and not rdates:
            emit(ev, start, end, all_day, False, start)
            continue
        lines = [f"RRULE:{fix_until(r, start)}" for r in rules]
        try:
            rs = rrulestr("\n".join(lines), dtstart=start, forceset=True) if lines else rrulestr(
                "RRULE:FREQ=DAILY;COUNT=1", dtstart=start, forceset=True)
        except Exception:
            emit(ev, start, end, all_day, False, start)
            continue
        for p, v in rdates:
            for part in v.split(","):
                try:
                    rs.rdate(parse_dt(p, part)[0])
                except ValueError:
                    pass
        for p, v in ev.all("EXDATE"):
            for part in v.split(","):
                try:
                    rs.exdate(parse_dt(p, part)[0])
                except ValueError:
                    pass
        for occ in rs.between(rstart - dur - timedelta(seconds=1), rend, inc=True):
            ov = overrides.pop((uid, ms(occ)), None)
            if ov is not None:
                t2 = times_of(ov)
                if t2:
                    emit(ov, t2[0], t2[1], t2[2], True, occ, rule_text)
            else:
                emit(ev, occ, occ + dur, all_day, True, occ, rule_text)

    # overrides moved into the range from an occurrence outside it
    for (uid, occ_ms), ov in overrides.items():
        t2 = times_of(ov)
        if t2:
            emit(ov, t2[0], t2[1], t2[2], True, datetime.fromtimestamp(occ_ms / 1000, UTC))
    return out


# ── Sync ─────────────────────────────────────────────────────────────────────

def ics_time(dt):
    return dt.astimezone(UTC).strftime("%Y%m%dT%H%M%SZ")


def calendar_query(start, end):
    return f"""<?xml version="1.0" encoding="utf-8"?>
<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><d:getetag/><c:calendar-data/></d:prop>
  <c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT">
    <c:time-range start="{ics_time(start)}" end="{ics_time(end)}"/>
  </c:comp-filter></c:comp-filter></c:filter>
</c:calendar-query>"""


def fetch_calendar(account, cal, rstart, rend):
    """-> list of events of one calendar"""
    kind = account["type"]
    cal_id = cal["id"]
    events = []

    def add(items, href, etag):
        for e in items:
            e.update(calendar=cal_id, href=href, etag=etag,
                     id=f"{cal_id}|{e['uid']}|{e['start']}")
            events.append(e)

    if kind == "caldav":
        user, pw = credentials(account)
        status, _, body, final = http("REPORT", cal["href"], user, pw, calendar_query(rstart, rend), depth=1)
        check_auth(status)
        if status != 207:
            raise CalError(f"server answered {status}")
        for resp in xml_root(body).findall("d:response", NS):
            href_el = resp.find("d:href", NS)
            data_el = resp.find(".//c:calendar-data", NS)
            if href_el is None or data_el is None or not data_el.text:
                continue
            etag_el = resp.find(".//d:getetag", NS)
            add(expand_calendar(data_el.text, rstart, rend), urljoin(final, href_el.text.strip()),
                etag_el.text.strip() if etag_el is not None and etag_el.text else "")
    elif kind == "ics":
        user, pw = credentials(account)
        status, _, body, _ = http("GET", normalize_url(cal["href"]), user, pw)
        check_auth(status)
        if status != 200:
            raise CalError(f"server answered {status}")
        add(expand_calendar(body.decode("utf-8", "replace"), rstart, rend), cal["href"], "")
    elif kind == "local":
        path = os.path.expanduser(cal["href"])
        with open(path, encoding="utf-8", errors="replace") as f:
            add(expand_calendar(f.read(), rstart, rend), path, "")
    elif kind == "graph":
        events = graph_events(account, cal, rstart, rend)
    return events


def sync(req):
    rstart = datetime.fromtimestamp(req["start"] / 1000, UTC)
    rend = datetime.fromtimestamp(req["end"] / 1000, UTC)
    jobs = [(a, c) for a in req.get("accounts", []) for c in a.get("calendars", []) if c.get("enabled", True)]
    events, errors = [], []

    def run(job):
        a, c = job
        try:
            return fetch_calendar(a, c, rstart, rend), None
        except CalError as e:
            return [], {"calendar": c["id"], "account": a.get("name", ""), "message": str(e)}
        except Exception as e:  # keep the other calendars going
            return [], {"calendar": c["id"], "account": a.get("name", ""), "message": f"{type(e).__name__}: {e}"}

    # colors changed on another device (iPhone, web) come along with every sync
    def color_of(job):
        a, c = job
        if a["type"] != "caldav":
            return None
        try:
            return c["id"], read_color(a, c)
        except Exception:
            return None

    # calendars added / removed on another device, for the accounts asked about
    def list_of(a):
        try:
            return a["id"], rediscover(a)["calendars"]
        except Exception:
            return a["id"], None       # offline etc.: keep what's there

    colors, lists = {}, {}
    wanted = set(req.get("discover") or [])
    with ThreadPoolExecutor(max_workers=6) as pool:
        listed = pool.map(list_of, [a for a in req.get("accounts", [])
                                    if a["id"] in wanted and a["type"] in ("caldav", "graph")])
        for evs, err in pool.map(run, jobs):
            events.extend(evs)
            if err:
                errors.append(err)
        for r in pool.map(color_of, jobs):
            if r and r[1]:
                colors[r[0]] = r[1]
        for acc_id, cals in listed:
            if cals is not None:
                lists[acc_id] = cals
    events.sort(key=lambda e: (e["start"], not e["allDay"]))
    return {"events": events, "errors": errors, "colors": colors, "calendarLists": lists}


# ── Writing ──────────────────────────────────────────────────────────────────

def fold(line):
    out, b = [], line.encode()
    while len(b) > 75:
        cut = 75 if not out else 74
        while cut > 0 and (b[cut] & 0xC0) == 0x80:  # don't split UTF-8 sequences
            cut -= 1
        out.append(b[:cut].decode())
        b = b[cut:]
    out.append(b.decode())
    return "\r\n ".join(out)


def new_calendar_text(name=None):
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//quickshell//calendar//EN", "CALSCALE:GREGORIAN"]
    if name:
        lines.append("X-WR-CALNAME:" + escape(name))
    lines.append("END:VCALENDAR")
    return "\r\n".join(lines) + "\r\n"


def local_tzid():
    """IANA name of this machine's zone (e.g. Europe/Zurich), or None."""
    tz = os.environ.get("TZ", "").lstrip(":")
    if "/" in tz:
        return tz
    try:
        path = os.path.realpath("/etc/localtime")
        i = path.find("zoneinfo/")
        if i >= 0:
            ZoneInfo(path[i + 9:])
            return path[i + 9:]
    except Exception:
        pass
    return None


def vtimezone_lines(tzid, year):
    """VTIMEZONE for tzid with this year's rules (RFC 5545 wants one per TZID used)."""
    zone = ZoneInfo(tzid)
    t, end = datetime(year, 1, 1, tzinfo=UTC), datetime(year + 1, 1, 1, tzinfo=UTC)
    prev = t.astimezone(zone).utcoffset()
    trans = []
    while t < end:
        n = t + timedelta(hours=1)
        off = n.astimezone(zone).utcoffset()
        if off != prev:
            trans.append((n, prev, off))
            prev = off
        t = n

    def fmt(o):
        s = int(o.total_seconds())
        sign, s = ("+" if s >= 0 else "-"), abs(s)
        return f"{sign}{s // 3600:02d}{(s % 3600) // 60:02d}"

    lines = ["BEGIN:VTIMEZONE", f"TZID:{tzid}"]
    if not trans:
        lines += ["BEGIN:STANDARD", "DTSTART:19700101T000000",
                  f"TZOFFSETFROM:{fmt(prev)}", f"TZOFFSETTO:{fmt(prev)}", "END:STANDARD"]
    for at, frm, to in trans:
        local = at.astimezone(timezone(frm))        # wall clock when it happens
        kind = "DAYLIGHT" if to > frm else "STANDARD"
        wd = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"][local.weekday()]
        last = (local + timedelta(days=7)).month != local.month
        byday = f"-1{wd}" if last else f"{(local.day - 1) // 7 + 1}{wd}"
        lines += [f"BEGIN:{kind}", f"DTSTART:1970{local.strftime('%m%dT%H%M%S')}",
                  f"RRULE:FREQ=YEARLY;BYMONTH={local.month};BYDAY={byday}",
                  f"TZOFFSETFROM:{fmt(frm)}", f"TZOFFSETTO:{fmt(to)}", f"END:{kind}"]
    lines.append("END:VTIMEZONE")
    return lines


def dt_lines(name, start_ms, all_day, keep_params=None):
    if all_day:
        d = datetime.fromtimestamp(start_ms / 1000, LOCAL).date()
        return f"{name};VALUE=DATE:{d.strftime('%Y%m%d')}"
    # keep the event's own zone; new times go in the local zone (not UTC), so
    # repeats stay at the same wall-clock time across daylight saving changes
    tzid = (keep_params or {}).get("TZID") or local_tzid()
    zone = resolve_tz(tzid) if tzid else None
    if tzid and zone is not None and zone is not LOCAL:
        local = datetime.fromtimestamp(start_ms / 1000, zone)
        return f'{name};TZID={tzid}:{local.strftime("%Y%m%dT%H%M%S")}'
    return f"{name}:{ics_time(datetime.fromtimestamp(start_ms / 1000, UTC))}"


def ensure_vtimezones(text):
    """Add a VTIMEZONE for every TZID used that the calendar doesn't define yet."""
    used = set(re.findall(r";TZID=([^:;]+)[:;]", unfold_text(text)))
    defined = set(m.strip() for m in re.findall(r"^TZID:(.*)$", unfold_text(text), re.M))
    missing = []
    for tzid in sorted(used - defined):
        try:
            missing += vtimezone_lines(tzid, datetime.now().year)
        except Exception:
            pass   # not an IANA name (e.g. Outlook's): the server already knows it
    if not missing:
        return text
    i = text.upper().find("BEGIN:VEVENT")
    if i < 0:
        return text
    return text[:i] + "\r\n".join(missing) + "\r\n" + text[i:]


def split_blocks(text):
    """VCALENDAR text -> (head lines, [event blocks as line lists], tail lines)"""
    lines = unfold_text(text.replace("\r\n", "\n")).split("\n")
    head, blocks, tail, cur, depth, seen_event = [], [], [], None, 0, False
    for ln in lines:
        up = ln.upper()
        if cur is not None:
            cur.append(ln)
            if up.startswith("BEGIN:"):
                depth += 1
            elif up.startswith("END:"):
                depth -= 1
                if depth == 0:
                    blocks.append(cur)
                    cur = None
            continue
        if up == "BEGIN:VEVENT":
            cur, depth, seen_event = [ln], 1, True
        elif up == "END:VCALENDAR" or (seen_event and not up.startswith("BEGIN:")):
            tail.append(ln)
        else:
            (tail if seen_event else head).append(ln)
    return head, blocks, tail


def block_uid(block):
    for ln in block:
        if ln.upper().startswith("UID"):
            return unescape(parse_line(ln)[2]).strip()
    return None


def is_master(block):
    return not any(ln.upper().startswith("RECURRENCE-ID") for ln in block)


def join_blocks(head, blocks, tail):
    lines = [ln for ln in head if ln.strip()] + [ln for b in blocks for ln in b] + [ln for ln in tail if ln.strip()]
    if not any(ln.upper() == "END:VCALENDAR" for ln in lines):
        lines.append("END:VCALENDAR")
    return "\r\n".join(fold(ln) for ln in lines) + "\r\n"


def set_props(block, props):
    """Replace (or add) top-level properties of a VEVENT block. props: name -> full line, a list of
    lines (ATTENDEE) or None (remove)."""
    out, depth = [], 0
    names = set(props)
    for ln in block[1:-1]:
        up = ln.upper()
        if up.startswith("BEGIN:"):
            depth += 1
        elif up.startswith("END:"):
            depth -= 1
        elif depth == 0 and parse_line(ln)[0] in names:
            continue
        out.append(ln)
    new = []
    for v in props.values():
        if isinstance(v, list):
            new += v
        elif v:
            new.append(v)
    return [block[0]] + new + out + [block[-1]]


def apply_override(text, ev, now):
    """Change one occurrence of a series only: a VEVENT with RECURRENCE-ID
    (replacing an earlier change of that occurrence)."""
    head, blocks, tail = split_blocks(text)
    uid = ev["uid"]
    master_i = next((i for i, b in enumerate(blocks) if block_uid(b) == uid and is_master(b)), None)
    if master_i is None:
        raise CalError("Couldn't find the repeating event anymore — refresh and try again")
    master = blocks[master_i]
    comp = parse_ics("BEGIN:VCALENDAR\n" + "\n".join(master) + "\nEND:VCALENDAR").subs[0].subs[0]
    sp, sv = comp.get("DTSTART")
    t = times_of(comp)
    occ_ms = ev["occurrence"]
    rid_dt = datetime.fromtimestamp(occ_ms / 1000, UTC)
    rid_value = format_like(sp, sv, rid_dt)
    rid_params = ";VALUE=DATE" if t and t[2] else (f";TZID={sp['TZID']}" if sp and sp.get("TZID") and not sv.strip().endswith("Z") else "")
    rid_line = f"RECURRENCE-ID{rid_params}:{rid_value}"

    # drop an earlier change of the same occurrence
    def same_rid(b):
        for ln in b:
            if ln.upper().startswith("RECURRENCE-ID"):
                _, p, v = parse_line(ln)
                try:
                    return ms(parse_dt(p, v)[0]) == occ_ms
                except ValueError:
                    return False
        return False
    blocks = [b for b in blocks if not (block_uid(b) == uid and not is_master(b) and same_rid(b))]
    master_i = next(i for i, b in enumerate(blocks) if block_uid(b) == uid and is_master(b))

    skip = {"DTSTART", "DTEND", "DURATION", "RRULE", "RDATE", "EXDATE", "RECURRENCE-ID",
            "SUMMARY", "LOCATION", "DESCRIPTION", "DTSTAMP", "SEQUENCE", "LAST-MODIFIED"}
    kept, depth = [], 0
    for ln in master[1:-1]:
        up = ln.upper()
        if up.startswith("BEGIN:"):
            depth += 1
        elif up.startswith("END:"):
            depth -= 1
        elif depth == 0 and parse_line(ln)[0] in skip:
            continue
        kept.append(ln)
    stamp = ics_time(now)
    block = ["BEGIN:VEVENT", rid_line, f"DTSTAMP:{stamp}", f"LAST-MODIFIED:{stamp}",
             dt_lines("DTSTART", ev["start"], ev["allDay"], sp), dt_lines("DTEND", ev["end"], ev["allDay"], sp),
             f"SUMMARY:{escape(ev.get('title') or '')}"]
    for name, key in (("LOCATION", "location"), ("DESCRIPTION", "description")):
        if ev.get(key):
            block.append(f"{name}:{escape(ev[key])}")
    block += kept + ["END:VEVENT"]
    blocks.insert(master_i + 1, block)
    return ensure_vtimezones(join_blocks(head, blocks, tail)), uid


def apply_event(text, ev, now):
    """Insert or update the event (by UID) in a VCALENDAR text.
    ev["scope"] == "this" on a repeating event: only that occurrence."""
    if ev.get("scope") == "this" and ev.get("recurring") and ev.get("uid"):
        return apply_override(text, ev, now)
    head, blocks, tail = split_blocks(text)
    uid = ev.get("uid") or ""
    master_i = next((i for i, b in enumerate(blocks) if block_uid(b) == uid and is_master(b)), None)
    stamp = ics_time(now)

    def text_line(name, value):
        return f"{name}:{escape(value)}" if value else None

    if master_i is None:
        uid = uid or str(uuid.uuid4())
        block = ["BEGIN:VEVENT", f"UID:{uid}", f"DTSTAMP:{stamp}", f"CREATED:{stamp}",
                 dt_lines("DTSTART", ev["start"], ev["allDay"]), dt_lines("DTEND", ev["end"], ev["allDay"]),
                 f"SUMMARY:{escape(ev.get('title') or '')}"]
        for name, key in (("LOCATION", "location"), ("DESCRIPTION", "description")):
            if ev.get(key):
                block.append(f"{name}:{escape(ev[key])}")
        if ev.get("setRrule"):
            block.append("RRULE:" + clean_rule(ev["setRrule"]))
        org_line, att_lines = people_lines(ev)
        if att_lines:
            block += [org_line] + att_lines
        block.append("END:VEVENT")
        blocks.append(block)
        return ensure_vtimezones(join_blocks(head, blocks, tail)), uid

    block = blocks[master_i]
    comp = parse_ics("BEGIN:VCALENDAR\n" + "\n".join(block) + "\nEND:VCALENDAR").subs[0].subs[0]
    sp, _ = comp.get("DTSTART")
    old = times_of(comp)
    seq_p, seq_v = comp.get("SEQUENCE")
    props = {
        "SUMMARY": f"SUMMARY:{escape(ev.get('title') or '')}",
        "LOCATION": text_line("LOCATION", ev.get("location")),
        "DESCRIPTION": text_line("DESCRIPTION", ev.get("description")),
        "DTSTAMP": f"DTSTAMP:{stamp}",
        "LAST-MODIFIED": f"LAST-MODIFIED:{stamp}",
        "SEQUENCE": f"SEQUENCE:{int(seq_v or 0) + 1}",
    }
    # times: for a series, move the whole series by the same amount as this occurrence
    shift = ev["start"] - ev.get("occurrence", ev["start"]) if ev.get("recurring") else 0
    if old is not None:
        new_start = ms(old[0]) + shift if ev.get("recurring") else ev["start"]
        new_end = new_start + (ev["end"] - ev["start"])
        changed = (new_start != ms(old[0]) or new_end != ms(old[1]) or ev["allDay"] != old[2])
        if changed:
            props["DTSTART"] = dt_lines("DTSTART", new_start, ev["allDay"], sp)
            props["DTEND"] = dt_lines("DTEND", new_end, ev["allDay"], sp)
            props["DURATION"] = None
        if changed and ev.get("recurring"):
            # a series keeps its days (BYDAY etc. would no longer match); only the
            # time moves, and with it the dates that refer to the old time
            zone = old[0].tzinfo
            new_local = datetime.fromtimestamp(new_start / 1000, zone)
            if new_local.date() != old[0].date() or ev["allDay"] != old[2]:
                raise CalError("A repeating event can change its time here, but not its day — "
                               "do that in the app the calendar comes from")
            delta = timedelta(milliseconds=new_start - ms(old[0]))
            block = shift_series_dates(block, delta)
            for i, b in enumerate(blocks):
                if i != master_i and block_uid(b) == uid and not is_master(b):
                    blocks[i] = shift_series_dates(b, delta, names=("RECURRENCE-ID",))
    # repeat rule changed in the editor ("" = doesn't repeat any more)
    if "setRrule" in ev:
        rule = clean_rule(ev["setRrule"] or "")
        props["RRULE"] = "RRULE:" + rule if rule else None
        if not rule:
            props["RDATE"] = None
            props["EXDATE"] = None
            # the changed single occurrences of the old series would float around on their own
            blocks = [b for i, b in enumerate(blocks) if i == master_i or not (block_uid(b) == uid and not is_master(b))]
            master_i = next(i for i, b in enumerate(blocks) if block_uid(b) == uid and is_master(b))
    # guests changed in the editor (given = the editor knows them; [] removes them)
    if "attendees" in ev:
        org_line, att_lines = people_lines(ev)
        props["ORGANIZER"] = org_line
        props["ATTENDEE"] = att_lines
    blocks[master_i] = set_props(block, props)
    return ensure_vtimezones(join_blocks(head, blocks, tail)), uid


def clean_rule(rule):
    rule = (rule or "").strip()
    if rule.upper().startswith("RRULE:"):
        rule = rule[6:]
    if rule and not re.fullmatch(r"[A-Za-z0-9=;,+\-]+", rule):
        raise CalError("That repeat rule isn't valid")
    return rule


def format_like(params, value, dt):
    """Write dt in the same form (UTC / TZID / floating / date) as `value` was."""
    if (params or {}).get("VALUE", "").upper() == "DATE" or re.fullmatch(r"\d{8}", value.strip()):
        return dt.astimezone(LOCAL).strftime("%Y%m%d")
    if value.strip().endswith("Z"):
        return ics_time(dt)
    zone = resolve_tz((params or {}).get("TZID"))
    return dt.astimezone(zone).strftime("%Y%m%dT%H%M%S")


def shift_series_dates(block, delta, names=("EXDATE", "RECURRENCE-ID", "RRULE")):
    out = []
    for ln in block:
        name, params, value = parse_line(ln)
        if name in names and name != "RRULE":
            parts = [format_like(params, v, parse_dt(params, v)[0] + delta) for v in value.split(",")]
            head = ln[:len(ln) - len(value)]
            ln = head + ",".join(parts)
        elif name in names and name == "RRULE":
            def until(m):
                v = m.group(1)
                if len(v) == 8:
                    return m.group(0)
                d, _ = parse_dt({}, v)
                return "UNTIL=" + format_like({}, v, d + delta)
            ln = re.sub(r"UNTIL=([0-9TZ]+)", until, ln)
        out.append(ln)
    return out


def exclude_occurrence(text, uid, occ_ms):
    head, blocks, tail = split_blocks(text)
    for i, b in enumerate(blocks):
        if block_uid(b) == uid and is_master(b):
            comp = parse_ics("BEGIN:VCALENDAR\n" + "\n".join(b) + "\nEND:VCALENDAR").subs[0].subs[0]
            sp, _ = comp.get("DTSTART")
            t = times_of(comp)
            line = dt_lines("EXDATE", occ_ms, t[2] if t else False, sp)
            blocks[i] = [b[0], line] + b[1:]
    # drop a moved/changed copy of that occurrence too
    blocks = [b for b in blocks if not (block_uid(b) == uid and not is_master(b) and
                                        any(occ_ms == ms(parse_dt(*parse_line(ln)[1:])[0])
                                            for ln in b if ln.upper().startswith("RECURRENCE-ID")))]
    return join_blocks(head, blocks, tail)


def remove_event(text, uid):
    head, blocks, tail = split_blocks(text)
    return join_blocks(head, [b for b in blocks if block_uid(b) != uid], tail)


def save(req):
    account, cal, ev = req["account"], req["calendar"], req["event"]
    now = datetime.now(UTC)
    if account["type"] == "local":
        path = os.path.expanduser(cal["href"])
        text = open(path, encoding="utf-8").read() if os.path.exists(path) else new_calendar_text()
        text, uid = apply_event(text, ev, now)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, path)
        return {"uid": uid}
    if account["type"] == "graph":
        return graph_save(account, cal, ev)
    if account["type"] != "caldav":
        raise CalError("This calendar is read-only")

    user, pw = credentials(account)
    href = ev.get("href")
    if href and ev.get("calendar") == cal["id"]:
        status, headers, body, _ = http("GET", href, user, pw)
        check_auth(status)
        if status != 200:
            raise CalError(f"Couldn't load the event (status {status})")
        etag = headers.get("ETag") or ev.get("etag") or ""
        text, uid = apply_event(body.decode("utf-8", "replace"), ev, now)
        hdr = {"Content-Type": "text/calendar; charset=utf-8"}
        if etag:
            hdr["If-Match"] = etag
        status, _, _, _ = http("PUT", href, user, pw, text, headers=hdr)
    else:
        # new event (or moved to another calendar: create there, delete the old one)
        new_ev = dict(ev)
        if not href or ev.get("recurring"):
            new_ev["uid"] = ev.get("uid") if href else ""
        text, uid = apply_event(new_calendar_text(), dict(new_ev, uid=new_ev.get("uid") or ""), now)
        target = cal["href"].rstrip("/") + "/" + re.sub(r"[^A-Za-z0-9._-]", "_", uid) + ".ics"
        status, _, _, _ = http("PUT", target, user, pw, text,
                               headers={"Content-Type": "text/calendar; charset=utf-8", "If-None-Match": "*"})
        if status in (200, 201, 204) and href and "://" in href:   # not from a file / Microsoft 365
            http("DELETE", href, user, pw, headers={"If-Match": ev["etag"]} if ev.get("etag") else None)
    check_auth(status)
    if status == 412:
        raise CalError("The event was changed somewhere else meanwhile — refresh and try again")
    if status not in (200, 201, 204):
        raise CalError(f"The server didn't accept the event (status {status})")
    return {"uid": uid}


def delete(req):
    account, cal, ev = req["account"], req["calendar"], req["event"]
    only_this = bool(req.get("occurrence")) and ev.get("recurring")
    if account["type"] == "local":
        path = os.path.expanduser(cal["href"])
        text = open(path, encoding="utf-8").read()
        text = exclude_occurrence(text, ev["uid"], ev["occurrence"]) if only_this else remove_event(text, ev["uid"])
        with open(path + ".tmp", "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(path + ".tmp", path)
        return {}
    if account["type"] == "graph":
        return graph_delete(account, ev, only_this)
    if account["type"] != "caldav":
        raise CalError("This calendar is read-only")
    user, pw = credentials(account)
    if only_this:
        status, headers, body, _ = http("GET", ev["href"], user, pw)
        check_auth(status)
        text = exclude_occurrence(body.decode("utf-8", "replace"), ev["uid"], ev["occurrence"])
        hdr = {"Content-Type": "text/calendar; charset=utf-8"}
        if headers.get("ETag"):
            hdr["If-Match"] = headers["ETag"]
        status, _, _, _ = http("PUT", ev["href"], user, pw, text, headers=hdr)
    else:
        status, _, _, _ = http("DELETE", ev["href"], user, pw,
                               headers={"If-Match": ev["etag"]} if ev.get("etag") else None)
    check_auth(status)
    if status == 412:
        raise CalError("The event was changed somewhere else meanwhile — refresh and try again")
    if status not in (200, 204, 404):
        raise CalError(f"The server didn't delete the event (status {status})")
    return {}


# ── Calendar colors (Apple's calendar-color property, used by iCloud and most servers) ──

PROPFIND_COLOR = """<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:" xmlns:a="http://apple.com/ns/ical/"><d:prop><a:calendar-color/></d:prop></d:propfind>"""


def read_color(account, cal):
    """Color of one CalDAV calendar on the server, '#rrggbb' or None."""
    user, pw = credentials(account)
    status, _, body, _ = http("PROPFIND", cal["href"], user, pw, PROPFIND_COLOR, depth=0)
    if status != 207:
        return None
    el = xml_root(body).find(".//a:calendar-color", NS)
    c = (el.text or "").strip() if el is not None else ""
    return c[:7].lower() if re.fullmatch(r"#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?", c) else None


def set_color(req):
    account, cal, color = req["account"], req["calendar"], req.get("color", "")
    if account["type"] != "caldav":
        return {}            # subscriptions / local files: the color only lives in the app
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", color or ""):
        raise CalError("Not a color: " + str(color))
    body = f"""<?xml version="1.0" encoding="utf-8"?>
<d:propertyupdate xmlns:d="DAV:" xmlns:a="http://apple.com/ns/ical/">
  <d:set><d:prop><a:calendar-color>{color.upper()}FF</a:calendar-color></d:prop></d:set>
</d:propertyupdate>"""
    user, pw = credentials(account)
    status, _, resp, _ = http("PROPPATCH", cal["href"], user, pw, body)
    check_auth(status)
    if status == 207:
        # the multistatus says per property whether it worked
        st = xml_root(resp).find(".//d:propstat/d:status", NS)
        if st is not None and st.text and " 200 " not in st.text + " ":
            raise CalError("The server didn't take the color (" + st.text.strip() + ")")
        return {}
    if status not in (200, 204):
        raise CalError(f"The server didn't take the color (status {status})")
    return {}


# ── Microsoft 365 (Graph) ────────────────────────────────────────────────────
# Work / school accounts on Exchange Online. There's no CalDAV and EWS is being
# switched off, so this talks to Microsoft Graph. Sign-in is OAuth's device code
# flow: the dialog shows a code, you approve it on microsoft.com in any browser.
# The refresh token (+ the current access token) is kept in the keyring as JSON
# under the account id.
#
# Client: by default Microsoft Office's public client id (the one DavMail uses),
# which organizations allow unless they lock sign-ins down; an own app
# registration (public client flows on, delegated Calendars.ReadWrite +
# User.Read) can be set per account instead.

GRAPH = "https://graph.microsoft.com/v1.0"
GRAPH_CLIENT = "d3590ed6-52b3-4102-aeff-aad2292ab01c"
GRAPH_SCOPE = ("https://graph.microsoft.com/Calendars.ReadWrite "
               "https://graph.microsoft.com/User.Read offline_access")
GRAPH_EVENT_FIELDS = ("id,subject,start,end,isAllDay,location,body,onlineMeeting,isCancelled,type,"
                      "seriesMasterId,originalStart,isReminderOn,reminderMinutesBeforeStart")
GRAPH_DAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
ICS_DAYS = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]


class GraphError(CalError):
    def __init__(self, message, status):
        super().__init__(message)
        self.status = status


_tokens = {}
_token_lock = threading.Lock()


def oauth(account, endpoint, data):
    """POST to Microsoft's sign-in (devicecode / token) -> its JSON answer"""
    tenant = quote(account.get("tenant") or "organizations", safe="")
    body = urlencode(dict(data, client_id=account.get("clientId") or GRAPH_CLIENT))
    status, _, resp, _ = http("POST", f"https://login.microsoftonline.com/{tenant}/oauth2/v2.0/{endpoint}",
                              body=body, headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        return json.loads(resp)
    except ValueError:
        raise CalError(f"Microsoft sign-in answered {status}")


def oauth_error(j, fallback):
    desc = (j.get("error_description") or "").strip()
    m = re.match(r"(AADSTS\d+)", desc)
    code = m.group(1) if m else ""
    if code in ("AADSTS65001", "AADSTS90094", "AADSTS90095"):
        return f"Your organization needs an admin to approve this app first ({code})"
    if code == "AADSTS53003":
        return f"Blocked by your organization's sign-in rules (Conditional Access, {code})"
    if j.get("error") == "authorization_declined":
        return "The sign-in was declined"
    if j.get("error") == "expired_token":
        return "The code expired — start again"
    if j.get("error") == "invalid_grant":
        return fallback + (f" ({code})" if code else "")
    return desc.splitlines()[0] if desc else fallback


def token_record(j, old_refresh=None):
    return {"refresh": j.get("refresh_token") or old_refresh, "access": j["access_token"],
            "exp": time.time() + int(j.get("expires_in") or 3600)}


def graph_token(account, force=False):
    """Access token for the account, refreshed (and saved) when it ran out."""
    with _token_lock:
        t = _tokens.get(account["id"])
        if t is None:
            try:
                t = json.loads(secret_lookup(account["id"]) or "{}")
            except ValueError:
                t = {}
        if not force and t.get("access") and t.get("exp", 0) > time.time() + 120:
            _tokens[account["id"]] = t
            return t["access"]
        if not t.get("refresh"):
            raise CalError("Not signed in to Microsoft 365 — remove the account and add it again")
        j = oauth(account, "token", {"grant_type": "refresh_token", "refresh_token": t["refresh"], "scope": GRAPH_SCOPE})
        if "access_token" not in j:
            raise CalError(oauth_error(j, "The Microsoft 365 sign-in expired — remove the account and add it again"))
        t = token_record(j, t["refresh"])
        secret_store(account["id"], "Quickshell calendar: " + (account.get("name") or "Microsoft 365"), json.dumps(t))
        _tokens[account["id"]] = t
        return t["access"]


def graph(account, method, path, body=None, headers=None):
    """One Graph request -> its JSON answer ({} when empty)"""
    url = path if path.startswith("https://") else GRAPH + path
    h = {"Accept": "application/json"}
    h.update(headers or {})
    data = json.dumps(body) if body is not None else None
    if data is not None:
        h["Content-Type"] = "application/json"
    force = False
    for attempt in range(4):
        h["Authorization"] = "Bearer " + graph_token(account, force)
        status, hdrs, resp, _ = http(method, url, body=data, headers=h)
        if status == 401 and not force:       # token revoked early: refresh once
            force = True
            continue
        if status in (429, 503, 504) and attempt < 3:   # throttled
            try:
                wait = float((hdrs or {}).get("Retry-After") or 2)
            except ValueError:
                wait = 2
            time.sleep(min(wait, 10))
            continue
        break
    try:
        j = json.loads(resp) if resp else {}
    except ValueError:
        j = {}
    if status >= 400:
        err = j.get("error") if isinstance(j, dict) else None
        msg = err.get("message", "") if isinstance(err, dict) else ""
        if status == 401:
            raise GraphError("Microsoft 365 didn't accept the sign-in — remove the account and add it again", status)
        if status == 403:
            raise GraphError("Access denied" + (f": {msg}" if msg else ""), status)
        raise GraphError(msg or f"Microsoft 365 answered {status}", status)
    return j


def graph_all(account, path, headers=None):
    """GET a list, following the pages"""
    out = []
    for _ in range(100):
        j = graph(account, "GET", path, headers=headers)
        out += j.get("value", [])
        path = j.get("@odata.nextLink")
        if not path:
            break
    return out


def graph_prefer():
    # times in the local zone, so all-day events stay on their day; bodies as plain text
    return f'outlook.timezone="{local_tzid() or "UTC"}", outlook.body-content-type="text"'


def graph_dt(d, all_day):
    """Graph's {dateTime, timeZone} -> aware datetime (all-day: local midnight, like DATE values)"""
    dt = datetime.strptime((d or {}).get("dateTime", "")[:19], "%Y-%m-%dT%H:%M:%S")
    if all_day:
        return dt.replace(hour=0, minute=0, second=0, tzinfo=LOCAL)
    zone = d.get("timeZone") or "UTC"
    return dt.replace(tzinfo=UTC if "utc" in zone.lower() else resolve_tz(zone))


def graph_dt_out(when_ms, all_day, tzid):
    zone = LOCAL if all_day else ZoneInfo(tzid)
    d = datetime.fromtimestamp(when_ms / 1000, zone)
    return {"dateTime": d.strftime("%Y-%m-%dT00:00:00" if all_day else "%Y-%m-%dT%H:%M:%S"), "timeZone": tzid}


def graph_rrule(rec):
    """Graph recurrence -> RRULE text (for the editor and the "Repeats" line)"""
    if not rec:
        return ""
    p, r = rec.get("pattern") or {}, rec.get("range") or {}
    kind = p.get("type", "")
    freq = {"daily": "DAILY", "weekly": "WEEKLY", "absoluteMonthly": "MONTHLY", "relativeMonthly": "MONTHLY",
            "absoluteYearly": "YEARLY", "relativeYearly": "YEARLY"}.get(kind)
    if not freq:
        return ""
    days = ",".join(ICS_DAYS[GRAPH_DAYS.index(d)] for d in p.get("daysOfWeek") or [] if d in GRAPH_DAYS)
    parts = ["FREQ=" + freq]
    if (p.get("interval") or 1) > 1:
        parts.append(f"INTERVAL={p['interval']}")
    if kind == "weekly" and days:
        parts.append("BYDAY=" + days)
    # absolute monthly / yearly: on the start's day, which is what a plain FREQ means too
    if kind.startswith("relative") and days:
        if kind == "relativeYearly" and p.get("month"):
            parts.append(f"BYMONTH={p['month']}")
        parts.append("BYDAY=" + days)
        parts.append("BYSETPOS=" + str({"second": 2, "third": 3, "fourth": 4, "last": -1}.get(p.get("index"), 1)))
    if r.get("type") == "numbered" and r.get("numberOfOccurrences"):
        parts.append(f"COUNT={r['numberOfOccurrences']}")
    elif r.get("type") == "endDate" and r.get("endDate"):
        parts.append("UNTIL=" + r["endDate"].replace("-", ""))
    return ";".join(parts)


def graph_recurrence(rule, start_ms, all_day, tzid):
    """RRULE from the editor -> Graph recurrence (None = doesn't repeat)"""
    rule = clean_rule(rule)
    if not rule:
        return None
    m = dict(part.split("=", 1) for part in rule.upper().split(";") if "=" in part)
    freq = m.get("FREQ")
    if (set(m) - {"FREQ", "INTERVAL", "BYDAY", "COUNT", "UNTIL", "WKST"} or (m.get("BYDAY") and freq != "WEEKLY")
            or freq not in ("DAILY", "WEEKLY", "MONTHLY", "YEARLY")):
        raise CalError("Microsoft 365 can't take that repeat rule — pick a simpler one")
    start = datetime.fromtimestamp(start_ms / 1000, LOCAL if all_day else ZoneInfo(tzid))
    interval = int(m.get("INTERVAL") or 1)
    if freq == "DAILY":
        pattern = {"type": "daily", "interval": interval}
    elif freq == "WEEKLY":
        days = (m.get("BYDAY") or ICS_DAYS[start.weekday()]).split(",")
        pattern = {"type": "weekly", "interval": interval, "firstDayOfWeek": "monday",
                   "daysOfWeek": [GRAPH_DAYS[ICS_DAYS.index(d)] for d in days if d in ICS_DAYS]}
    elif freq == "MONTHLY":
        pattern = {"type": "absoluteMonthly", "interval": interval, "dayOfMonth": start.day}
    else:
        pattern = {"type": "absoluteYearly", "interval": interval, "dayOfMonth": start.day, "month": start.month}
    rng = {"type": "noEnd", "startDate": start.strftime("%Y-%m-%d"), "recurrenceTimeZone": tzid}
    if m.get("COUNT"):
        rng.update(type="numbered", numberOfOccurrences=int(m["COUNT"]))
    elif m.get("UNTIL"):
        rng.update(type="endDate", endDate=parse_dt({}, m["UNTIL"])[0].astimezone(LOCAL).strftime("%Y-%m-%d"))
    return {"pattern": pattern, "range": rng}


def graph_rules(account, master_ids):
    """series id -> RRULE, a $batch of 20 at a time (the occurrences don't carry it)"""
    rules, ids = {}, list(master_ids)
    for i in range(0, len(ids), 20):
        chunk = ids[i:i + 20]
        reqs = [{"id": str(n), "method": "GET", "url": f"/me/events/{quote(mid, safe='')}?$select=recurrence"}
                for n, mid in enumerate(chunk)]
        try:
            j = graph(account, "POST", "/$batch", {"requests": reqs})
        except CalError:
            continue      # only the "Repeats" line is missing then
        for r in j.get("responses", []):
            if r.get("status") == 200:
                rules[chunk[int(r["id"])]] = graph_rrule((r.get("body") or {}).get("recurrence"))
    return rules


def graph_events(account, cal, rstart, rend):
    """-> list of events of one Microsoft 365 calendar (repeats come expanded)"""
    def iso(dt):
        return dt.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    items = graph_all(account, f"/me/calendars/{quote(cal['href'], safe='')}/calendarView"
                               f"?startDateTime={iso(rstart)}&endDateTime={iso(rend)}"
                               f"&$top=250&$select={GRAPH_EVENT_FIELDS}",
                      headers={"Prefer": graph_prefer()})
    rules = graph_rules(account, {e["seriesMasterId"] for e in items if e.get("seriesMasterId")})
    out = []
    for e in items:
        if e.get("isCancelled"):
            continue
        all_day = bool(e.get("isAllDay"))
        try:
            start, end = graph_dt(e.get("start"), all_day), graph_dt(e.get("end"), all_day)
        except ValueError:
            continue
        recurring = e.get("type") in ("occurrence", "exception")
        occ = start
        if e.get("type") == "exception" and e.get("originalStart"):    # moved: where it was
            try:
                occ = datetime.fromisoformat(e["originalStart"].replace("Z", "+00:00")).astimezone(LOCAL)
                if all_day:   # the nearest local midnight
                    occ = (occ + timedelta(hours=12)).replace(hour=0, minute=0, second=0, microsecond=0)
            except ValueError:
                pass
        mins = e.get("reminderMinutesBeforeStart")
        uid = e.get("seriesMasterId") or e["id"]
        out.append({
            "uid": uid,
            "title": e.get("subject") or "(No title)",
            "location": (e.get("location") or {}).get("displayName") or "",
            "description": ((e.get("body") or {}).get("content") or "").strip(),
            "url": (e.get("onlineMeeting") or {}).get("joinUrl") or "",
            "status": "",
            "start": ms(start), "end": ms(end), "allDay": all_day,
            "recurring": recurring, "occurrence": ms(occ),
            "alarms": [ms(start) - int(mins) * 60000] if e.get("isReminderOn") and mins is not None else [],
            "rrule": rules.get(uid, "") if recurring else "",
            "calendar": cal["id"], "href": e["id"], "etag": e.get("@odata.etag") or "",
            "id": f"{cal['id']}|{uid}|{ms(start)}",
        })
    return out


def graph_title(ev):
    t = ev.get("title") or ""
    return "" if t == "(No title)" else t


def graph_save(account, cal, ev):
    tzid = local_tzid() or "UTC"
    href = ev.get("href")
    all_day = bool(ev["allDay"])

    if not href or ev.get("calendar") != cal["id"]:
        # new event (or moved here from another calendar: create here, delete the old one)
        if href and ev.get("recurring"):
            raise CalError("A repeating event can't move to another calendar here — do that in Outlook")
        body = {"subject": graph_title(ev), "isAllDay": all_day,
                "body": {"contentType": "text", "content": ev.get("description") or ""},
                "location": {"displayName": ev.get("location") or ""},
                "start": graph_dt_out(ev["start"], all_day, tzid), "end": graph_dt_out(ev["end"], all_day, tzid)}
        if ev.get("setRrule"):
            body["recurrence"] = graph_recurrence(ev["setRrule"], ev["start"], all_day, tzid)
        if ev.get("attendees"):
            body["attendees"] = graph_attendees(ev["attendees"])     # Exchange sends the invitations
        graph(account, "POST", f"/me/calendars/{quote(cal['href'], safe='')}/events", body)
        if href and str(ev.get("calendar", "")).startswith(account["id"] + "|"):
            graph_delete(account, ev, False)
        return {}

    # "this" = the occurrence on its own (it becomes an exception), else the series / single event
    series = ev.get("recurring") and ev.get("scope") != "this"
    target = ev["uid"] if series else href
    cur = graph(account, "GET", f"/me/events/{quote(target, safe='')}?$select=subject,body,location,start,end,isAllDay",
                headers={"Prefer": graph_prefer()})
    # only what changed, so e.g. a meeting invite's formatted text isn't replaced by its plain-text copy
    patch = {}
    if graph_title(ev) != (cur.get("subject") or ""):
        patch["subject"] = graph_title(ev)
    if (ev.get("description") or "").strip() != ((cur.get("body") or {}).get("content") or "").strip():
        patch["body"] = {"contentType": "text", "content": ev.get("description") or ""}
    if (ev.get("location") or "") != ((cur.get("location") or {}).get("displayName") or ""):
        patch["location"] = {"displayName": ev.get("location") or ""}

    old_all_day = bool(cur.get("isAllDay"))
    old_start, old_end = graph_dt(cur.get("start"), old_all_day), graph_dt(cur.get("end"), old_all_day)
    # a series moves by the same amount as this occurrence did
    new_start = ms(old_start) + ev["start"] - ev.get("occurrence", ev["start"]) if series else ev["start"]
    new_end = new_start + (ev["end"] - ev["start"])
    if new_start != ms(old_start) or new_end != ms(old_end) or all_day != old_all_day:
        if series and "setRrule" not in ev and (
                all_day != old_all_day
                or datetime.fromtimestamp(new_start / 1000, LOCAL).date() != old_start.astimezone(LOCAL).date()):
            raise CalError("A repeating event can change its time here, but not its day — do that in Outlook")
        patch.update(isAllDay=all_day, start=graph_dt_out(new_start, all_day, tzid),
                     end=graph_dt_out(new_end, all_day, tzid))
    if "setRrule" in ev and ev.get("scope") != "this":
        patch["recurrence"] = graph_recurrence(ev["setRrule"] or "", new_start, all_day, tzid)
    if "attendees" in ev:
        patch["attendees"] = graph_attendees(ev["attendees"])

    if patch:
        graph(account, "PATCH", f"/me/events/{quote(target, safe='')}", patch)
    return {}


def graph_attendees(people):
    return [{"emailAddress": {"address": a["email"].strip(), "name": (a.get("name") or "")[:120]}, "type": "required"}
            for a in people if EMAIL_RE.fullmatch(str(a.get("email") or "").strip())]


def graph_delete(account, ev, only_this):
    target = ev["href"] if only_this or not ev.get("recurring") else ev["uid"]
    try:
        graph(account, "DELETE", f"/me/events/{quote(target, safe='')}")
    except GraphError as e:
        if e.status != 404:       # gone already
            raise
    return {}


def discover_graph(account):
    me = graph(account, "GET", "/me?$select=displayName,userPrincipalName,mail")
    cals = graph_all(account, "/me/calendars?$select=id,name,hexColor,canEdit,isDefaultCalendar&$top=100")
    cals.sort(key=lambda c: not c.get("isDefaultCalendar"))
    calendars = [{
        "href": c["id"],
        "name": c.get("name") or "Calendar",
        "color": c.get("hexColor") if re.fullmatch(r"#[0-9a-fA-F]{6}", c.get("hexColor") or "") else "",
        "readOnly": not c.get("canEdit", True),
    } for c in cals]
    if not calendars:
        raise CalError("Signed in, but there are no calendars on this account")
    return {"calendars": calendars, "username": me.get("mail") or me.get("userPrincipalName") or ""}


def graph_login(req):
    """Device code sign-in. Prints the code for the dialog right away, then
    waits (polling Microsoft) until it was approved in the browser."""
    account = {"id": req["id"], "tenant": (req.get("tenant") or "").strip() or "organizations",
               "clientId": (req.get("clientId") or "").strip(), "name": "Microsoft 365"}
    j = oauth(account, "devicecode", {"scope": GRAPH_SCOPE})
    if "device_code" not in j:
        raise CalError(oauth_error(j, "Microsoft didn't start the sign-in"))
    print(json.dumps({"step": "code", "userCode": j["user_code"], "url": j["verification_uri"],
                      "expiresIn": int(j.get("expires_in") or 900)}), flush=True)
    interval = int(j.get("interval") or 5)
    deadline = time.time() + int(j.get("expires_in") or 900)
    while True:
        if time.time() > deadline:
            raise CalError("The code expired — start again")
        time.sleep(interval)
        try:
            t = oauth(account, "token", {"grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                                         "device_code": j["device_code"]})
        except CalError:
            continue      # a network hiccup while waiting: keep trying until the code runs out
        if "access_token" in t:
            break
        if t.get("error") == "authorization_pending":
            continue
        if t.get("error") == "slow_down":
            interval += 5
            continue
        raise CalError(oauth_error(t, "The sign-in didn't work"))
    rec = token_record(t)
    secret_store(account["id"], "Quickshell calendar: Microsoft 365", json.dumps(rec))
    _tokens[account["id"]] = rec
    return discover_graph(account)


# ── Calendars of an account that's already set up ──────────────────────────
# New calendars made on another device (iPhone, iCloud.com, Outlook) show up
# without signing in again: the password / tokens are in the keyring already.

def rediscover(account):
    if account["type"] == "caldav":
        user, pw = credentials(account)
        return discover({"url": account.get("url"), "username": user, "password": pw})
    if account["type"] == "graph":
        return discover_graph(account)
    raise CalError("This account has a single calendar")


# ── Importing .ics files ─────────────────────────────────────────────────────
# Exports of Apple Calendar (File → Export), Google (Settings → Import & export,
# or Takeout's .zip), Outlook, Thunderbird, Proton, …, single invites (.ics
# attachments) and folders of them. The events are copied as they are (repeat
# rules, changed occurrences, reminders, time zones) into a calendar of any
# writable account, or into new local calendars.

ICS_EXT = (".ics", ".ical", ".icalendar", ".ifb", ".vcs")
APPLE_ARCHIVE = ("That's an Apple Calendar archive (.icbu), which only Apple Calendar can read — "
                 "in Apple Calendar pick the calendar, then File → Export → Export… to get an .ics")


def decode_ics(data):
    if data.startswith(b"\xef\xbb\xbf"):
        return data[3:].decode("utf-8", "replace")
    if data[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return data.decode("utf-16", "replace")
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("cp1252", "replace")      # old Outlook / Windows exports


def read_sources(path):
    """a file, a folder or a .zip -> [(label, text)] of the calendars in it"""
    if path.startswith("file://"):
        path = unquote(urlparse(path).path)
    path = os.path.expanduser(path)
    base = os.path.basename(path.rstrip("/"))
    if base.lower().endswith(".icbu"):
        raise CalError(APPLE_ARCHIVE)
    if os.path.isdir(path):
        out = []
        for dirpath, _, files in os.walk(path):
            for f in sorted(files):
                if f.lower().endswith(ICS_EXT):
                    out += read_sources(os.path.join(dirpath, f))
        if not out:
            raise CalError(f"No .ics files in {base}")
        return out
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] == b"PK\x03\x04":                      # Google Takeout etc.
        out = []
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            for name in sorted(z.namelist()):
                if name.lower().endswith(ICS_EXT) and not name.startswith("__MACOSX/"):
                    out.append((os.path.basename(name), decode_ics(z.read(name))))
        if not out:
            raise CalError(f"No .ics files in {base}")
        return out
    text = decode_ics(data)
    if "BEGIN:VCALENDAR" not in text.upper():
        raise CalError(f"{base} isn't an .ics calendar")
    return [(base, text)]


def calendars_in(text):
    """-> [{props: [lines], comps: [(NAME, lines)]}], one per VCALENDAR in the text
    (some exports put several in one file)"""
    lines = unfold_text(text.replace("\r\n", "\n").replace("\r", "\n")).split("\n")
    cals, cur, comp, depth = [], None, None, 0
    for ln in lines:
        if not ln.strip():
            continue
        up = ln.upper()
        if cur is None:
            if up.startswith("BEGIN:VCALENDAR"):
                cur = {"props": [], "comps": []}
            continue
        if comp is not None:
            comp[1].append(ln)
            if up.startswith("BEGIN:"):
                depth += 1
            elif up.startswith("END:"):
                depth -= 1
                if depth == 0:
                    cur["comps"].append(comp)
                    comp = None
            continue
        if up.startswith("END:VCALENDAR"):
            cals.append(cur)
            cur = None
        elif up.startswith("BEGIN:"):
            comp, depth = (up[6:].strip(), [ln]), 1
        else:
            cur["props"].append(ln)
    if cur is not None:              # cut off at the end: keep what's complete
        cals.append(cur)
    return cals


def cal_prop(props, name):
    for ln in props:
        n, _, v = parse_line(ln)
        if n == name:
            return unescape(v).strip()
    return ""


def component_of(lines):
    return parse_ics("BEGIN:VCALENDAR\n" + "\n".join(lines) + "\nEND:VCALENDAR").subs[0].subs[0]


def last_end(comp, start, end):
    """ms the last occurrence ends, None = repeats forever"""
    rules = [v for _, v in comp.all("RRULE")]
    if not rules:
        last = start
        for p, v in comp.all("RDATE"):
            for part in v.split(","):
                try:
                    last = max(last, parse_dt(p, part)[0])
                except ValueError:
                    pass
        return ms(last + (end - start))
    if not any(k in rules[0].upper() for k in ("UNTIL=", "COUNT=")):
        return None
    try:
        rs = rrulestr("\n".join(f"RRULE:{fix_until(r, start)}" for r in rules), dtstart=start, forceset=True)
        last = rs.before(datetime(9000, 1, 1, tzinfo=UTC), inc=True) or start
    except Exception:
        return None
    return ms(last + (end - start))


def import_groups(paths):
    """-> (sources, groups, errors). A group is one event: its master VEVENT and
    the changed occurrences (same UID), with the VTIMEZONEs it needs."""
    sources, groups, errors = [], [], []
    for path in paths:
        try:
            files = read_sources(path)
        except (OSError, CalError, zipfile.BadZipFile) as e:
            errors.append({"path": path, "message": str(e) if isinstance(e, CalError) else
                           f"Couldn't read {os.path.basename(path)}: {getattr(e, 'strerror', None) or e}"})
            continue
        for label, text in files:
            src = {"label": label, "path": path, "name": "", "color": "", "events": 0, "other": 0, "invite": False}
            by_uid = {}
            for cal in calendars_in(text):
                src["name"] = src["name"] or cal_prop(cal["props"], "X-WR-CALNAME")
                color = cal_prop(cal["props"], "X-APPLE-CALENDAR-COLOR")
                if not src["color"] and re.fullmatch(r"#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?", color):
                    src["color"] = color[:7].lower()
                if cal_prop(cal["props"], "METHOD").upper() in ("REQUEST", "PUBLISH", "ADD"):
                    src["invite"] = cal_prop(cal["props"], "METHOD").upper() == "REQUEST"
                tzs = {}
                for name, lines in cal["comps"]:
                    if name == "VTIMEZONE":
                        tzid = next((parse_line(l)[2].strip() for l in lines if l.upper().startswith("TZID")), "")
                        if tzid:
                            tzs[tzid] = lines
                for name, lines in cal["comps"]:
                    if name == "VTIMEZONE":
                        continue
                    if name != "VEVENT":
                        src["other"] += 1          # tasks, journal entries, free/busy
                        continue
                    uid = block_uid(lines)
                    if not uid:     # the same file imported twice is still recognized
                        uid = "import-" + hashlib.sha1("\n".join(lines).encode()).hexdigest()[:24]
                        lines = [lines[0], "UID:" + uid] + lines[1:]
                    g = by_uid.get(uid)
                    if g is None:
                        g = by_uid[uid] = {"uid": uid, "source": label, "blocks": [], "tz": {}}
                    g["blocks"].append(lines)
                    for tzid in re.findall(r";TZID=\"?([^:;\"]+)\"?[:;]", "\n".join(lines)):
                        if tzid in tzs:
                            g["tz"][tzid] = tzs[tzid]
            for g in by_uid.values():
                main = next((b for b in g["blocks"] if is_master(b)), g["blocks"][0])
                try:
                    comp = component_of(main)
                    t = times_of(comp)
                except ValueError:
                    t = None
                if t is None:
                    errors.append({"path": label, "message": "An event without a valid start was left out"})
                    continue
                f = event_fields(comp)
                if f["status"] == "CANCELLED" and is_master(main):
                    continue
                g.update(title=f["title"], location=f["location"], start=ms(t[0]), end=ms(t[1]), allDay=t[2],
                         recurring=bool(comp.all("RRULE") or comp.all("RDATE")), lastEnd=last_end(comp, t[0], t[1]),
                         master=is_master(main))
                groups.append(g)
                src["events"] += 1
            sources.append(src)
    return sources, groups, errors


def import_read(req):
    sources, groups, errors = import_groups(req.get("paths") or [])
    if not groups and errors:
        raise CalError(errors[0]["message"])
    now = ms(datetime.now(UTC))
    upcoming = [g for g in groups if g["lastEnd"] is None or g["lastEnd"] >= now]
    for s in sources:
        s["past"] = sum(1 for g in groups if g["source"] == s["label"] and g not in upcoming)
    # preview: what's coming next, else the most recent
    pick = sorted(upcoming, key=lambda g: max(g["start"], now) if g["recurring"] else g["start"])[:6] \
        or sorted(groups, key=lambda g: -g["start"])[:6]
    keys = ("uid", "title", "location", "start", "end", "allDay", "recurring", "source")
    return {
        "sources": sources, "errors": errors,
        "total": len(groups), "upcoming": len(upcoming),
        "recurring": sum(1 for g in groups if g["recurring"]),
        "first": min((g["start"] for g in groups), default=0),
        "last": max((g["lastEnd"] or g["start"] for g in groups), default=0),
        "forever": any(g["lastEnd"] is None for g in groups),
        "preview": [{k: g[k] for k in keys} for g in pick],
    }


def strip_alarms(block):
    out, skip = [], 0
    for ln in block:
        up = ln.upper()
        if up == "BEGIN:VALARM":
            skip += 1
        if not skip:
            out.append(ln)
        if up == "END:VALARM" and skip:
            skip -= 1
    return out


def prepare(g, alarms, new_uid=None):
    """the group's blocks ready to write: DTSTAMP (required) added where missing,
    reminders dropped if asked, a new UID for an imported copy"""
    stamp = ics_time(datetime.now(UTC))
    out = []
    for b in g["blocks"]:
        b = list(b) if alarms else strip_alarms(b)
        if new_uid:
            b = [f"UID:{new_uid}" if parse_line(ln)[0] == "UID" else ln for ln in b]
        if not any(parse_line(ln)[0] == "DTSTAMP" for ln in b[1:-1]):
            b.insert(1, f"DTSTAMP:{stamp}")
        out.append(b)
    return out


def resource_text(blocks, tz):
    head = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//quickshell//calendar//EN", "CALSCALE:GREGORIAN"]
    for lines in tz.values():
        head += lines
    return ensure_vtimezones(join_blocks(head, blocks, ["END:VCALENDAR"]))


class Progress:
    def __init__(self, total):
        self.total, self.done, self.lock, self.last = total, 0, threading.Lock(), 0

    def step(self):
        with self.lock:
            self.done += 1
            if time.time() - self.last > 0.15 or self.done == self.total:
                self.last = time.time()
                print(json.dumps({"step": "progress", "done": self.done, "total": self.total}), flush=True)


def import_local(path, groups, mode, alarms, res, prog):
    path = os.path.expanduser(path)
    text = open(path, encoding="utf-8", errors="replace").read() if os.path.exists(path) else new_calendar_text()
    head, blocks, tail = split_blocks(text)
    have = {block_uid(b) for b in blocks}
    defined = {m.strip() for m in re.findall(r"^TZID:(.*)$", "\n".join(head + tail), re.M)}
    for g in groups:
        uid, replaced = g["uid"], False
        if uid in have:
            if mode == "skip":
                res["skipped"] += 1
                prog.step()
                continue
            if mode == "replace":
                blocks = [b for b in blocks if block_uid(b) != uid]
                replaced = True
            else:
                uid = str(uuid.uuid4())
        blocks += prepare(g, alarms, uid if uid != g["uid"] else None)
        have.add(uid)
        for tzid, lines in g["tz"].items():
            if tzid not in defined:
                head += lines
                defined.add(tzid)
        if replaced:
            res["replaced"] += 1
        else:
            res["imported"] += 1
            res["created"].append(uid)
        prog.step()
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path + ".tmp", "w", encoding="utf-8") as f:
        f.write(ensure_vtimezones(join_blocks(head, blocks, tail)))
    os.replace(path + ".tmp", path)


UID_QUERY = """<?xml version="1.0" encoding="utf-8"?>
<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><d:getetag/><c:calendar-data><c:comp name="VCALENDAR"><c:comp name="VEVENT">
    <c:prop name="UID"/></c:comp></c:comp></c:calendar-data></d:prop>
  <c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT"/></c:comp-filter></c:filter>
</c:calendar-query>"""


def caldav_uids(account, cal):
    """UID -> (href, etag) of everything in a CalDAV calendar"""
    user, pw = credentials(account)
    status, _, body, final = http("REPORT", cal["href"], user, pw, UID_QUERY, depth=1, timeout=60)
    check_auth(status)
    if status != 207:
        raise CalError(f"Couldn't read the calendar (server answered {status})")
    out = {}
    for resp in xml_root(body).findall("d:response", NS):
        href_el, data_el = resp.find("d:href", NS), resp.find(".//c:calendar-data", NS)
        if href_el is None or data_el is None or not data_el.text:
            continue
        etag_el = resp.find(".//d:getetag", NS)
        for uid in re.findall(r"^UID:(.*)$", unfold_text(data_el.text), re.M):
            out[unescape(uid.strip())] = (urljoin(final, href_el.text.strip()),
                                          etag_el.text.strip() if etag_el is not None and etag_el.text else "")
    return out


def import_caldav(account, cal, groups, mode, alarms, res, prog):
    user, pw = credentials(account)
    have = caldav_uids(account, cal)
    def one(g):
        try:
            uid, old = g["uid"], have.get(g["uid"])
            if old and mode == "skip":
                return "skipped", None
            if old and mode == "copy":
                uid, old = str(uuid.uuid4()), None
            text = resource_text(prepare(g, alarms, uid if uid != g["uid"] else None), g["tz"])
            hdr = {"Content-Type": "text/calendar; charset=utf-8"}
            if old:
                href = old[0]
                if old[1]:
                    hdr["If-Match"] = old[1]
            else:
                href = cal["href"].rstrip("/") + "/" + quote(re.sub(r"[^A-Za-z0-9._@-]", "_", uid)[:120]) + ".ics"
                hdr["If-None-Match"] = "*"
            status, _, body, _ = http("PUT", href, user, pw, text, headers=hdr)
            check_auth(status)
            if not old and (status == 412 or b"no-uid-conflict" in (body or b"")):
                return "skipped", None       # it's there already under another name
            if status not in (200, 201, 204):
                hint = "the server refused it" if status in (400, 403, 415) else f"status {status}"
                return "failed", f"{g['title']}: {hint}"
            return ("replaced", None) if old else ("imported", href)
        except CalError as e:
            return "failed", f"{g['title']}: {e}"
        finally:
            prog.step()

    with ThreadPoolExecutor(max_workers=4) as pool:
        for kind, extra in pool.map(one, groups):
            if kind == "failed":
                res["failed"].append(extra)
            else:
                res[kind] += 1
                if kind == "imported":
                    res["created"].append(extra)


def ics_reminder(comp):
    """minutes before the start of the first reminder, or None"""
    for al in comp.subs:
        if al.name != "VALARM":
            continue
        tp, tv = al.get("TRIGGER")
        d = parse_duration(tv) if tv and (tp or {}).get("RELATED", "").upper() != "END" else None
        if d is not None and d <= timedelta(0):
            return int(-d.total_seconds() // 60)
    return None


def import_graph(account, cal, groups, mode, alarms, res, prog):
    tzid = local_tzid() or "UTC"
    # Microsoft gives every event its own UID, so already imported ones are found by title + start
    have = {}
    for e in graph_all(account, f"/me/calendars/{quote(cal['href'], safe='')}/events?$select=id,subject,start,isAllDay&$top=500",
                       headers={"Prefer": graph_prefer()}):
        try:
            have[((e.get("subject") or "").strip(), ms(graph_dt(e.get("start"), bool(e.get("isAllDay")))))] = e["id"]
        except ValueError:
            pass
    for g in groups:
        try:
            if not g["master"]:
                raise CalError("a changed occurrence without its series")
            title = "" if g["title"] == "(No title)" else g["title"]
            old = have.get((title.strip(), g["start"]))
            if old and mode == "skip":
                res["skipped"] += 1
                continue
            comp = component_of(next(b for b in g["blocks"] if is_master(b)))
            body = {"subject": title, "isAllDay": g["allDay"],
                    "body": {"contentType": "text", "content": event_fields(comp)["description"]},
                    "location": {"displayName": g["location"]},
                    "start": graph_dt_out(g["start"], g["allDay"], tzid), "end": graph_dt_out(g["end"], g["allDay"], tzid)}
            rules = [v for _, v in comp.all("RRULE")]
            if rules:
                body["recurrence"] = graph_recurrence(rules[0], g["start"], g["allDay"], tzid)
                if comp.all("EXDATE") or len(g["blocks"]) > 1:
                    res["simplified"] += 1     # Microsoft 365 takes the series, not its exceptions
            mins = ics_reminder(comp) if alarms else None
            body["isReminderOn"] = mins is not None
            if mins is not None:
                body["reminderMinutesBeforeStart"] = mins
            created = graph(account, "POST", f"/me/calendars/{quote(cal['href'], safe='')}/events", body)
            if old and mode == "replace":
                graph(account, "DELETE", f"/me/events/{quote(old, safe='')}")
                res["replaced"] += 1
            else:
                res["imported"] += 1
                res["created"].append(created.get("id"))
        except CalError as e:
            res["failed"].append(f"{g['title']}: {e}")
        finally:
            prog.step()


def new_calendar_path(name):
    folder = os.path.expanduser("~/.local/share/calendars")
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "imported"
    path, n = os.path.join(folder, slug + ".ics"), 2
    while os.path.exists(path):
        path, n = os.path.join(folder, f"{slug}-{n}.ics"), n + 1
    return path


def import_events(req):
    """{paths, target: {account, calendar} | {new: true, names: {label: name}},
    duplicates: skip|replace|copy, upcomingOnly, alarms}"""
    sources, groups, errors = import_groups(req.get("paths") or [])
    now = ms(datetime.now(UTC))
    if req.get("upcomingOnly"):
        groups = [g for g in groups if g["lastEnd"] is None or g["lastEnd"] >= now]
    mode = req.get("duplicates") or "skip"
    alarms = req.get("alarms", True)
    res = {"imported": 0, "replaced": 0, "skipped": 0, "simplified": 0, "failed": [], "created": [],
           "newCalendars": [], "first": min((g["start"] for g in groups if g["start"] >= now), default=0)}
    res["failed"] += [f"{e['path']}: {e['message']}" for e in errors]
    prog = Progress(len(groups))
    print(json.dumps({"step": "progress", "done": 0, "total": len(groups)}), flush=True)
    target = req.get("target") or {}
    if target.get("new"):
        # one new local calendar per file, like the calendars they were exported from
        for s in sources:
            mine = [g for g in groups if g["source"] == s["label"]]
            if not mine:
                continue
            name = (target.get("names") or {}).get(s["label"]) or s["name"] or os.path.splitext(s["label"])[0]
            path = new_calendar_path(name)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as f:
                f.write(new_calendar_text(name))
            import_local(path, mine, mode, alarms, res, prog)
            res["newCalendars"].append({"href": path, "name": name, "color": s["color"], "readOnly": False})
        res["created"] = []           # undo = removing the new calendars
        return res
    account, cal = target["account"], target["calendar"]
    if account["type"] == "local":
        import_local(cal["href"], groups, mode, alarms, res, prog)
    elif account["type"] == "caldav":
        import_caldav(account, cal, groups, mode, alarms, res, prog)
    elif account["type"] == "graph":
        import_graph(account, cal, groups, mode, alarms, res, prog)
    else:
        raise CalError("That calendar is read-only")
    return res


def import_undo(req):
    account, cal, created = req["account"], req["calendar"], [c for c in req.get("created") or [] if c]
    if account["type"] == "local":
        path = os.path.expanduser(cal["href"])
        text = open(path, encoding="utf-8", errors="replace").read()
        head, blocks, tail = split_blocks(text)
        gone = set(created)
        with open(path + ".tmp", "w", encoding="utf-8") as f:
            f.write(join_blocks(head, [b for b in blocks if block_uid(b) not in gone], tail))
        os.replace(path + ".tmp", path)
    elif account["type"] == "caldav":
        user, pw = credentials(account)
        with ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(lambda href: http("DELETE", href, user, pw), created))
    elif account["type"] == "graph":
        for gid in created:
            try:
                graph(account, "DELETE", f"/me/events/{quote(gid, safe='')}")
            except GraphError as e:
                if e.status != 404:
                    raise
    return {"removed": len(created)}


# ── main ─────────────────────────────────────────────────────────────────────

def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        req = json.loads(os.environ.get("CAL_REQUEST") or "{}")
        if cmd == "discover":
            kind = req.get("type")
            res = discover_ics(req) if kind == "ics" else discover_local(req) if kind == "local" else discover(req)
        elif cmd == "sync":
            res = sync(req)
        elif cmd == "save":
            res = save(req)
        elif cmd == "delete":
            res = delete(req)
        elif cmd == "set-color":
            res = set_color(req)
        elif cmd == "store-secret":
            secret_store(req["id"], req.get("label") or "Quickshell calendar", req.get("password") or "")
            res = {}
        elif cmd == "forget-secret":
            secret_clear(req["id"])
            res = {}
        elif cmd == "graph-login":
            res = graph_login(req)
        elif cmd == "rediscover":
            res = rediscover(req["account"])
        elif cmd == "import-read":
            res = import_read(req)
        elif cmd == "import":
            res = import_events(req)
        elif cmd == "import-undo":
            res = import_undo(req)
        else:
            raise CalError(f"unknown command {cmd!r}")
        print(json.dumps(dict(res, ok=True)))
    except CalError as e:
        print(json.dumps({"ok": False, "error": str(e)}))
    except Exception as e:
        print(json.dumps({"ok": False, "error": f"{type(e).__name__}: {e}"}))


if __name__ == "__main__":
    main()
