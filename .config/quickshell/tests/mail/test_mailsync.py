#!/usr/bin/env python3
"""Tests for scripts/mail/mailsync.py: unit tests + end to end against fakeserver.py.

    python3 -I tests/mail/test_mailsync.py        (no network, no keyring needed)
"""

import email
import email.policy
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "..", "scripts", "mail", "mailsync.py")
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(SCRIPT))

import mailsync as M                       # noqa: E402
from fakeserver import FakeMail             # noqa: E402
from sample import ME, NEWSLETTER_HTML, fill, message, tiny_pdf   # noqa: E402


# ── Unit ─────────────────────────────────────────────────────────────────────

class Unit(unittest.TestCase):
    def test_mutf7(self):
        for s in ["INBOX", "Entwürfe", "Projekte/Entwürfe & Ideen", "日本語", "a&b", "Ünïcödé/Ä"]:
            self.assertEqual(M.mutf7_decode(M.mutf7_encode(s)), s)
        self.assertEqual(M.mutf7_encode("Entwürfe"), "Entw&APw-rfe")
        self.assertEqual(M.mutf7_encode("a&b"), "a&-b")
        self.assertEqual(M.quote_box('My "Box"'), '"My \\"Box\\""')

    def test_uid_set(self):
        self.assertEqual(M.uid_set([5, 3, 4, 9, 10, 1]), "1,3:5,9:10")
        self.assertEqual(M.uid_set([7]), "7")

    def test_parse_fetch_with_literals(self):
        data = [(b'1 (UID 7 FLAGS (\\Seen $Forwarded) BODY[HEADER.FIELDS (FROM SUBJECT)] {30}', b"From: a@b.c\r\nSubject: hi\r\n\r\n"),
                b' INTERNALDATE "01-Oct-2026 10:00:00 +0000")',
                b'2 (UID 9 FLAGS ())']
        msgs = M.parse_fetch(data)
        self.assertEqual(len(msgs), 2)
        self.assertEqual(msgs[0]["UID"], "7")
        self.assertEqual(msgs[0]["FLAGS"], ["\\Seen", "$Forwarded"])
        self.assertEqual(msgs[0]["BODY[HEADER.FIELDS (FROM SUBJECT)]"], b"From: a@b.c\r\nSubject: hi\r\n\r\n")
        self.assertEqual(msgs[0]["INTERNALDATE"], "01-Oct-2026 10:00:00 +0000")
        self.assertEqual(msgs[1]["FLAGS"], [])

    def test_parse_list(self):
        data = [b'(\\HasNoChildren \\Sent) "/" "Sent Messages"', b'(\\Noselect) "." "[Gmail]"',
                (b'(\\HasNoChildren) "/" {8}', b"Odd Name")]
        f = M.parse_list(data)
        self.assertEqual(f[0]["raw"], "Sent Messages")
        self.assertIn("\\sent", f[0]["flags"])
        self.assertEqual(f[1]["delim"], ".")
        self.assertEqual(f[2]["raw"], "Odd Name")

    def test_roles(self):
        self.assertEqual(M.role_of("INBOX", []), "inbox")
        self.assertEqual(M.role_of("[Gmail]/Gesendet", ["\\sent"]), "sent")
        self.assertEqual(M.role_of("Gelöschte Elemente", []), "trash")
        self.assertEqual(M.role_of("INBOX.Spam", []), "junk")
        self.assertEqual(M.role_of("Projekte", []), "")

    def test_bodystructure(self):
        raw = message("x", "A", "a@x.org", "plain body", html="<p>hi</p>",
                      attach=[("a.pdf", b"%PDF", "application/pdf")], inline_image=True)
        from fakeserver import bodystructure
        msg = email.message_from_bytes(raw, policy=email.policy.compat32)
        toks = M.parse_tokens(M.tokenize([bodystructure(msg).encode()]))
        parts = M.walk_structure(toks[0])
        types = [p["type"] for p in parts]
        self.assertEqual(types, ["text/plain", "text/html", "image/png", "application/pdf"])
        self.assertEqual([p["section"] for p in parts], ["1.1", "1.2.1", "1.2.2", "2"])
        atts = [p for p in parts if M.is_attachment(p)]
        self.assertEqual([p["filename"] for p in atts], ["a.pdf"])           # the cid logo isn't one
        self.assertEqual(M.preview_part(parts)["section"], "1.1")

    def test_source(self):
        raw = message("x", "A", "a@x.org", "plain body", html="<p>hi</p>",
                      attach=[("a.pdf", b"%PDF", "application/pdf")])
        raw = (b"Authentication-Results: mx.me.org; spf=pass smtp.mailfrom=x.org; dkim=fail header.d=x.org\r\n"
               b"Authentication-Results: relay.org; dkim=pass; dmarc=none\r\n") + raw
        msg = email.message_from_bytes(raw, policy=email.policy.default)
        head = M.header_block(raw)
        self.assertIn("Subject: x", head)
        self.assertNotIn("plain body", head)
        self.assertEqual(M.auth_results(msg), {"spf": "pass", "dkim": "fail", "dmarc": "none"})   # topmost wins
        tree = M.mime_tree(msg)
        self.assertEqual([(p["depth"], p["type"]) for p in tree],
                         [(0, "multipart/mixed"), (1, "multipart/alternative"), (2, "text/plain"), (2, "text/html"), (1, "application/pdf")])
        self.assertEqual(tree[-1]["name"], "a.pdf")
        self.assertEqual(tree[-1]["size"], 4)

    def test_eml_file(self):
        raw = message("Rechnung / Oktober", "A", "a@x.org", "plain body", attach=[("a.pdf", b"%PDF", "application/pdf")])
        with tempfile.TemporaryDirectory() as d:
            src = os.path.join(d, "in.eml")
            with open(src, "wb") as f:
                f.write(raw)
            req = {"file": src, "cache": os.path.join(d, "cache")}
            b = M.body(req)
            self.assertEqual(b["headers"]["subject"], "Rechnung / Oktober")
            self.assertGreater(b["headers"]["dateTs"], 0)
            self.assertEqual([a["name"] for a in b["attachments"]], ["a.pdf"])
            out = M.save_eml(dict(req, dest=os.path.join(d, "out")))["path"]
            self.assertEqual(os.path.basename(out), "Rechnung _ Oktober.eml")
            self.assertEqual(open(out, "rb").read(), raw)
            self.assertTrue(M.save_eml(dict(req, dest=os.path.join(d, "out")))["path"].endswith("Oktober (1).eml"))
            with self.assertRaises(M.MailError):
                M.body({"file": os.path.join(d, "missing.eml"), "cache": d})

    def test_decode_header_and_addresses(self):
        self.assertEqual(M.decode_header("=?utf-8?q?Gr=C3=BCsse?= aus =?utf-8?q?Z=C3=BCrich?="), "Grüsse aus Zürich")
        a = M.addresses('"Fischer, Lea" <lea@example.org>, tom@example.org')
        self.assertEqual(a, [{"name": "Fischer, Lea", "email": "lea@example.org"}, {"name": "", "email": "tom@example.org"}])

    def test_decode_partial(self):
        import base64
        b = base64.encodebytes("Grüezi mitenand, wie gaht's?".encode())[:20]       # cut in the middle
        self.assertTrue(M.decode_partial(b, "base64", "utf-8").startswith("Grüezi"))
        self.assertEqual(M.decode_partial(b"Gr=C3=BCsse=", "quoted-printable", "utf-8"), "Grüsse")

    def test_html_to_text(self):
        t = M.html_to_text("<style>x{}</style><p>Hallo&nbsp;Welt</p><ul><li>eins</li><li>zwei</li></ul><script>bad()</script>")
        self.assertIn("Hallo Welt", t)
        self.assertIn("• eins", t)
        self.assertNotIn("bad", t)
        self.assertNotIn("x{}", t)

    def test_sanitize_blocks_remote(self):
        h, blocked = M.sanitize_html(NEWSLETTER_HTML, False, {"logo@example.org": "/tmp/logo.png"})
        self.assertNotIn("<script", h)
        self.assertNotIn("alert", h)
        self.assertNotIn("onload", h)
        self.assertNotIn("onclick", h)
        self.assertNotIn("javascript:", h)
        self.assertNotIn("tracker.example.net", h)
        self.assertEqual(blocked, 2)                       # the pixel and the css background
        self.assertIn('src="file:///tmp/logo.png"', h)
        self.assertIn('href="https://shop.example.net/sale"', h)
        self.assertNotIn("color:red", h)                   # <style> blocks are gone

    def test_sanitize_allows_remote_when_asked(self):
        h, blocked = M.sanitize_html(NEWSLETTER_HTML, True)
        self.assertEqual(blocked, 0)
        self.assertIn("https://tracker.example.net/open.gif", h)
        self.assertNotIn("bg.png", h)                      # css url() never: Qt can't show it anyway

    def test_sanitize_odd_input(self):
        h, _ = M.sanitize_html('<img src="file:///etc/passwd"><a href="file:///x">x</a><iframe src="https://e.x">y</iframe>z')
        self.assertNotIn("passwd", h)
        self.assertNotIn("file:///x", h)
        self.assertNotIn("iframe", h)
        self.assertIn("z", h)

    def test_autoconfig_xml(self):
        xml = """<clientConfig version="1.1"><emailProvider id="x.org"><domain>x.org</domain>
          <incomingServer type="pop3"><hostname>pop.x.org</hostname><port>995</port><socketType>SSL</socketType></incomingServer>
          <incomingServer type="imap"><hostname>imap.x.org</hostname><port>993</port><socketType>SSL</socketType>
            <username>%EMAILLOCALPART%</username></incomingServer>
          <outgoingServer type="smtp"><hostname>smtp.x.org</hostname><port>587</port><socketType>STARTTLS</socketType>
            <username>%EMAILADDRESS%</username></outgoingServer></emailProvider></clientConfig>"""
        c = M.parse_autoconfig(xml, "anna@x.org")
        self.assertEqual(c["imap"], {"host": "imap.x.org", "port": 993, "security": "ssl"})
        self.assertEqual(c["smtp"], {"host": "smtp.x.org", "port": 587, "security": "starttls"})
        self.assertEqual(c["username"], "anna")
        plain = xml.replace("<socketType>SSL</socketType>\n            <username>", "<socketType>plain</socketType>\n            <username>")
        self.assertIsNone(M.parse_autoconfig(plain, "anna@x.org"))       # never a plain-text server from the net

    def test_autoconfig_presets(self):
        os.environ["MAIL_NO_NETWORK"] = "1"
        try:
            c = M.autoconfig({"email": "anna@icloud.com"})
            self.assertEqual(c["imap"]["host"], "imap.mail.me.com")
            self.assertEqual(c["smtp"]["port"], 587)
            self.assertIn("app-specific", c["hint"])
            self.assertEqual(M.autoconfig({"email": "x@gmail.com"})["provider"], "gmail")
            self.assertEqual(M.autoconfig({"email": "x@unknown-domain.example"})["source"], "guessed")
            with self.assertRaises(M.MailError):
                M.autoconfig({"email": "x@outlook.com"})
            with self.assertRaises(M.MailError):
                M.autoconfig({"email": "not an address"})
        finally:
            del os.environ["MAIL_NO_NETWORK"]

    def test_server_checks(self):
        acc = {"imap": {"host": "mail.example.org", "port": 143, "security": "none"}}
        with self.assertRaises(M.MailError):
            M.server_of(acc, "imap")                       # no plain text over the network
        acc["imap"]["host"] = "127.0.0.1"
        self.assertEqual(M.server_of(acc, "imap"), ("127.0.0.1", 143, "none"))
        with self.assertRaises(M.MailError):
            M.server_of({"imap": {"host": "-oProxy", "port": 1, "security": "ssl"}}, "imap")

    def test_build_message(self):
        acc = {"email": ME, "displayName": "Me Myself"}
        with tempfile.NamedTemporaryFile(suffix=".txt", delete=False) as f:
            f.write(b"hello")
        msg, rcpts = M.build_message(acc, {"to": [{"name": "Lea", "email": "lea@example.org"}], "cc": ["tom@example.org"],
                                           "bcc": ["secret@example.org"], "subject": "Hi\r\nBcc: injected",
                                           "text": "Grüsse", "inReplyTo": "<a@b>", "references": ["<z@b>", "bad ref"],
                                           "attachments": [f.name]})
        os.unlink(f.name)
        self.assertEqual(sorted(rcpts), ["lea@example.org", "secret@example.org", "tom@example.org"])
        b = msg.as_bytes()
        self.assertNotIn(b"secret@example.org", b)           # Bcc never in the message
        self.assertNotIn(b"\nBcc:", b)
        self.assertEqual(msg["References"], "<z@b> <a@b>")
        self.assertEqual(msg["From"], "Me Myself <me@example.com>")
        self.assertEqual(len(list(msg.iter_attachments())), 1)
        with self.assertRaises(M.MailError):
            M.build_message(acc, {"to": ["not-an-address"]})
        with self.assertRaises(M.MailError):
            M.build_message(acc, {"to": []})


