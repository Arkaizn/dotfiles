from datetime import datetime
from datetime import timedelta
from urllib.parse import quote
from urllib.parse import urlencode
from zoneinfo import ZoneInfo
import json
import re
import threading
import time
from .common import CalError, ICS_DAYS, LOCAL, UTC, secret_lookup, secret_store
from .net import http
from .ical import EMAIL_RE, clean_rule, local_tzid, ms, parse_dt, resolve_tz


GRAPH = "https://graph.microsoft.com/v1.0"


GRAPH_CLIENT = "d3590ed6-52b3-4102-aeff-aad2292ab01c"


GRAPH_SCOPE = ("https://graph.microsoft.com/Calendars.ReadWrite "
               "https://graph.microsoft.com/User.Read offline_access")


GRAPH_EVENT_FIELDS = ("id,subject,start,end,isAllDay,location,body,onlineMeeting,isCancelled,type,"
                      "seriesMasterId,originalStart,isReminderOn,reminderMinutesBeforeStart")


GRAPH_DAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]


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
