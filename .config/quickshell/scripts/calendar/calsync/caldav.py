from datetime import datetime
from urllib.parse import urljoin
from urllib.parse import urlparse
import os
import re
from qsbackend import lazy
_futures = lazy('concurrent.futures')   # (not "futures": functions use that name)
from .common import CalError, NS, UTC, credentials
from .files import atomic_write_text, file_lock
from .net import PROPFIND_CALENDARS, PROPFIND_COLOR, PROPFIND_HOME, PROPFIND_PRINCIPAL, check_auth, first_href, http, normalize_url, xml_root
from .ical import apply_event, exclude_occurrence, expand_calendar, ics_time, new_calendar_text, remove_event, unescape, unfold_text
from .graph import discover_graph, graph_delete, graph_events, graph_save


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
    with _futures.ThreadPoolExecutor(max_workers=6) as pool:
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


def save(req):
    account, cal, ev = req["account"], req["calendar"], req["event"]
    now = datetime.now(UTC)
    if account["type"] == "local":
        path = os.path.expanduser(cal["href"])
        with file_lock(path):
            text = open(path, encoding="utf-8").read() if os.path.exists(path) else new_calendar_text()
            text, uid = apply_event(text, ev, now)
            atomic_write_text(path, text)
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
        with file_lock(path):
            text = open(path, encoding="utf-8").read()
            text = exclude_occurrence(text, ev["uid"], ev["occurrence"]) if only_this else remove_event(text, ev["uid"])
            atomic_write_text(path, text)
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


def rediscover(account):
    if account["type"] == "caldav":
        user, pw = credentials(account)
        return discover({"url": account.get("url"), "username": user, "password": pw})
    if account["type"] == "graph":
        return discover_graph(account)
    raise CalError("This account has a single calendar")