# ── End to end against the fake server ───────────────────────────────────────

class EndToEnd(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srv = FakeMail(user=ME, password="pw-123").start()
        fill(cls.srv)
        cls.acc = {"id": "acc-test", "name": "Test", "email": ME, "displayName": "Me", "username": ME, "provider": "",
                   "imap": {"host": "127.0.0.1", "port": cls.srv.imap_port, "security": "none"},
                   "smtp": {"host": "127.0.0.1", "port": cls.srv.smtp_port, "security": "none"}}
        cls.cache = tempfile.mkdtemp()

    @classmethod
    def tearDownClass(cls):
        cls.srv.stop()

    def run_cmd(self, cmd, req, secrets=None):
        env = dict(os.environ, MAIL_REQUEST=json.dumps(req),
                   MAIL_FAKE_SECRETS=json.dumps(secrets if secrets is not None else {"acc-test": "pw-123"}))
        out = subprocess.run([sys.executable, "-I", SCRIPT, cmd], env=env, capture_output=True, text=True, timeout=60)
        self.assertEqual(out.stderr, "", out.stderr)
        return json.loads(out.stdout)

    def ok(self, cmd, req, **kw):
        r = self.run_cmd(cmd, req, **kw)
        self.assertTrue(r["ok"], r.get("error"))
        return r

    def inbox(self):
        r = self.ok("sync", {"accounts": [{"account": self.acc, "folders": [{"path": "INBOX"}]}]})
        self.assertEqual(r["results"][0]["error"], "")
        return r["results"][0]["folders"][0]

    def test_01_login(self):
        r = self.ok("test", {"account": self.acc, "password": "pw-123"}, secrets={})
        self.assertIn("Trash", [f["path"] for f in r["folders"]])
        bad = self.run_cmd("test", {"account": self.acc, "password": "wrong"}, secrets={})
        self.assertFalse(bad["ok"])
        self.assertIn("app password", bad["error"])
        none = self.run_cmd("folders", {"account": self.acc}, secrets={})
        self.assertIn("No password in the keyring", none["error"])

    def test_02_folders(self):
        r = self.ok("folders", {"account": self.acc})
        roles = {f["path"]: f["role"] for f in r["folders"]}
        self.assertEqual(roles["INBOX"], "inbox")
        self.assertEqual(roles["Sent"], "sent")
        self.assertEqual(roles["Trash"], "trash")
        self.assertIn("Projekte/Entwürfe & Ideen", roles)
        inbox = next(f for f in r["folders"] if f["path"] == "INBOX")
        self.assertEqual((inbox["total"], inbox["unread"]), (7, 4))
        self.assertEqual(r["folders"][0]["path"], "INBOX")          # inbox first

    def test_99_create_folder(self):
        r = self.ok("create-folder", {"account": self.acc, "name": "Rechnungen 2026 ä", "parent": "Projekte/Entwürfe & Ideen"})
        self.assertEqual(r["path"], "Projekte/Entwürfe & Ideen/Rechnungen 2026 ä")
        new = next(f for f in r["folders"] if f["path"] == r["path"])
        self.assertEqual((new["name"], new["depth"], new["total"]), ("Rechnungen 2026 ä", 2, 0))
        under = self.ok("create-folder", {"account": self.acc, "name": "Steuer", "parent": "Sent"})
        paths = [f["path"] for f in under["folders"]]
        self.assertEqual(paths[paths.index("Sent") + 1], "Sent/Steuer")      # right under its parent
        top = self.ok("create-folder", {"account": self.acc, "name": "Belege", "parent": ""})
        self.assertEqual(top["path"], "Belege")
        for bad, why in [({"name": "", "parent": ""}, "needs a name"), ({"name": "a/b", "parent": ""}, "can't contain"),
                         ({"name": "belege", "parent": ""}, "already"), ({"name": "x", "parent": "Nope"}, "gone"),
                         ({"name": "x\ny", "parent": ""}, "can't be used")]:
            res = self.run_cmd("create-folder", dict(bad, account=self.acc))
            self.assertFalse(res["ok"])
            self.assertIn(why, res["error"])

    def test_03_sync(self):
        f = self.inbox()
        self.assertEqual(len(f["new"]), 7)
        self.assertEqual(f["unread"], 4)
        by_subject = {m["subject"]: m for m in f["new"]}
        bill = by_subject["Rechnung Oktober – Nr. 4711"]
        self.assertEqual(bill["attachments"], 1)
        self.assertTrue(bill["flagged"])
        self.assertTrue(bill["preview"].startswith("Guten Tag, anbei Ihre Rechnung"))
        self.assertEqual(by_subject["Fotos vom Ausflug"]["attachments"], 2)
        self.assertEqual(by_subject["Herbst-Angebote 🍂"]["attachments"], 0)        # inline logo only
        re2 = [m for m in f["new"] if m["subject"] == "Re: Wochenende planen"]
        self.assertTrue(any("<plan-1@example.org>" in m["refs"] for m in re2))
        self.assertNotIn(">", by_subject["Re: Wochenende planen"]["preview"][:1])
        # again, knowing all: nothing new, flags of the known ones
        f2 = self.ok("sync", {"accounts": [{"account": self.acc, "folders": [
            {"path": "INBOX", "uidvalidity": f["uidvalidity"], "uids": f["uids"]}]}]})["results"][0]["folders"][0]
        self.assertEqual(f2["new"], [])
        self.assertEqual(len(f2["flags"]), 7)
        # another uidvalidity: everything is new again
        f3 = self.ok("sync", {"accounts": [{"account": self.acc, "folders": [
            {"path": "INBOX", "uidvalidity": 999, "uids": f["uids"]}]}]})["results"][0]["folders"][0]
        self.assertEqual(len(f3["new"]), 7)

    def test_04_limit(self):
        r = self.ok("sync", {"limit": 2, "accounts": [{"account": self.acc, "folders": [{"path": "INBOX"}]}]})
        f = r["results"][0]["folders"][0]
        self.assertEqual(len(f["new"]), 2)
        self.assertEqual(f["total"], 7)

    def uid_of(self, subject, folder="INBOX"):
        f = self.ok("sync", {"accounts": [{"account": self.acc, "folders": [{"path": folder}]}]})["results"][0]["folders"][0]
        return next(m["uid"] for m in f["new"] if m["subject"] == subject)

    def test_05_body(self):
        uid = self.uid_of("Herbst-Angebote 🍂")
        r = self.ok("body", {"account": self.acc, "folder": "INBOX", "uid": uid, "cache": self.cache})
        self.assertEqual(r["remoteBlocked"], 2)
        self.assertIn("<h1>Herbst-Angebote</h1>", r["html"])
        self.assertIn("file://", r["html"])                        # inline logo written out
        self.assertEqual(r["text"].strip(), "Unsere neuen Produkte sind da.")
        self.assertEqual(r["headers"]["from"][0]["email"], "news@shop.example.net")
        # from the cache now: works with the server's password gone
        r2 = self.run_cmd("body", {"account": self.acc, "folder": "INBOX", "uid": uid, "cache": self.cache, "allowRemote": True},
                          secrets={})
        self.assertTrue(r2["ok"], r2.get("error"))
        self.assertEqual(r2["remoteBlocked"], 0)
        # the message is still unread (BODY.PEEK)
        f = self.inbox()
        self.assertEqual(f["unread"], 4)

    def test_05b_prefetch(self):
        cache = tempfile.mkdtemp()
        r = self.ok("sync", {"cache": cache, "accounts": [{"account": self.acc, "folders": [{"path": "INBOX"}]}]})
        f = r["results"][0]["folders"][0]
        self.assertEqual(len([n for n in os.listdir(cache) if n.endswith(".eml")]), 7)
        for n in os.listdir(cache):
            self.assertEqual(os.stat(os.path.join(cache, n)).st_mode & 0o777, 0o600)
        # every body opens without a connection now
        uid = f["new"][0]["uid"]
        b = self.run_cmd("body", {"account": self.acc, "folder": "INBOX", "uid": uid, "uidvalidity": f["uidvalidity"],
                                  "cache": cache}, secrets={})
        self.assertTrue(b["ok"], b.get("error"))
        # still unread on the server (BODY.PEEK)
        self.assertEqual(self.inbox()["unread"], 4)

    def test_06_attachment(self):
        uid = self.uid_of("Rechnung Oktober – Nr. 4711")
        b = self.ok("body", {"account": self.acc, "folder": "INBOX", "uid": uid, "cache": self.cache})
        self.assertEqual([a["name"] for a in b["attachments"]], ["Rechnung-4711.pdf"])
        dest = tempfile.mkdtemp()
        r = self.ok("attachment", {"account": self.acc, "folder": "INBOX", "uid": uid, "cache": self.cache, "index": 0, "dest": dest})
        with open(r["path"], "rb") as f:
            self.assertEqual(f.read(), b"%PDF-1.4 fake pdf")
        r2 = self.ok("attachment", {"account": self.acc, "folder": "INBOX", "uid": uid, "cache": self.cache, "index": 0, "dest": dest})
        self.assertTrue(r2["path"].endswith("Rechnung-4711 (1).pdf"))         # never overwrites
        bad = self.run_cmd("attachment", {"account": self.acc, "folder": "INBOX", "uid": uid, "cache": self.cache, "index": 5, "dest": dest})
        self.assertFalse(bad["ok"])

    def test_07_flags(self):
        uid = self.uid_of("Herbst-Angebote 🍂")
        self.ok("flags", {"account": self.acc, "folder": "INBOX", "uids": [uid], "add": ["seen", "flagged"]})
        f = self.inbox()
        self.assertEqual(f["unread"], 3)
        m = next(m for m in f["new"] if m["uid"] == uid)
        self.assertTrue(m["seen"] and m["flagged"])
        self.ok("flags", {"account": self.acc, "folder": "INBOX", "uids": [uid], "remove": ["seen", "flagged"]})
        self.assertEqual(self.inbox()["unread"], 4)

    def test_08_search(self):
        r = self.ok("search", {"account": self.acc, "folder": "INBOX", "query": "Bahnhof"})
        self.assertEqual(len(r["uids"]), 1)
        self.assertEqual(r["messages"][0]["subject"], "Re: Wochenende planen")
        r = self.ok("search", {"account": self.acc, "folder": "INBOX", "query": "Bahnhof", "known": r["uids"]})
        self.assertEqual(r["messages"], [])                  # known ones aren't fetched again

    def test_09_move_delete(self):
        uid = self.srv.add("INBOX", message("Zum Verschieben", "X", "x@example.org", "move me"))
        self.ok("move", {"account": self.acc, "folder": "INBOX", "uids": [uid], "to": "Archive"})
        self.assertIn("Zum Verschieben", [m["subject"] for m in self.ok("sync", {"accounts": [{"account": self.acc, "folders": [
            {"path": "Archive"}]}]})["results"][0]["folders"][0]["new"]])
        auid = self.uid_of("Zum Verschieben", "Archive")
        self.ok("delete", {"account": self.acc, "folder": "Archive", "uids": [auid], "trash": "Trash"})
        tuid = self.uid_of("Zum Verschieben", "Trash")
        self.ok("delete", {"account": self.acc, "folder": "Trash", "uids": [tuid], "trash": "Trash"})     # for good
        self.assertEqual(len(self.srv.boxes["Trash"].msgs), 0)
        self.assertNotIn("Zum Verschieben", [m["subject"] for m in self.inbox()["new"]])

    def test_10_send(self):
        with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as f:
            f.write(b"%PDF attach")
        uid = self.uid_of("Re: Wochenende planen")
        r = self.ok("send", {"account": self.acc, "sentFolder": "Sent", "message": {
            "to": [{"name": "Lea", "email": "lea@example.org"}], "bcc": ["hidden@example.org"],
            "subject": "Re: Wochenende planen", "text": "Bis Samstag!\n\n> Super, dann 9 Uhr",
            "inReplyTo": "<plan-2@example.org>", "references": ["<plan-1@example.org>"], "attachments": [f.name],
            "replyTo": {"folder": "INBOX", "uid": uid, "flag": "answered"}}})
        os.unlink(f.name)
        self.assertEqual(r["warning"], "")
        sent = self.srv.sent[-1]
        self.assertEqual(sorted(sent["to"]), ["hidden@example.org", "lea@example.org"])
        msg = email.message_from_bytes(sent["raw"], policy=email.policy.default)
        self.assertEqual(msg["In-Reply-To"], "<plan-2@example.org>")
        self.assertIsNone(msg["Bcc"])
        self.assertEqual([p.get_filename() for p in msg.iter_attachments()], [os.path.basename(f.name)])
        saved = self.srv.boxes["Sent"].msgs[-1]
        self.assertIn("\\Seen", saved["flags"])
        self.assertIn(b"Bis Samstag!", saved["raw"])
        answered = next(m for m in self.srv.boxes["INBOX"].msgs if m["uid"] == uid)
        self.assertIn("\\Answered", answered["flags"])
        # Gmail files sent mail by itself: no second copy
        n = len(self.srv.boxes["Sent"].msgs)
        self.ok("send", {"account": dict(self.acc, provider="gmail"), "sentFolder": "Sent",
                         "message": {"to": ["lea@example.org"], "subject": "x", "text": "y"}})
        self.assertEqual(len(self.srv.boxes["Sent"].msgs), n)

    def test_11_send_errors(self):
        bad = self.run_cmd("send", {"account": self.acc, "message": {"to": ["lea@example.org"], "subject": "x", "text": "y"}},
                           secrets={"acc-test": "nope"})
        self.assertFalse(bad["ok"])
        self.assertIn("didn't accept the login", bad["error"])
        r = self.run_cmd("send", {"account": self.acc, "message": {"to": ["lea@example.org"], "attachments": ["/nonexistent/x.pdf"]}})
        self.assertIn("Attachment not found", r["error"])

    def test_12_unicode_folder(self):
        self.srv.add("Projekte/Entwürfe & Ideen", message("Idee", "Me", ME, "eine Idee"))
        f = self.ok("sync", {"accounts": [{"account": self.acc, "folders": [{"path": "Projekte/Entwürfe & Ideen"}]}]})["results"][0]["folders"][0]
        self.assertEqual([m["subject"] for m in f["new"]], ["Idee"])

    def test_13_errors_are_per_account(self):
        broken = dict(self.acc, id="acc-broken", imap={"host": "127.0.0.1", "port": 1, "security": "none"})
        r = self.ok("sync", {"accounts": [{"account": broken, "folders": [{"path": "INBOX"}]},
                                          {"account": self.acc, "folders": [{"path": "INBOX"}]}]},
                    secrets={"acc-test": "pw-123", "acc-broken": "x"})
        self.assertIn("refused", r["results"][0]["error"])
        self.assertEqual(r["results"][1]["error"], "")
        self.assertEqual(len(r["results"][1]["folders"][0]["new"]), 7)

    def test_14_folder_list_in_sync(self):
        r = self.ok("sync", {"accounts": [{"account": self.acc, "listFolders": True, "folders": []}]})
        fl = r["results"][0]["folderList"]
        self.assertEqual(fl[0]["role"], "inbox")
        self.assertTrue(all("unread" in f for f in fl))

    def test_15_unknown_command(self):
        out = subprocess.run([sys.executable, "-I", SCRIPT, "nope"], capture_output=True, text=True)
        self.assertFalse(json.loads(out.stdout)["ok"])


# ── Part 2 ───────────────────────────────────────────────────────────────────

class NewsletterLayout(unittest.TestCase):
    def test_tricks(self):
        src = ('<div style="display:none;max-height:0;overflow:hidden">Preheader <b>text</b> <div>nested</div></div>'
               '<table width="600" style="max-width:640px"><tr><td style="font-size:28px;line-height:14px;margin-top:-30px">Head</td></tr>'
               '<tr><td style="letter-spacing:-2px;color:#999">Footer</td></tr>'
               '<tr><td style="mso-hide:all">Outlook only</td></tr></table><p>After</p>'
               '<img src="data:image/svg+xml;base64,PHN2Zy8+"><img src="data:image/png;base64,iVBORw0KGgo=">')
        r = M.sanitize(src)
        self.assertEqual(r["width"], 640)
        for gone in ("Preheader", "nested", "Outlook only", "line-height", "-30px", "letter-spacing", "svg"):
            self.assertNotIn(gone, r["html"])
        for kept in ("Head", "Footer", "<p>After</p>", "color:#999", "font-size:28px", "data:image/png"):
            self.assertIn(kept, r["html"])
        self.assertEqual(M.sanitize("<p>plain flowing text</p>")["width"], 0)
        r = M.sanitize('<div style="Margin: 0 auto;max-width:500px;color:red">x</div>')
        self.assertNotIn("auto", r["html"])
        self.assertIn("color:red", r["html"])
        # a wide picture in a flowing message isn't a fixed layout
        self.assertEqual(M.sanitize('<p>Hi</p><img width="900" style="width:900px" src="data:image/png;base64,iVBORw0KGgo=">')["width"], 0)


class RichCompose(unittest.TestCase):
    def test_html_with_pasted_picture(self):
        d = tempfile.mkdtemp()
        pic = os.path.join(d, "p.png")
        with open(pic, "wb") as f:
            f.write(b"\x89PNG\r\n\x1a\n" + b"\0" * 32)
        acc = {"email": "me@example.com", "displayName": "Me"}
        html = ('<html><head><meta name="qrichtext" content="1" /></head><body style=" font-family:\'Noto Sans\'; font-size:14px;">'
                f'<p><span style=" font-weight:700;">Hi</span><img src="file://{pic}" width="200" />'
                '<img src="file:///etc/passwd" /><img src="file://' + d + '/../../etc/hostname" /></p></body></html>')
        msg, _ = M.build_message(acc, {"to": [{"name": "", "email": "x@example.org"}], "subject": "s", "text": "Hi [image]",
                                       "html": html, "inlineDir": d, "attachments": []})
        self.assertEqual([p.get_content_type() for p in msg.walk()],
                         ["multipart/alternative", "text/plain", "multipart/related", "text/html", "image/png"])
        out = msg.get_body(("html",)).get_content()
        self.assertIn("cid:", out)
        self.assertNotIn("file://", out)                     # nothing local leaves, not even via ../
        self.assertNotIn("qrichtext", out)
        self.assertIn("Arial, Helvetica, sans-serif", out)
        self.assertEqual(msg.get_body(("plain",)).get_content().strip(), "Hi [image]")


class RemoteImages(unittest.TestCase):
    """allowed remote images: fetched by mailsync, checked, cached; never Qt"""
    @classmethod
    def setUpClass(cls):
        import http.server, threading
        png = b"\x89PNG\r\n\x1a\n" + b"\0" * 64
        cls.hits = []
        class H(http.server.BaseHTTPRequestHandler):
            def log_message(self, *a): pass
            def do_GET(self):
                cls.hits.append(self.path)
                body = {"/a.png": png, "/evil.svg": b"<svg xmlns='http://www.w3.org/2000/svg'/>"}.get(self.path)
                if self.path == "/redir":
                    self.send_response(302); self.send_header("Location", "file:///etc/passwd"); self.end_headers(); return
                if body is None:
                    self.send_response(404); self.end_headers(); return
                self.send_response(200); self.end_headers(); self.wfile.write(body)
        cls.srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()
        cls.base = f"http://127.0.0.1:{cls.srv.server_address[1]}"

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()

    def test_localize(self):
        cache = tempfile.mkdtemp()
        os.environ["MAIL_TEST_LOCAL_IMAGES"] = "1"
        try:
            src = (f'<p><img src="{self.base}/a.png" alt="logo"><img src="{self.base}/evil.svg">'
                   f'<img src="{self.base}/pixel.gif" width="1" height="1"><img src="{self.base}/redir">'
                   f'<img src="data:image/svg+xml;base64,PHN2Zy8+"></p>')
            out, _ = M.sanitize_html(src, True, {}, False)
            out = M.localize_images(out, cache)
            self.assertIn('src="file://' + cache, out)
            self.assertNotIn(self.base, out)                 # nothing left for Qt to fetch
            self.assertNotIn("svg", out)                     # neither the SVG file nor the data: one
            self.assertNotIn("/pixel.gif", self.hits)        # tracking pixel never asked for
            files = os.listdir(cache)
            self.assertTrue(any(f.endswith(".png") for f in files))
            for f in files:
                self.assertEqual(os.stat(os.path.join(cache, f)).st_mode & 0o777, 0o600)
            # again: from the cache, no request
            n = len(self.hits)
            M.localize_images(M.sanitize_html(src, True, {}, False)[0], cache)
            self.assertEqual(len([h for h in self.hits[n:] if h == "/a.png"]), 0)
        finally:
            del os.environ["MAIL_TEST_LOCAL_IMAGES"]

    def test_local_network_refused(self):
        self.assertFalse(M.public_host("127.0.0.1"))
        self.assertFalse(M.public_host("192.168.1.1"))
        self.assertFalse(M.public_host("localhost"))


class Part2Unit(unittest.TestCase):
    def test_dark_style(self):
        h, _ = M.sanitize_html('<p style="color:#000;background-color:#fff;font-weight:bold" bgcolor="#fff">'
                               '<font color="red">x</font></p>', adapt=True)
        self.assertNotIn("#000", h)
        self.assertNotIn("bgcolor", h)                      # a white page background goes away
        self.assertNotIn("#fff", h)
        self.assertNotIn('color="red"', h)
        self.assertIn('color="#ff8383"', h)                 # red stays red, lighter
        self.assertIn("font-weight:bold", h)
        h2, _ = M.sanitize_html('<p style="color:#000">x</p>')
        self.assertIn("color:#000", h2)                     # original style keeps them

    def test_dark_colors(self):
        self.assertEqual(M.dark_color("#ffffff", "bg"), "")
        self.assertEqual(M.dark_color("transparent", "bg"), None)
        lum = lambda c: M.colorsys.rgb_to_hls(*M.parse_color(c)[:3])[1]
        self.assertLess(lum(M.dark_color("#1a73e8", "bg")), 0.25)     # a blue button: dark blue
        self.assertGreater(lum(M.dark_color("#333", "text")), 0.75)     # dark text: light
        self.assertEqual(M.dark_color("#eeeeee", "text"), "#eeeeee")    # light text stays
        self.assertEqual(M.dark_color("#222222", "bg"), "#222222")      # a dark card stays
        self.assertEqual(M.parse_color("rgb(255, 0, 0)"), (1.0, 0.0, 0.0, 1.0))
        self.assertTrue(M.dark_color("hsla(0, 0%, 100%, 0.5)", "text").startswith("rgba("))
        self.assertEqual(M.dark_style("background:#fff url(none);color:#000").split(";")[1], "color:#e6e6e6")
        self.assertNotIn("background", M.dark_style("background-color:#ffffff;color:#000"))

    def test_clean_account(self):
        good = {"email": "a@x.org", "imap": {"host": "imap.x.org", "port": 993, "security": "ssl"},
                "smtp": {"host": "smtp.x.org", "port": 465, "security": "ssl"}, "color": "#123456", "provider": "evil"}
        c, errs = M.clean_account(good)
        self.assertEqual(errs, [])
        self.assertEqual(c["provider"], "")
        self.assertEqual(c["username"], "a@x.org")
        bad = dict(good, email="nope", imap={"host": "imap.x.org", "port": 143, "security": "none"},
                   smtp={"host": "-o x", "port": 99999, "security": "ssl"}, signature=5)
        _, errs = M.clean_account(bad)
        self.assertEqual(len(errs), 4)

    def test_invitation_ics(self):
        ev = {"uid": "abc-1@quickshell", "title": "Evil\r\nATTENDEE:mailto:x@evil.org; a, b", "start": 1793430000000,
              "end": 1793433600000, "location": "Raum 1", "description": "Line 1\nLine 2", "sequence": 2,
              "organizer": {"name": 'Me "the" Boss', "email": "me@example.com"},
              "attendees": [{"name": "Lea", "email": "lea@example.org"}, {"name": "", "email": "tom@example.org"}]}
        ics, rcpts = M.invitation_ics(ev, "REQUEST")
        lines = ics.split("\r\n")
        self.assertIn("METHOD:REQUEST", lines)
        self.assertEqual(rcpts, ["lea@example.org", "tom@example.org"])
        self.assertEqual(sum(1 for ln in lines if ln.startswith("ATTENDEE")), 2)   # no injected one
        self.assertIn("SUMMARY:Evil\\nATTENDEE:mailto:x@evil.org\\; a\\, b", lines)
        self.assertIn('ORGANIZER;CN="Me the Boss":mailto:me@example.com', lines)
        self.assertIn("SEQUENCE:2", lines)
        self.assertTrue(all(len(ln.encode()) <= 75 for ln in lines))
        weekly, _ = M.invitation_ics(dict(ev, rrule="FREQ=WEEKLY;BYDAY=MO;COUNT=4"), "REQUEST")
        self.assertIn("RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=4\r\n", weekly)
        with self.assertRaises(M.MailError):
            M.invitation_ics(dict(ev, rrule="FREQ=DAILY\r\nATTENDEE:mailto:x@evil.org"), "REQUEST")
        cancel, _ = M.invitation_ics(ev, "CANCEL")
        self.assertIn("STATUS:CANCELLED", cancel)
        with self.assertRaises(M.MailError):
            M.invitation_ics(dict(ev, attendees=[]), "REQUEST")
        with self.assertRaises(M.MailError):
            M.invitation_ics(dict(ev, attendees=[{"email": "x@y.org>\r\nBcc: z@q.org"}]), "REQUEST")

    def test_all_day_and_folding(self):
        ev = {"uid": "u1", "title": "Ä" * 60, "start": 1793397600000, "end": 1793484000000, "allDay": True,
              "organizer": {"email": "me@example.com"}, "attendees": [{"email": "a@b.org"}]}
        ics, _ = M.invitation_ics(ev, "REQUEST")
        self.assertRegex(ics, r"DTSTART;VALUE=DATE:\d{8}\r\n")
        for ln in ics.split("\r\n"):
            self.assertLessEqual(len(ln.encode()), 75)
        unfolded = ics.replace("\r\n ", "")
        self.assertIn("SUMMARY:" + "Ä" * 60, unfolded)


class Part2EndToEnd(EndToEnd):
    """export / import, viewer, invitations — reuses the fake server of EndToEnd"""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.gnupg = tempfile.mkdtemp()
        os.chmod(cls.gnupg, 0o700)
        os.environ["GNUPGHOME"] = cls.gnupg

    @classmethod
    def tearDownClass(cls):
        subprocess.run(["gpgconf", "--homedir", cls.gnupg, "--kill", "all"], capture_output=True)
        super().tearDownClass()

    def test_p2_export_import_encrypted(self):
        d = tempfile.mkdtemp()
        path = os.path.join(d, "accounts.qsmail")
        accs = [dict(self.acc, signature="Grüsse", color="#7aa2f7"),
                dict(self.acc, id="acc-2", email="two@example.com", username="two@example.com")]
        r = self.ok("export", {"accounts": accs, "withPasswords": True, "passphrase": "correct horse", "path": path},
                    secrets={"acc-test": "pw-123", "acc-2": "pw-two"})
        self.assertTrue(r["encrypted"])
        self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
        raw = open(path, "rb").read()
        self.assertTrue(raw.startswith(b"-----BEGIN PGP MESSAGE-----"))
        self.assertNotIn(b"pw-123", raw)
        self.assertNotIn(b"example.com", raw)               # the whole file is encrypted
        # passphrase needed / wrong
        r = self.ok("import-read", {"path": path})
        self.assertTrue(r["needPassphrase"])
        bad = self.run_cmd("import-read", {"path": path, "passphrase": "wrong one!"})
        self.assertIn("Wrong passphrase", bad["error"])
        r = self.ok("import-read", {"path": path, "passphrase": "correct horse"})
        self.assertEqual([a["email"] for a in r["accounts"]], [ME, "two@example.com"])
        self.assertTrue(all(a["hasPassword"] for a in r["accounts"]))
        self.assertNotIn("password", json.dumps(r).replace("hasPassword", "").replace("passwordStored", ""))
        self.assertEqual(r["accounts"][0]["signature"], "Grüsse")
        r = self.ok("import", {"path": path, "passphrase": "correct horse", "pick": {"two@example.com": "mail-new1"}})
        self.assertEqual([(a["id"], a["passwordStored"]) for a in r["accounts"]], [("mail-new1", True)])
        bad = self.run_cmd("import", {"path": path, "passphrase": "correct horse", "pick": {ME: "../../etc"}})
        self.assertIn("bad account id", bad["error"])
        # a changed file
        lines = raw.decode().splitlines()
        mid = len(lines) // 2
        lines[mid] = ("A" if lines[mid][0] != "A" else "B") + lines[mid][1:]
        tampered = os.path.join(d, "tampered.qsmail")
        open(tampered, "w").write("\n".join(lines) + "\n")
        bad = self.run_cmd("import-read", {"path": tampered, "passphrase": "correct horse"})
        self.assertFalse(bad["ok"])
        short = self.run_cmd("export", {"accounts": accs, "withPasswords": True, "passphrase": "short", "path": path})
        self.assertIn("at least 8", short["error"])

    def test_p2_export_plain_and_bad_files(self):
        d = tempfile.mkdtemp()
        path = os.path.join(d, "plain.json")
        self.ok("export", {"accounts": [self.acc], "withPasswords": False, "path": path})
        v = json.load(open(path))
        self.assertNotIn("password", v["accounts"][0])
        r = self.ok("import-read", {"path": path})
        self.assertFalse(r["encrypted"])
        self.assertFalse(r["accounts"][0]["hasPassword"])
        # 127.0.0.1 without TLS is allowed (local), a remote one isn't
        v["accounts"][0]["imap"] = {"host": "mail.evil.org", "port": 143, "security": "none"}
        json.dump(v, open(path, "w"))
        r = self.ok("import-read", {"path": path})
        self.assertTrue(r["accounts"][0]["errors"])
        r = self.ok("import", {"path": path, "pick": {ME: "mail-x"}})
        self.assertEqual(r["accounts"], [])                    # never imported with errors
        open(path, "w").write('{"hello": 1}')
        self.assertIn("isn't a mail accounts export", self.run_cmd("import-read", {"path": path})["error"])

    def test_p2_viewer(self):
        uid = self.srv.add("INBOX", message("Dokumente", "X", "x@example.org", "anbei",
                                            attach=[("brief.pdf", tiny_pdf(), "application/pdf"),
                                                    ("notiz.txt", "Grüsse\nZeile 2".encode(), "text/plain"),
                                                    ("bild.png", b"\x89PNG\r\n\x1a\n", "image/png"),
                                                    ("../../evil name.bin", b"x", "application/octet-stream")]))
        req = {"account": self.acc, "folder": "INBOX", "uid": uid, "cache": self.cache}
        pdf = self.ok("view", dict(req, index=0))
        self.assertEqual(pdf["kind"], "pdf")
        self.assertEqual(pdf["pageCount"], 1)
        self.assertEqual(len(pdf["pages"]), 1)
        self.assertTrue(open(pdf["pages"][0], "rb").read(8).startswith(b"\x89PNG"))
        self.assertEqual(os.stat(os.path.dirname(pdf["path"])).st_mode & 0o777, 0o700)
        txt = self.ok("view", dict(req, index=1))
        self.assertEqual((txt["kind"], txt["text"]), ("text", "Grüsse\nZeile 2"))
        self.assertEqual(self.ok("view", dict(req, index=2))["kind"], "image")
        other = self.ok("view", dict(req, index=3))
        self.assertEqual(other["kind"], "other")
        self.assertNotIn("..", os.path.basename(other["path"]))
        self.assertTrue(other["path"].startswith(self.cache))
        broken = self.srv.add("INBOX", message("Kaputt", "X", "x@example.org", "x",
                                               attach=[("kaputt.pdf", b"%PDF-1.4 nothing here", "application/pdf")]))
        r = self.run_cmd("view", {"account": self.acc, "folder": "INBOX", "uid": broken, "cache": self.cache, "index": 0})
        self.assertFalse(r["ok"])
        self.assertIn("PDF", r["error"])

    def test_p2_invite(self):
        ev = {"uid": "inv-1@quickshell", "title": "Projekt; Start", "start": 1793430000000, "end": 1793433600000,
              "location": "Zürich", "sequence": 0,
              "attendees": [{"name": "Lea", "email": "lea@example.org"}, {"name": "Tom", "email": "tom@example.org"}]}
        n = len(self.srv.boxes["Sent"].msgs)
        r = self.ok("invite", {"account": self.acc, "event": ev, "method": "REQUEST", "sentFolder": "Sent"})
        self.assertEqual(r["recipients"], ["lea@example.org", "tom@example.org"])
        sent = self.srv.sent[-1]
        msg = email.message_from_bytes(sent["raw"], policy=email.policy.default)
        self.assertTrue(msg["Subject"].startswith("Invitation: Projekt; Start @ "))
        cal = next(p for p in msg.walk() if p.get_content_type() == "text/calendar")
        self.assertEqual(cal.get_param("method"), "REQUEST")
        body = cal.get_content()
        self.assertIn("ORGANIZER;CN=\"Me\":mailto:me@example.com", body)
        self.assertIn("SUMMARY:Projekt\\; Start", body)
        self.assertIn("invite.ics", [p.get_filename() for p in msg.iter_attachments()])
        self.assertEqual(len(self.srv.boxes["Sent"].msgs), n + 1)
        r = self.ok("invite", {"account": self.acc, "event": dict(ev, sequence=1), "method": "CANCEL"})
        msg = email.message_from_bytes(self.srv.sent[-1]["raw"], policy=email.policy.default)
        self.assertTrue(msg["Subject"].startswith("Cancelled: "))
        self.assertIn("METHOD:CANCEL", next(p for p in msg.walk() if p.get_content_type() == "text/calendar").get_content())


# the inherited end-to-end tests don't need to run twice (unittest skips names that aren't callable)
for _name in [n for n in dir(EndToEnd) if n.startswith("test_")]:
    setattr(Part2EndToEnd, _name, None)


class CalendarAttendees(unittest.TestCase):
    """calsync.py writes guests into the event and reads them back"""

    def test_round_trip(self):
        sys.path.insert(0, os.path.join(HERE, "..", "..", "scripts", "calendar"))
        import calsync as C
        from datetime import datetime, timezone
        now = datetime.now(timezone.utc)
        span = (datetime.fromtimestamp(1793000000, timezone.utc), datetime.fromtimestamp(1794000000, timezone.utc))
        ev = {"title": "Treffen", "start": 1793430000000, "end": 1793433600000, "allDay": False,
              "organizer": {"name": "Me", "email": "me@example.com"},
              "attendees": [{"name": "Lea \"L\"", "email": "lea@example.org"}, {"name": "", "email": "bad address"}]}
        text, uid = C.apply_event(C.new_calendar_text(), ev, now)
        self.assertTrue(uid)
        self.assertIn('ATTENDEE;CN="Lea L";ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE;SCHEDULE-AGENT=CLIENT:mailto:lea@example.org',
                      text.replace("\r\n ", ""))
        self.assertNotIn("bad address", text)
        evs = C.expand_calendar(text, *span)
        self.assertEqual(evs[0]["attendees"][0]["email"], "lea@example.org")
        self.assertEqual(evs[0]["organizer"]["email"], "me@example.com")
        # editing: guests replaced, sequence goes up, removing all removes the organizer too
        text2, _ = C.apply_event(text, dict(evs[0], attendees=[{"name": "Tom", "email": "tom@example.org"}],
                                            organizer=ev["organizer"]), now)
        evs2 = C.expand_calendar(text2, *span)
        self.assertEqual([a["email"] for a in evs2[0]["attendees"]], ["tom@example.org"])
        self.assertEqual(evs2[0]["sequence"], 1)
        text3, _ = C.apply_event(text2, dict(evs2[0], attendees=[]), now)
        self.assertNotIn("ATTENDEE", text3)
        self.assertNotIn("ORGANIZER", text3)


if __name__ == "__main__":
    unittest.main(verbosity=1)
