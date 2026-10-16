#!/usr/bin/env python3
"""Calendar backend for the quickshell calendar app (modules/calendar).

Speaks the standard protocols, so most providers work:
  caldav  CalDAV server: iCloud (https://caldav.icloud.com + app-specific
          password), Nextcloud, Fastmail, mailbox.org, Radicale, Baïkal, …
  ics     read-only .ics / webcal:// subscription (Google's and Outlook's
          "secret iCal address", holiday calendars, …)
  local   a .ics file on disk, read/write

Only the standard library + python-dateutil. Passwords live in the keyring
(secret-tool), never in the accounts file.

Usage:  calsync.py <command>   with the request JSON in $CAL_REQUEST,
        the answer is JSON on stdout: {"ok": true, ...} or {"ok": false, "error": "..."}

  discover      {type, url, username, password}  -> {calendars: [{href, name, color, readOnly}]}
  sync          {accounts, start, end}           -> {events: [...], errors: [...]}
  save          {account, calendar, event}       -> {}
  delete        {account, calendar, event, occurrence: bool}
  store-secret  {id, label, password}
  forget-secret {id}
"""

import base64
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
import uuid
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta, timezone
from urllib.parse import urljoin, urlparse
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


def event_fields(ev):
    def text(name):
        _, v = ev.get(name)
        return unescape(v) if v is not None else ""
    return {
        "uid": text("UID"),
        "title": text("SUMMARY") or "(No title)",
        "location": text("LOCATION"),
        "description": text("DESCRIPTION"),
        "url": text("URL"),
        "status": text("STATUS").upper(),
    }


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

    with ThreadPoolExecutor(max_workers=6) as pool:
        for evs, err in pool.map(run, jobs):
            events.extend(evs)
            if err:
                errors.append(err)
    events.sort(key=lambda e: (e["start"], not e["allDay"]))
    return {"events": events, "errors": errors}


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
    """Replace (or add) top-level properties of a VEVENT block. props: name -> full line or None (remove)."""
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
    new = [v for v in props.values() if v]
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
        text, _ = apply_event(text, ev, now)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, path)
        return {}
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
        text, _ = apply_event(body.decode("utf-8", "replace"), ev, now)
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
        if status in (200, 201, 204) and href:
            http("DELETE", href, user, pw, headers={"If-Match": ev["etag"]} if ev.get("etag") else None)
    check_auth(status)
    if status == 412:
        raise CalError("The event was changed somewhere else meanwhile — refresh and try again")
    if status not in (200, 201, 204):
        raise CalError(f"The server didn't accept the event (status {status})")
    return {}


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
        elif cmd == "store-secret":
            secret_store(req["id"], req.get("label") or "Quickshell calendar", req.get("password") or "")
            res = {}
        elif cmd == "forget-secret":
            secret_clear(req["id"])
            res = {}
        else:
            raise CalError(f"unknown command {cmd!r}")
        print(json.dumps(dict(res, ok=True)))
    except CalError as e:
        print(json.dumps({"ok": False, "error": str(e)}))
    except Exception as e:
        print(json.dumps({"ok": False, "error": f"{type(e).__name__}: {e}"}))


if __name__ == "__main__":
    main()
