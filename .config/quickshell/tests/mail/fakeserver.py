"""A small IMAP4rev1 + SMTP server for the mail tests (plain text, this computer only).

Enough of both protocols for scripts/mail/mailsync.py: LOGIN, LIST (special-use
flags), SELECT / EXAMINE, STATUS, FETCH / UID FETCH (FLAGS, INTERNALDATE,
RFC822.SIZE, BODYSTRUCTURE, BODY[HEADER.FIELDS (…)], BODY[section]<0.n>, BODY[]),
UID STORE, UID COPY / MOVE, EXPUNGE / UID EXPUNGE, APPEND, UID SEARCH (ALL, TEXT,
CHARSET), LOGOUT. SMTP: EHLO, AUTH PLAIN / LOGIN, MAIL, RCPT, DATA, QUIT.

    srv = FakeMail(user="me@example.com", password="secret")
    srv.add("INBOX", raw_bytes, flags={"\\Seen"})
    srv.start()  …  srv.imap_port, srv.smtp_port, srv.sent  …  srv.stop()
"""

import base64
import email
import email.policy
import re
import socketserver
import threading
import time


class Box:
    def __init__(self, path, flags=(), uidvalidity=1):
        self.path, self.flags, self.uidvalidity = path, list(flags), uidvalidity
        self.uidnext, self.msgs = 1, []

    def add(self, raw, flags=(), date=None):
        self.msgs.append({"uid": self.uidnext, "flags": set(flags), "raw": raw, "date": date or time.time()})
        self.uidnext += 1
        return self.uidnext - 1


