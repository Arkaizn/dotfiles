"""Sample messages for the mail tests and the fake server."""

import time
from datetime import datetime
from email.message import EmailMessage
from email.utils import format_datetime, localtime, make_msgid

ME = "me@example.com"


def message(subject, name, addr, text, html=None, attach=None, msgid=None, reply_to=None, refs=None,
            to=ME, when=None, inline_image=False):
    m = EmailMessage()
    m["From"] = f"{name} <{addr}>"
    m["To"] = to
    m["Subject"] = subject
    m["Date"] = format_datetime(datetime.fromtimestamp(when).astimezone() if when else localtime())
    m["Message-ID"] = msgid or make_msgid(domain="example.org")
    if reply_to:
        m["In-Reply-To"] = reply_to
        m["References"] = " ".join((refs or []) + [reply_to])
    m.set_content(text)
    if html:
        m.add_alternative(html, subtype="html")
        if inline_image:
            m.get_payload()[1].add_related(b"\x89PNG\r\n\x1a\n" + b"\x00" * 16, "image", "png", cid="<logo@example.org>")
    for fname, data, ctype in attach or []:
        main, sub = ctype.split("/")
        m.add_attachment(data, maintype=main, subtype=sub, filename=fname)
    return m.as_bytes(policy=m.policy.clone(linesep="\r\n"))


NEWSLETTER_HTML = """<html><head><style>body{color:red}</style><script>alert(1)</script></head>
<body onload="evil()"><h1>Herbst-Angebote</h1>
<p>Hallo! Unsere <b>neuen</b> Produkte sind da.</p>
<img src="https://tracker.example.net/open.gif?u=1" width="1" height="1">
<img src="cid:logo@example.org" alt="Logo">
<p style="background:url(https://tracker.example.net/bg.png)">Mehr <a href="https://shop.example.net/sale" onclick="x()">im Shop</a>
or <a href="javascript:alert(2)">nope</a></p></body></html>"""


def tiny_pdf(text="Hallo PDF"):
    """a valid one-page PDF (xref offsets computed)"""
    objs = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
            None, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
    stream = f"BT /F1 24 Tf 40 100 Td ({text}) Tj ET".encode()
    objs[3] = "<< /Length %d >>\nstream\n%s\nendstream" % (len(stream), stream.decode())
    out = b"%PDF-1.4\n"
    offs = []
    for i, o in enumerate(objs, 1):
        offs.append(len(out))
        out += f"{i} 0 obj\n{o}\nendobj\n".encode()
    x = len(out)
    out += f"xref\n0 {len(objs) + 1}\n0000000000 65535 f \n".encode()
    out += b"".join(f"{o:010d} 00000 n \n".encode() for o in offs)
    out += f"trailer\n<< /Size {len(objs) + 1} /Root 1 0 R >>\nstartxref\n{x}\n%%EOF\n".encode()
    return out


INVITE = """BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//EN\r\nMETHOD:REQUEST\r\nBEGIN:VEVENT\r\nUID:team-1@example.org\r\nDTSTAMP:20261028T100000Z\r\nDTSTART:20261104T090000Z\r\nDTEND:20261104T100000Z\r\nSUMMARY:Team-Meeting\r\nORGANIZER;CN=Lea:mailto:lea@example.org\r\nATTENDEE;CN=Me;RSVP=TRUE:mailto:me@example.com\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"""


def fill(srv):
    now = time.time()
    day = 86400
    t1 = "<plan-1@example.org>"
    srv.add("INBOX", message("Wochenende planen", "Lea Fischer", "lea@example.org",
                             "Hi! Hast du am Samstag Zeit? Wir könnten wandern gehen.", msgid=t1, when=now - 3 * day),
            flags={"\\Seen"}, date=now - 3 * day)
    srv.add("INBOX", message("Re: Wochenende planen", "Tom Keller", "tom@example.org",
                             "Ich bin dabei!\n\n> Hi! Hast du am Samstag Zeit?", reply_to=t1, when=now - 2 * day,
                             msgid="<plan-2@example.org>"), flags={"\\Seen"}, date=now - 2 * day)
    srv.add("INBOX", message("Re: Wochenende planen", "Lea Fischer", "lea@example.org",
                             "Super, dann 9 Uhr am Bahnhof.", reply_to="<plan-2@example.org>", refs=[t1],
                             when=now - 3600), date=now - 3600)
    srv.add("INBOX", message("=?utf-8?q?Rechnung_Oktober_=E2=80=93_Nr=2E_4711?=", "Stadtwerke", "rechnung@stadtwerke.example",
                             "Guten Tag,\nanbei Ihre Rechnung für Oktober.\nFreundliche Grüsse",
                             attach=[("Rechnung-4711.pdf", b"%PDF-1.4 fake pdf", "application/pdf")], when=now - 5 * 3600),
            flags={"\\Flagged"}, date=now - 5 * 3600)
    srv.add("INBOX", message("Herbst-Angebote 🍂", "Shop Newsletter", "news@shop.example.net",
                             "Unsere neuen Produkte sind da.", html=NEWSLETTER_HTML, inline_image=True, when=now - 1800),
            date=now - 1800)
    srv.add("INBOX", message("Fotos vom Ausflug", "Mia Graf", "mia@example.org", "Hier die Fotos!",
                             attach=[("berg.jpg", b"\xff\xd8\xff fake jpeg", "image/jpeg"),
                                     ("see.jpg", b"\xff\xd8\xff fake jpeg 2", "image/jpeg")], when=now - 8 * day),
            flags={"\\Seen"}, date=now - 8 * day)
    srv.add("INBOX", message("Einladung: Team-Meeting", "Lea Fischer", "lea@example.org",
                             "Hallo, anbei die Einladung und das Protokoll.",
                             attach=[("invite.ics", INVITE.encode(), "text/calendar"),
                                     ("Protokoll.pdf", tiny_pdf("Protokoll Oktober"), "application/pdf"),
                                     ("notiz.txt", "Punkte:\n1. Budget\n2. Termine".encode(), "text/plain")],
                             when=now - 600), date=now - 600)
    srv.add("Sent", message("Bewerbung", "Me", ME, "Sehr geehrte Damen und Herren …", to="jobs@firma.example",
                            when=now - 10 * day), flags={"\\Seen"}, date=now - 10 * day)
    srv.add("Archive", message("Alte Notiz", "Me", ME, "Archiviert.", when=now - 40 * day),
            flags={"\\Seen"}, date=now - 40 * day)
