from datetime import datetime
from datetime import timedelta
from dateutil.rrule import rrulestr
from urllib.parse import quote
from urllib.parse import unquote
from urllib.parse import urljoin
from urllib.parse import urlparse
import hashlib
import io
import json
import os
import re
import threading
import time

from qsbackend import lazy
_futures = lazy('concurrent.futures')   # (not "futures": functions use that name)
uuid = lazy('uuid')
zipfile = lazy('zipfile')
from .common import CalError, NS, UTC, credentials
from .files import atomic_write_text, file_lock
from .net import check_auth, http, xml_root
from .ical import block_uid, ensure_vtimezones, event_fields, fix_until, ics_time, is_master, join_blocks, local_tzid, ms, new_calendar_text, parse_dt, parse_duration, parse_ics, parse_line, split_blocks, times_of, unescape, unfold_text
from .graph import GraphError, graph, graph_all, graph_dt, graph_dt_out, graph_prefer, graph_recurrence


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
            # a zip can unpack to far more than it weighs: check the sizes it
            # declares before reading anything (200 MB of calendars, 50 MB each)
            infos = [i for i in z.infolist() if i.filename.lower().endswith(ICS_EXT) and not i.filename.startswith("__MACOSX/")]
            if sum(i.file_size for i in infos) > 200 * 1024 * 1024 or any(i.file_size > 50 * 1024 * 1024 for i in infos):
                raise CalError(f"{base} unpacks to too much (over 200 MB, or a file over 50 MB)")
            for info in sorted(infos, key=lambda i: i.filename):
                out.append((os.path.basename(info.filename), decode_ics(z.read(info))))
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
    atomic_write_text(path, ensure_vtimezones(join_blocks(head, blocks, tail)))


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

    with _futures.ThreadPoolExecutor(max_workers=4) as pool:
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
        with file_lock(path):
            text = open(path, encoding="utf-8", errors="replace").read()
            head, blocks, tail = split_blocks(text)
            gone = set(created)
            atomic_write_text(path, join_blocks(head, [b for b in blocks if block_uid(b) not in gone], tail))
    elif account["type"] == "caldav":
        user, pw = credentials(account)
        with _futures.ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(lambda href: http("DELETE", href, user, pw), created))
    elif account["type"] == "graph":
        for gid in created:
            try:
                graph(account, "DELETE", f"/me/events/{quote(gid, safe='')}")
            except GraphError as e:
                if e.status != 404:
                    raise
    return {"removed": len(created)}