def q(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def nstr(s):
    return "NIL" if s is None else q(s)


def params_of(part, extra=()):
    ps = [(k, v) for k, v in part.get_params(header="content-type")[1:] or []] if part.get("Content-Type") else []
    items = [f"{q(k.upper())} {q(v)}" for k, v in list(ps) + list(extra)]
    return "(" + " ".join(items) + ")" if items else "NIL"


def bodystructure(part):
    if part.is_multipart():
        kids = "".join(bodystructure(p) for p in part.get_payload())
        return f"({kids} {q(part.get_content_subtype().upper())} {params_of(part)} NIL NIL)"
    main, sub = part.get_content_maintype().upper(), part.get_content_subtype().upper()
    payload = part.get_payload(decode=False)
    payload = payload.encode() if isinstance(payload, str) else (payload or b"")
    enc = (part.get("Content-Transfer-Encoding") or "7bit").upper()
    cid = part.get("Content-ID")
    disp = part.get_content_disposition()
    fname = part.get_filename()
    dsp = f"({q(disp.upper())} {('(' + q('FILENAME') + ' ' + q(fname) + ')') if fname else 'NIL'})" if disp else "NIL"
    base = f"{q(main)} {q(sub)} {params_of(part)} {nstr(cid)} NIL {q(enc)} {len(payload)}"
    if main == "TEXT":
        return f"({base} {payload.count(b'\n')} NIL {dsp} NIL)"
    return f"({base} NIL {dsp} NIL)"


def section_of(msg, section):
    part = msg
    for n in section.split("."):
        n = int(n)
        if part.is_multipart():
            part = part.get_payload()[n - 1]
        elif n != 1:
            return b""
    payload = part.get_payload(decode=False)
    return payload.encode() if isinstance(payload, str) else (payload or b"")


def tokens(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == " ":
            i += 1
        elif c == '"':
            j, buf = i + 1, []
            while s[j] != '"':
                if s[j] == "\\":
                    j += 1
                buf.append(s[j])
                j += 1
            out.append(("str", "".join(buf)))
            i = j + 1
        elif c == "(":
            depth, j = 0, i
            while True:
                if s[j] == "(":
                    depth += 1
                elif s[j] == ")":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            out.append(("list", s[i + 1:j]))
            i = j + 1
        else:
            j, depth = i, 0
            while j < len(s) and (depth or s[j] != " "):
                depth += s[j] == "["
                depth -= s[j] == "]"
                j += 1
            out.append(("atom", s[i:j]))
            i = j
    return out


def seqset(spec, values):
    """'3:5,9' / '4:*' over a sorted list of numbers -> the ones in it"""
    top = max(values) if values else 0
    keep = set()
    for piece in spec.split(","):
        a, _, b = piece.partition(":")
        a = top if a == "*" else int(a)
        b = a if not _ else (top if b == "*" else int(b))
        lo, hi = min(a, b), max(a, b)
        keep |= {v for v in values if lo <= v <= hi}
    return sorted(keep)


def mutf7(s):
    out, buf = [], []

    def flush():
        if buf:
            out.append("&" + base64.b64encode("".join(buf).encode("utf-16-be")).decode().rstrip("=").replace("/", ",") + "-")
            buf.clear()
    for ch in s:
        if 0x20 <= ord(ch) <= 0x7e:
            flush()
            out.append("&-" if ch == "&" else ch)
        else:
            buf.append(ch)
    flush()
    return "".join(out)


def unmutf7(s):
    out, i = [], 0
    while i < len(s):
        if s[i] == "&":
            j = s.index("-", i)
            if j == i + 1:
                out.append("&")
            else:
                b = s[i + 1:j].replace(",", "/")
                out.append(base64.b64decode(b + "=" * (-len(b) % 4)).decode("utf-16-be"))
            i = j + 1
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


class ImapHandler(socketserver.StreamRequestHandler):
    def send(self, line):
        self.wfile.write((line + "\r\n").encode() if isinstance(line, str) else line)

    def readline(self):
        line = self.rfile.readline()
        if not line:
            return None
        line = line.rstrip(b"\r\n")
        lits = []
        while True:       # literals: {n} at the end -> continuation, read n bytes, then the rest of the line
            m = re.search(rb"\{(\d+)\+?\}$", line)
            if not m:
                break
            n = int(m.group(1))
            if not line.endswith(b"+}"):
                self.send("+ go ahead")
            data = self.rfile.read(n)
            lits.append(data)
            rest = self.rfile.readline().rstrip(b"\r\n")
            line = line[:m.start()] + b"\x00LIT%d\x00" % (len(lits) - 1) + rest
        return line.decode("utf-8", "replace"), lits

    def handle(self):
        srv = self.server.mail
        self.send("* OK [CAPABILITY IMAP4rev1 MOVE UIDPLUS SPECIAL-USE] fake ready")
        self.box, self.ro, self.authed = None, False, False
        while True:
            got = self.readline()
            if got is None:
                return
            line, lits = got
            parts = line.split(" ", 2)
            if len(parts) < 2:
                continue
            tag, cmd = parts[0], parts[1].upper()
            args = parts[2] if len(parts) > 2 else ""
            try:
                with srv.lock:
                    done = self.command(srv, tag, cmd, args, lits)
            except Exception as e:      # a bug here shows up as a BAD in the test
                self.send(f"{tag} BAD {e!r}")
                continue
            if done:
                return

    def arg(self, t, lits):
        kind, v = t
        m = re.fullmatch(r"\x00LIT(\d+)\x00", v)
        if m:
            return lits[int(m.group(1))].decode("utf-8", "replace")
        return v

    def command(self, srv, tag, cmd, args, lits):
        toks = tokens(args)
        uid = False
        if cmd == "UID":
            uid, cmd = True, toks[0][1].upper()
            toks = toks[1:]
        if cmd == "CAPABILITY":
            self.send("* CAPABILITY IMAP4rev1 MOVE UIDPLUS SPECIAL-USE")
        elif cmd == "NOOP":
            pass
        elif cmd == "LOGOUT":
            self.send("* BYE")
            self.send(f"{tag} OK bye")
            return True
        elif cmd == "LOGIN":
            user, pw = self.arg(toks[0], lits), self.arg(toks[1], lits)
            if user != srv.user or pw != srv.password:
                self.send(f"{tag} NO [AUTHENTICATIONFAILED] Invalid credentials")
                return
            self.authed = True
        elif not self.authed:
            self.send(f"{tag} NO login first")
            return
        elif cmd == "LIST":
            for b in srv.boxes.values():
                fl = " ".join(["\\HasNoChildren"] + b.flags)
                self.send(f'* LIST ({fl}) "/" {q(mutf7(b.path))}')
        elif cmd == "CREATE":
            path = unmutf7(self.arg(toks[0], lits))
            if path in srv.boxes:
                self.send(f"{tag} NO [ALREADYEXISTS] mailbox exists")
                return
            srv.boxes[path] = Box(path)
        elif cmd == "SUBSCRIBE":
            pass
        elif cmd in ("SELECT", "EXAMINE"):
            b = srv.boxes.get(unmutf7(self.arg(toks[0], lits)))
            if not b:
                self.send(f"{tag} NO no such mailbox")
                return
            self.box, self.ro = b, cmd == "EXAMINE"
            self.send(f"* {len(b.msgs)} EXISTS")
            self.send("* 0 RECENT")
            self.send(f"* OK [UIDVALIDITY {b.uidvalidity}] ok")
            self.send(f"* OK [UIDNEXT {b.uidnext}] ok")
            self.send("* FLAGS (\\Seen \\Flagged \\Answered \\Deleted \\Draft)")
            self.send(f"{tag} OK [{'READ-ONLY' if self.ro else 'READ-WRITE'}] {cmd} done")
            return
        elif cmd == "STATUS":
            b = srv.boxes.get(unmutf7(self.arg(toks[0], lits)))
            if not b:
                self.send(f"{tag} NO no such mailbox")
                return
            unseen = sum(1 for m in b.msgs if "\\Seen" not in m["flags"])
            self.send(f"* STATUS {q(mutf7(b.path))} (MESSAGES {len(b.msgs)} UNSEEN {unseen})")
        elif cmd == "APPEND":
            b = srv.boxes.get(unmutf7(self.arg(toks[0], lits)))
            if not b:
                self.send(f"{tag} NO [TRYCREATE] no such mailbox")
                return
            flags = set(toks[1][1].split()) if len(toks) > 2 and toks[1][0] == "list" else set()
            raw = lits[-1]
            u = b.add(raw, flags)
            self.send(f"{tag} OK [APPENDUID {b.uidvalidity} {u}] APPEND done")
            return
        elif cmd in ("FETCH", "STORE", "SEARCH", "COPY", "MOVE", "EXPUNGE", "CLOSE"):
            if not self.box:
                self.send(f"{tag} NO select first")
                return
            getattr(self, "c_" + cmd.lower())(srv, tag, uid, toks, lits)
        else:
            self.send(f"{tag} BAD unknown command {cmd}")
            return
        self.send(f"{tag} OK {cmd} done")

    def pick(self, uid, spec):
        msgs = self.box.msgs
        if uid:
            keep = set(seqset(spec, [m["uid"] for m in msgs]))
            return [(i + 1, m) for i, m in enumerate(msgs) if m["uid"] in keep]
        keep = set(seqset(spec, list(range(1, len(msgs) + 1))))
        return [(i + 1, m) for i, m in enumerate(msgs) if i + 1 in keep]

    def c_fetch(self, srv, tag, uid, toks, lits):
        spec = toks[0][1]
        items_s = toks[1][1] if toks[1][0] == "list" else toks[1][1]
        items = [t[1] for t in tokens(items_s)]
        if uid and "UID" not in [i.upper() for i in items]:
            items = ["UID"] + items
        for seq, m in self.pick(uid, spec):
            msg = email.message_from_bytes(m["raw"], policy=email.policy.compat32)
            out = []
            for it in items:
                u = it.upper()
                if u == "UID":
                    out.append(f"UID {m['uid']}".encode())
                elif u == "FLAGS":
                    out.append(f"FLAGS ({' '.join(sorted(m['flags']))})".encode())
                elif u == "INTERNALDATE":
                    out.append(("INTERNALDATE " + time.strftime('"%d-%b-%Y %H:%M:%S +0000"', time.gmtime(m["date"]))).encode())
                elif u == "RFC822.SIZE":
                    out.append(f"RFC822.SIZE {len(m['raw'])}".encode())
                elif u == "BODYSTRUCTURE":
                    out.append(("BODYSTRUCTURE " + bodystructure(msg)).encode())
                elif u.startswith("BODY"):
                    sm = re.match(r"BODY(?:\.PEEK)?\[([^\]]*)\](?:<(\d+)\.(\d+)>)?", it, re.I)
                    sec, start, count = sm.group(1), sm.group(2), sm.group(3)
                    if sec == "":
                        data = m["raw"]
                    elif sec.upper().startswith("HEADER.FIELDS"):
                        want = [w.lower() for w in re.search(r"\(([^)]*)\)", sec).group(1).split()]
                        lines = [f"{k}: {v}" for k, v in msg.items() if k.lower() in want]
                        data = ("\r\n".join(lines) + "\r\n\r\n").encode()
                    elif sec.upper() == "HEADER":
                        data = m["raw"].split(b"\r\n\r\n", 1)[0] + b"\r\n\r\n"
                    elif sec.upper() == "TEXT":
                        data = m["raw"].split(b"\r\n\r\n", 1)[-1]
                    else:
                        data = section_of(msg, sec)
                    name = f"BODY[{sec}]"
                    if start is not None:
                        data = data[int(start):int(start) + int(count)]
                        name += f"<{start}>"
                    if "PEEK" not in u and not self.ro:
                        m["flags"].add("\\Seen")
                    out.append(f"{name} {{{len(data)}}}\r\n".encode() + data)
            self.send(f"* {seq} FETCH (".encode() + b" ".join(out) + b")\r\n")

    def c_store(self, srv, tag, uid, toks, lits):
        spec, op = toks[0][1], toks[1][1].upper()
        flags = set(toks[2][1].split())
        for seq, m in self.pick(uid, spec):
            if op.startswith("+"):
                m["flags"] |= flags
            elif op.startswith("-"):
                m["flags"] -= flags
            else:
                m["flags"] = set(flags)
            if "SILENT" not in op:
                self.send(f"* {seq} FETCH (UID {m['uid']} FLAGS ({' '.join(sorted(m['flags']))}))")

    def c_search(self, srv, tag, uid, toks, lits):
        args = [self.arg(t, lits) for t in toks]
        if args and args[0].upper() == "CHARSET":
            args = args[2:]
        hits = []
        for seq, m in enumerate(self.box.msgs, 1):
            ok = True
            i = 0
            while i < len(args):
                a = args[i].upper()
                if a == "ALL":
                    i += 1
                elif a == "TEXT":
                    needle = args[i + 1].lower().encode()
                    ok = ok and needle in m["raw"].lower()
                    i += 2
                else:
                    i += 1
            if ok:
                hits.append(m["uid"] if uid else seq)
        self.send("* SEARCH " + " ".join(map(str, hits)))

    def copy_to(self, srv, uid, toks, lits):
        dest = srv.boxes.get(unmutf7(self.arg(toks[1], lits)))
        if dest is None:
            raise ValueError("no such mailbox")
        picked = self.pick(uid, toks[0][1])
        for _, m in picked:
            dest.add(m["raw"], set(m["flags"]) - {"\\Deleted"}, m["date"])
        return picked

    def c_copy(self, srv, tag, uid, toks, lits):
        self.copy_to(srv, uid, toks, lits)

    def c_move(self, srv, tag, uid, toks, lits):
        picked = self.copy_to(srv, uid, toks, lits)
        gone = {id(m) for _, m in picked}
        self.box.msgs = [m for m in self.box.msgs if id(m) not in gone]

    def c_expunge(self, srv, tag, uid, toks, lits):
        keep = set(seqset(toks[0][1], [m["uid"] for m in self.box.msgs])) if uid else None
        self.box.msgs = [m for m in self.box.msgs
                         if "\\Deleted" not in m["flags"] or (keep is not None and m["uid"] not in keep)]

    def c_close(self, srv, tag, uid, toks, lits):
        self.box = None


class SmtpHandler(socketserver.StreamRequestHandler):
    def send(self, line):
        self.wfile.write((line + "\r\n").encode())

    def handle(self):
        srv = self.server.mail
        self.send("220 fake ESMTP")
        mail_from, rcpts, authed = None, [], False
        while True:
            raw = self.rfile.readline()
            if not raw:
                return
            line = raw.decode("utf-8", "replace").rstrip("\r\n")
            cmd = line.split(" ", 1)[0].upper()
            arg = line[len(cmd):].strip()
            if cmd in ("EHLO", "HELO"):
                self.send("250-fake")
                self.send("250-AUTH PLAIN LOGIN")
                self.send("250 8BITMIME")
            elif cmd == "AUTH":
                mech, _, data = arg.partition(" ")
                if mech.upper() == "PLAIN":
                    if not data:
                        self.send("334 ")
                        data = self.rfile.readline().decode().strip()
                    _, user, pw = base64.b64decode(data).decode().split("\x00")
                else:
                    self.send("334 VXNlcm5hbWU6")
                    user = base64.b64decode(self.rfile.readline().strip()).decode()
                    self.send("334 UGFzc3dvcmQ6")
                    pw = base64.b64decode(self.rfile.readline().strip()).decode()
                if user == srv.user and pw == srv.password:
                    authed = True
                    self.send("235 ok")
                else:
                    self.send("535 5.7.8 bad credentials")
            elif cmd == "MAIL":
                if not authed:
                    self.send("530 auth first")
                    continue
                mail_from, rcpts = re.search(r"<([^>]*)>", arg).group(1), []
                self.send("250 ok")
            elif cmd == "RCPT":
                rcpts.append(re.search(r"<([^>]*)>", arg).group(1))
                self.send("250 ok")
            elif cmd == "DATA":
                self.send("354 go")
                lines = []
                while True:
                    ln = self.rfile.readline()
                    if ln in (b".\r\n", b".\n", b""):
                        break
                    lines.append(ln[1:] if ln.startswith(b"..") else ln)
                with srv.lock:
                    srv.sent.append({"from": mail_from, "to": rcpts, "raw": b"".join(lines)})
                self.send("250 queued")
            elif cmd == "RSET":
                mail_from, rcpts = None, []
                self.send("250 ok")
            elif cmd == "NOOP":
                self.send("250 ok")
            elif cmd == "QUIT":
                self.send("221 bye")
                return
            else:
                self.send("502 not implemented")


class _Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


class FakeMail:
    def __init__(self, user="me@example.com", password="secret", boxes=None):
        self.user, self.password = user, password
        self.lock = threading.RLock()
        self.sent = []
        self.boxes = {}
        for path, flags in boxes or [("INBOX", []), ("Sent", ["\\Sent"]), ("Drafts", ["\\Drafts"]),
                                     ("Archive", ["\\Archive"]), ("Junk", ["\\Junk"]), ("Trash", ["\\Trash"]),
                                     ("Projekte/Entwürfe & Ideen", [])]:
            self.boxes[path] = Box(path, flags)

    def add(self, box, raw, flags=(), date=None):
        with self.lock:
            return self.boxes[box].add(raw, flags, date)

    def start(self):
        self.imap = _Server(("127.0.0.1", 0), ImapHandler)
        self.smtp = _Server(("127.0.0.1", 0), SmtpHandler)
        self.imap.mail = self.smtp.mail = self
        self.imap_port, self.smtp_port = self.imap.server_address[1], self.smtp.server_address[1]
        for s in (self.imap, self.smtp):
            threading.Thread(target=s.serve_forever, daemon=True).start()
        return self

    def stop(self):
        for s in (self.imap, self.smtp):
            s.shutdown()
            s.server_close()


if __name__ == "__main__":
    # a fake server with some mail, for trying the UI:  python3 tests/mail/fakeserver.py 1143 1025
    import os
    import sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from sample import fill
    srv = FakeMail()
    fill(srv)
    srv.imap = _Server(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 1143), ImapHandler)
    srv.smtp = _Server(("127.0.0.1", int(sys.argv[2]) if len(sys.argv) > 2 else 1025), SmtpHandler)
    srv.imap.mail = srv.smtp.mail = srv
    print(f"fake mail: IMAP 127.0.0.1:{srv.imap.server_address[1]}  SMTP 127.0.0.1:{srv.smtp.server_address[1]}"
          f"  user {srv.user}  password {srv.password}", flush=True)
    threading.Thread(target=srv.smtp.serve_forever, daemon=True).start()

    def appender():      # a new message every 90 s, to see notifications
        n = 0
        while True:
            time.sleep(90)
            n += 1
            from sample import message
            srv.add("INBOX", message(f"New message {n}", "Lea Fischer", "lea@example.org", f"Hello again, this is number {n}."))
    threading.Thread(target=appender, daemon=True).start()
    srv.imap.serve_forever()
