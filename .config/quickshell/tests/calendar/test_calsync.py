#!/usr/bin/env python3
"""Tests for scripts/calendar/calsync.py (no network: local servers only).

    python3 -I tests/calendar/test_calsync.py
"""
import http.server
import os
import json
import shutil
import subprocess
import tempfile
import threading
import time
import unittest
import zipfile

import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPT = os.path.join(ROOT, "scripts", "calendar", "calsync.py")      # the launcher the shell runs
sys.path.insert(0, os.path.dirname(SCRIPT))
import calsync            # noqa: E402  (the package: names resolve on use)
import calsync.net        # noqa: E402


class Recorder(http.server.BaseHTTPRequestHandler):
    """Answers every request; remembers the Authorization header it got."""
    seen = []
    redirect_to = None
    body = b"BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n"

    def do_GET(self):
        type(self).seen.append((self.server.server_port, self.headers.get("Authorization")))
        if type(self).redirect_to and self.server.server_port != type(self).redirect_to[1]:
            self.send_response(302)
            self.send_header("Location", type(self).redirect_to[0])
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Length", str(len(type(self).body)))
        self.end_headers()
        self.wfile.write(type(self).body)

    def log_message(self, *a):
        pass


def serve():
    s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Recorder)
    threading.Thread(target=s.serve_forever, daemon=True).start()
    return s


class Redirects(unittest.TestCase):
    def setUp(self):
        Recorder.seen = []
        self.a, self.b = serve(), serve()

    def tearDown(self):
        for s in (self.a, self.b): s.shutdown(); s.server_close()

    def test_login_not_sent_to_another_host(self):
        pb = self.b.server_port
        Recorder.redirect_to = (f"http://127.0.0.1:{pb}/cal.ics", pb)
        status, _, body, url = calsync.http("GET", f"http://127.0.0.1:{self.a.server_port}/cal", user="me", password="secret")
        self.assertEqual(status, 200)
        self.assertTrue(url.endswith(f":{pb}/cal.ics"))
        first, second = Recorder.seen
        self.assertTrue(first[1].startswith("Basic "))     # the server it was meant for
        self.assertIsNone(second[1])                        # not the one it was sent on to

    def test_https_to_http_refused(self):
        with self.assertRaises(calsync.CalError):
            calsync._check_redirect("https://dav.example.org/cal", "http://dav.example.org/cal")
        calsync._check_redirect("https://a.example/x", "https://b.example/y")   # https → https: fine
        calsync._check_redirect("http://127.0.0.1:1/x", "http://127.0.0.1:2/y")

    def test_origin(self):
        self.assertEqual(calsync._origin("https://Dav.Example.org/x"), ("https", "dav.example.org", 443))
        self.assertNotEqual(calsync._origin("https://a/x"), calsync._origin("https://a:8443/x"))

    def test_response_cap(self):
        old = calsync.net.MAX_RESPONSE
        calsync.net.MAX_RESPONSE = 10
        Recorder.redirect_to = None
        try:
            with self.assertRaises(calsync.CalError):
                calsync.http("GET", f"http://127.0.0.1:{self.a.server_port}/cal")
        finally:
            calsync.net.MAX_RESPONSE = old


def cli(cmd, req):
    """one request the way CalendarStore sends it: JSON in $CAL_REQUEST, JSON on stdout"""
    env = dict(os.environ, CAL_REQUEST=json.dumps(req))
    out = subprocess.run(["python3", "-I", SCRIPT, cmd], env=env, capture_output=True, text=True, timeout=60).stdout
    return json.loads(out.strip().splitlines()[-1])


def event(title, start_ms, uid=""):
    return {"title": title, "start": start_ms, "end": start_ms + 3600_000, "allDay": False,
            "scope": "all", "setRrule": False, "uid": uid, "location": "", "description": ""}


class LocalCalendar(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="caltest-")
        self.path = os.path.join(self.dir, "sub", "mine.ics")
        r = cli("discover", {"type": "local", "url": self.path})
        self.assertTrue(r["ok"], r)
        self.cal = dict(r["calendars"][0], id="c1", enabled=True)
        self.acc = {"id": "a1", "name": "Local", "type": "local", "calendars": [self.cal]}
        self.t0 = int(time.time() // 3600 * 3600 * 1000) + 86400_000

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def events(self):
        r = cli("sync", {"accounts": [self.acc], "start": self.t0 - 86400_000, "end": self.t0 + 30 * 86400_000})
        self.assertTrue(r["ok"], r)
        return r["events"]

    def test_save_sync_delete(self):
        r = cli("save", {"account": self.acc, "calendar": self.cal, "event": event("Dentist", self.t0)})
        self.assertTrue(r["ok"], r)
        evs = self.events()
        self.assertEqual([e["title"] for e in evs], ["Dentist"])
        self.assertEqual(oct(os.stat(self.path).st_mode & 0o777), "0o600")
        r = cli("delete", {"account": self.acc, "calendar": self.cal, "event": dict(evs[0], uid=r["uid"])})
        self.assertTrue(r["ok"], r)
        self.assertEqual(self.events(), [])
        self.assertEqual([f for f in os.listdir(os.path.dirname(self.path)) if f.endswith(".tmp")], [])

    def test_two_saves_at_once_both_kept(self):
        procs = []
        for i in range(4):
            env = dict(os.environ, CAL_REQUEST=json.dumps({"account": self.acc, "calendar": self.cal,
                                                           "event": event(f"E{i}", self.t0 + i * 7200_000)}))
            procs.append(subprocess.Popen(["python3", "-I", SCRIPT, "save"], env=env, stdout=subprocess.PIPE))
        for p in procs:
            p.communicate(timeout=60)
        self.assertEqual(sorted(e["title"] for e in self.events()), ["E0", "E1", "E2", "E3"])

    def test_zip_import_size_limit(self):
        z = os.path.join(self.dir, "bomb.zip")
        with zipfile.ZipFile(z, "w", zipfile.ZIP_DEFLATED) as f:
            f.writestr("big.ics", "BEGIN:VCALENDAR\n" + "X" * (51 * 1024 * 1024) + "\nEND:VCALENDAR\n")
        r = cli("import-read", {"paths": [z]})
        text = json.dumps(r)
        self.assertIn("too much", text)


class IcsSubscription(unittest.TestCase):
    def test_ics_over_http(self):
        Recorder.redirect_to = None
        Recorder.body = ("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:x1\r\nSUMMARY:Holiday\r\n"
                         "DTSTART;VALUE=DATE:20300101\r\nDTEND;VALUE=DATE:20300102\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n").encode()
        s = serve()
        try:
            url = f"http://127.0.0.1:{s.server_port}/h.ics"
            r = cli("discover", {"type": "ics", "url": url})
            self.assertTrue(r["ok"], r)
            cal = dict(r["calendars"][0], id="h", enabled=True)
            acc = {"id": "a", "name": "Sub", "type": "ics", "calendars": [cal]}
            start = int(time.mktime((2029, 12, 31, 0, 0, 0, 0, 0, -1)) * 1000)
            r = cli("sync", {"accounts": [acc], "start": start, "end": start + 5 * 86400_000})
            self.assertTrue(r["ok"], r)
            self.assertEqual([e["title"] for e in r["events"]], ["Holiday"])
        finally:
            s.shutdown(); s.server_close()


if __name__ == "__main__":
    unittest.main()
