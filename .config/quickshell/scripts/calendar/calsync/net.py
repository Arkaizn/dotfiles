from urllib.parse import urljoin
from urllib.parse import urlparse
import base64
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from .common import CalError, NS


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None  # handled by hand, so PROPFIND/REPORT keep their method + auth


_opener = urllib.request.build_opener(_NoRedirect)


# answers bigger than this aren't a calendar (a server could otherwise make
# the process eat memory until the outer timeout kills it)
MAX_RESPONSE = 50 * 1024 * 1024


def _origin(u):
    p = urlparse(u)
    return (p.scheme, (p.hostname or "").lower(), p.port or (443 if p.scheme == "https" else 80))


def _check_redirect(frm, to):
    if urlparse(frm).scheme == "https" and urlparse(to).scheme != "https":
        raise CalError(f"{urlparse(frm).netloc} redirected to an unencrypted address — refused")


def _read_capped(r):
    data = r.read(MAX_RESPONSE + 1)
    if len(data) > MAX_RESPONSE:
        raise CalError("The server's answer is bigger than 50 MB — not read")
    return data


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

    origin = _origin(url)
    for _ in range(8):
        req = urllib.request.Request(url, data=data, headers=h, method=method)
        try:
            with _opener.open(req, timeout=timeout) as r:
                return r.status, r.headers, _read_capped(r), url
        except urllib.error.HTTPError as e:
            loc = e.headers.get("Location") if e.headers else None
            if e.code in (301, 302, 303, 307, 308) and loc:
                e.close()                                   # its connection, before the next request
                nxt = urljoin(url, loc)
                # never from https down to http (the login would go in clear),
                # and the login only to the server it was meant for: a
                # redirect to another host gets the request without it
                _check_redirect(url, nxt)
                if _origin(nxt) != origin:
                    h.pop("Authorization", None)
                url = nxt
                if e.code == 303:
                    method, data = "GET", None
                continue
            return e.code, e.headers, _read_capped(e), url
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


PROPFIND_COLOR = """<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:" xmlns:a="http://apple.com/ns/ical/"><d:prop><a:calendar-color/></d:prop></d:propfind>"""
