from html.parser import HTMLParser
import colorsys
import hashlib
import html
import ipaddress
import os
import re
import socket
import time
import urllib.parse
import urllib.request

from qsbackend import lazy
_futures = lazy('concurrent.futures')   # (not "futures": functions use that name)
ssl = lazy('ssl')
from .mime import html_to_text
from .files import store_raw


COLOR_NAMES = {
    "white": (255, 255, 255), "black": (0, 0, 0), "red": (255, 0, 0), "green": (0, 128, 0), "blue": (0, 0, 255),
    "yellow": (255, 255, 0), "orange": (255, 165, 0), "purple": (128, 0, 128), "gray": (128, 128, 128),
    "grey": (128, 128, 128), "silver": (192, 192, 192), "maroon": (128, 0, 0), "navy": (0, 0, 128),
    "teal": (0, 128, 128), "olive": (128, 128, 0), "lime": (0, 255, 0), "aqua": (0, 255, 255),
    "fuchsia": (255, 0, 255), "lightgray": (211, 211, 211), "lightgrey": (211, 211, 211),
    "darkgray": (169, 169, 169), "darkgrey": (169, 169, 169), "dimgray": (105, 105, 105), "dimgrey": (105, 105, 105),
    "whitesmoke": (245, 245, 245), "gainsboro": (220, 220, 220), "ghostwhite": (248, 248, 255),
    "snow": (255, 250, 250), "ivory": (255, 255, 240), "beige": (245, 245, 220), "linen": (250, 240, 230),
    "aliceblue": (240, 248, 255), "lightblue": (173, 216, 230), "lightyellow": (255, 255, 224),
    "darkblue": (0, 0, 139), "darkred": (139, 0, 0), "darkgreen": (0, 100, 0),
}


COLOR_TOKEN = re.compile(r"#[0-9a-fA-F]{3,8}\b|\b(?:rgba?|hsla?)\([^)]*\)|\b(?:" + "|".join(COLOR_NAMES) + r")\b", re.I)


def parse_color(t):
    """-> (r, g, b, a) with r, g, b 0..1, or None"""
    t = t.strip().lower()
    if t in COLOR_NAMES:
        return tuple(x / 255 for x in COLOR_NAMES[t]) + (1.0,)
    if t.startswith("#"):
        h = t[1:]
        if len(h) in (3, 4):
            h = "".join(ch * 2 for ch in h)
        if len(h) not in (6, 8):
            return None
        try:
            v = [int(h[i:i + 2], 16) / 255 for i in range(0, len(h), 2)]
        except ValueError:
            return None
        return tuple(v[:3]) + ((v[3],) if len(v) == 4 else (1.0,))
    m = re.fullmatch(r"(rgba?|hsla?)\((.*)\)", t)
    if not m:
        return None
    parts = [x for x in re.split(r"[\s,/]+", m.group(2).strip()) if x]
    if len(parts) < 3:
        return None
    try:
        def num(x, scale):
            return float(x[:-1]) / 100 if x.endswith("%") else float(x) / scale
        a = num(parts[3], 1) if len(parts) > 3 else 1.0
        if m.group(1).startswith("rgb"):
            r, g, b = (num(x, 255) for x in parts[:3])
        else:
            hue = float(re.sub(r"deg$", "", parts[0])) / 360 % 1
            r, g, b = colorsys.hls_to_rgb(hue, num(parts[2], 100), num(parts[1], 100))
    except ValueError:
        return None
    return tuple(min(1.0, max(0.0, x)) for x in (r, g, b, a))


def dark_color(t, kind):
    """kind: "text" | "bg" | "border" -> the color for a dark page; "" = drop it (a white
    page background), None = leave it as it is (not a color: transparent, inherit …)"""
    c = parse_color(t)
    if c is None:
        return None
    h, l, s = colorsys.rgb_to_hls(*c[:3])
    if kind == "text":
        # dark → light (black ends at 0.9), light text stays
        l = l if l >= 0.7 else 0.9 - l * (0.2 / 0.7)
    else:
        if kind == "bg" and l >= 0.92 and (s < 0.3 or l >= 0.97):
            return ""
        # light → dark (white ends at 0.08), dark stays; borders a bit lighter
        l = l if l <= 0.25 else 0.25 - (l - 0.25) * (0.17 / 0.75)
        if kind == "border":
            l += 0.1
        s = min(s, 0.75)
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    if c[3] < 1:
        return "rgba(%d,%d,%d,%.2f)" % (round(r * 255), round(g * 255), round(b * 255), c[3])
    return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


def dark_style(style):
    """the color declarations of a style attribute turned dark"""
    def decl(d):
        if ":" not in d:
            return d
        prop, val = d.split(":", 1)
        p = prop.strip().lower()
        kind = ("text" if p in ("color", "text-decoration-color") else
                "bg" if p.startswith("background") else
                "border" if p.startswith(("border", "outline")) else None)
        if kind is None:
            return d
        dropped = []

        def swap(m):
            v = dark_color(m.group(0), kind)
            if v == "":
                dropped.append(1)
                return "transparent"
            return m.group(0) if v is None else v
        val = COLOR_TOKEN.sub(swap, val)
        # a plain white background (just the color): gone
        if dropped and p in ("background", "background-color") and re.fullmatch(r"\s*transparent\s*(!important)?\s*", val, re.I):
            return ""
        return prop + ":" + val
    return ";".join(x for x in (decl(d) for d in style.split(";")) if x.strip())


REMOTE = re.compile(r"^\s*(https?:)?//", re.I)


class _Sanitizer(HTMLParser):
    DROP = {"script", "style", "head", "title", "iframe", "object", "embed", "applet", "form",
            "noscript", "svg", "math", "template", "video", "audio", "canvas"}
    VOID = {"br", "hr", "img", "meta", "link", "input", "col", "area", "base", "wbr", "source"}
    KEEP_ATTRS = {"href", "src", "alt", "title", "width", "height", "align", "valign", "colspan", "rowspan",
                  "border", "cellpadding", "cellspacing", "color", "bgcolor", "face", "size", "style", "dir"}

    HIDDEN = re.compile(r"display\s*:\s*none|mso-hide\s*:\s*all|visibility\s*:\s*hidden", re.I)

    def __init__(self, allow_remote, cids, adapt=False):
        super().__init__(convert_charrefs=False)
        self.allow_remote, self.cids, self.adapt = allow_remote, cids, adapt
        self.out, self.skip, self.blocked = [], 0, 0
        self.hide = None          # [tag, depth]: inside an element hidden by its style (preheaders …)
        self.bg = []              # [tag, color or None] of the open table / tr / td / th
        self.width = 0            # the widest fixed width (px) of the layout (tables, cells, blocks):
                                  # what it was made for. Pictures don't count: a wide one in a
                                  # flowing message is shrunk by the app, it isn't a layout

    def note_width(self, v):
        m = re.fullmatch(r"\s*(\d{2,4})(\.\d+)?\s*(px)?\s*", v or "")
        if m:
            self.width = max(self.width, min(1200, int(m.group(1))))

    def inherit_bg(self, tag, kept):
        """Qt paints a cell's background only behind its first lines when tables are
        nested in it (newsletters: a dark card with light text → light on white). The
        cells inside get the color themselves."""
        own = None
        for a in kept:
            m = re.match(r'bgcolor="([^"]*)"', a) or re.match(r'style="[^"]*background(?:-color)?\s*:\s*(#[0-9a-fA-F]{3,8}|rgb[^;"]*)', a)
            if m:
                own = m.group(1)
        inherited = next((c for _, c in reversed(self.bg) if c), None)
        if own is None and inherited and tag in ("table", "td", "th"):
            kept = kept + [f'bgcolor="{inherited}"']
        self.bg.append([tag, own])
        return kept

    def hidden(self, style):
        st = style or ""
        if self.HIDDEN.search(st):
            return True
        return bool(re.search(r"max-height\s*:\s*0", st, re.I) and re.search(r"overflow\s*:\s*hidden", st, re.I))

    def clean_style(self, style, tag=""):
        if re.search(r"url\s*\(", style, re.I):
            if not self.allow_remote and re.search(r"url\s*\(\s*['\"]?\s*(https?:)?//", style, re.I):
                self.blocked += 1
            style = re.sub(r"url\s*\([^)]*\)", "none", style, flags=re.I)
        style = re.sub(r"expression\s*\(|javascript:|position\s*:\s*(fixed|absolute)", "", style, flags=re.I)
        if tag != "img":
            for m in re.finditer(r"(?:^|;)\s*(?:max-|min-)?width\s*:\s*([\d.]+)px", style, re.I):
                self.note_width(m.group(1))
        # Qt's rich text draws these literally, newsletters use them as tricks: lines on top of
        # each other (line-height below the font size), squeezed text, overlapping blocks
        style = re.sub(r"(^|;)\s*(letter-spacing|margin(-\w+)?)\s*:\s*-[^;]*", r"\1", style, flags=re.I)
        # "margin: 0 auto" (centering): Qt can't center with it, it widens the layout instead
        style = re.sub(r"(^|;)\s*margin(-left|-right)?\s*:[^;]*\bauto\b[^;]*", r"\1", style, flags=re.I)
        fs = re.search(r"font-size\s*:\s*([\d.]+)px", style, re.I)
        lh = re.search(r"line-height\s*:\s*([\d.]+)px", style, re.I)
        if lh and float(lh.group(1)) < max(12.0, float(fs.group(1)) if fs else 0):
            style = re.sub(r"(^|;)\s*line-height\s*:[^;]*", r"\1", style, flags=re.I)
        if self.adapt:      # dark mode: the sender's colors turned dark
            style = dark_style(style)
        return style

    def handle_starttag(self, tag, attrs, closed=False):
        tag = tag.lower()
        if self.hide is not None:
            if tag == self.hide[0] and tag not in self.VOID and not closed:
                self.hide[1] += 1
            return
        if tag not in self.VOID and not closed and not self.skip and self.hidden(dict((k.lower(), v) for k, v in attrs if k).get("style")):
            self.hide = [tag, 1]
            return
        if tag in self.DROP:
            if tag not in self.VOID and not closed:
                self.skip += 1
            return
        if self.skip or tag in ("meta", "link", "base", "html", "body"):
            return
        kept = []
        for k, v in attrs:
            k = (k or "").lower()
            v = v or ""
            if self.adapt and k in ("color", "bgcolor"):
                v = dark_color(v, "text" if k == "color" else "bg")
                if not v:           # a white page background, or not a color
                    continue
            if k.startswith("on") or k not in self.KEEP_ATTRS:
                if k == "background" and REMOTE.match(v) and not self.allow_remote:
                    self.blocked += 1
                continue
            if k == "href" and not re.match(r"^\s*(https?:|mailto:|#)", v, re.I):
                continue
            if k == "src":
                if v.lower().startswith("cid:"):
                    path = self.cids.get(v[4:].strip("<>"))
                    if not path:
                        continue
                    v = "file://" + path
                elif REMOTE.match(v):
                    if not self.allow_remote:
                        self.blocked += 1
                        continue
                    if v.startswith("//"):
                        v = "https:" + v
                # embedded images: only plain bitmap types (no SVG), at most 2 MB
                # of base64 (a mail can't hang the reader with one huge attribute)
                elif not re.match(r"^\s*data:image/(png|jpe?g|gif|webp|bmp)[;,]", v, re.I) or len(v) > 2 * 1024 * 1024:
                    continue
            if k == "style":
                v = self.clean_style(v, tag)
            if k == "width" and tag in ("table", "td", "th", "div"):
                self.note_width(v)
            kept.append(f'{k}="{html.escape(v, quote=True)}"')
        if tag == "img" and not any(a.startswith("src=") for a in kept):
            return
        if tag in ("table", "tr", "td", "th") and not closed:
            kept = self.inherit_bg(tag, kept)
        self.out.append(f"<{tag}{' ' if kept else ''}{' '.join(kept)}{' /' if closed else ''}>")

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs, closed=True)

    def handle_endtag(self, tag):
        tag = tag.lower()
        if self.hide is not None:
            if tag == self.hide[0]:
                self.hide[1] -= 1
                if self.hide[1] == 0:
                    self.hide = None
            return
        if tag in self.DROP:
            self.skip = max(0, self.skip - 1)
            return
        if self.skip or tag in self.VOID or tag in ("html", "body"):
            return
        if tag in ("table", "tr", "td", "th"):
            while self.bg:
                if self.bg.pop()[0] == tag:
                    break
        self.out.append(f"</{tag}>")

    def handle_data(self, data):
        if not self.skip and self.hide is None:
            self.out.append(html.escape(data, quote=False))

    def handle_entityref(self, name):
        if not self.skip and self.hide is None:
            self.out.append(f"&{name};")

    def handle_charref(self, name):
        if not self.skip and self.hide is None:
            self.out.append(f"&#{name};")


IMG_MAX = 5 * 1024 * 1024


IMG_COUNT = 60


IMG_SECONDS = 15


IMG_MAGIC = ((b"\x89PNG\r\n\x1a\n", ".png"), (b"\xff\xd8\xff", ".jpg"), (b"GIF87a", ".gif"), (b"GIF89a", ".gif"), (b"BM", ".bmp"))


def image_kind(head):
    for magic, ext in IMG_MAGIC:
        if head.startswith(magic):
            return ext
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return ".webp"
    return ""


def public_host(host):
    """the name only resolves to addresses on the internet (not this computer / the LAN)"""
    if os.environ.get("MAIL_TEST_LOCAL_IMAGES"):         # tests only: their server is on 127.0.0.1
        return bool(host)
    try:
        infos = socket.getaddrinfo(host, None)
    except OSError:
        return False
    for info in infos:
        ip = ipaddress.ip_address(info[4][0].split("%")[0])
        if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_multicast or ip.is_reserved or ip.is_unspecified:
            return False
    return bool(infos)


class _PublicOnly(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        u = urllib.parse.urlsplit(newurl)
        if u.scheme not in ("http", "https") or not public_host(u.hostname or ""):
            return None
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch_image(url, cache):
    """-> local path or "" (cached by URL; only http(s), public hosts, real bitmaps, ≤ IMG_MAX)"""
    key = hashlib.sha1(url.encode("utf-8", "replace")).hexdigest()
    for ext in (".png", ".jpg", ".gif", ".bmp", ".webp"):
        p = os.path.join(cache, "r-" + key + ext)
        if os.path.exists(p):
            os.utime(p)            # recently used: pruned last
            return p
    if os.path.exists(os.path.join(cache, "r-" + key + ".bad")):
        return ""
    u = urllib.parse.urlsplit(url)
    if u.scheme not in ("http", "https") or not public_host(u.hostname or ""):
        return ""
    opener = urllib.request.OpenerDirector()
    for h in (urllib.request.HTTPHandler(), urllib.request.HTTPSHandler(context=ssl.create_default_context()),
              _PublicOnly(), urllib.request.HTTPErrorProcessor()):
        opener.add_handler(h)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0", "Accept": "image/*"})
        with opener.open(req, timeout=8) as r:
            data = r.read(IMG_MAX + 1)
    except Exception:
        return ""
    ext = image_kind(data[:16])
    if len(data) > IMG_MAX or not ext:
        # remembered: not tried again for every message that has it
        os.close(os.open(os.path.join(cache, "r-" + key + ".bad"), os.O_WRONLY | os.O_CREAT, 0o600))
        return ""
    p = os.path.join(cache, "r-" + key + ext)
    store_raw(p, data)
    return p


IMG_TAG = re.compile(r"<img\b[^>]*>", re.I)


def localize_images(out_html, cache):
    """remote <img> → the local copies; tracking pixels and failed ones go"""
    tags = IMG_TAG.findall(out_html)
    def attr(tag, name):
        m = re.search(r'\b' + name + r'="([^"]*)"', tag)
        return html.unescape(m.group(1)) if m else ""
    def tiny(tag):
        # a tracking pixel: up to 3 px wide or high, as an attribute or in the style
        style = attr(tag, "style")
        dims = [attr(tag, "width"), attr(tag, "height")]
        dims += re.findall(r"(?:^|;)\s*(?:max-)?(?:width|height)\s*:\s*([^;]+)", style, re.I)
        if re.search(r"display\s*:\s*none|visibility\s*:\s*hidden", style, re.I):
            return True
        return any(re.fullmatch(r"\s*[0-3](\.\d+)?(px)?\s*", d) for d in dims if d)
    urls = []
    for t in tags:
        src = attr(t, "src")
        if REMOTE.match(src) and not tiny(t) and src not in urls:
            urls.append(src)
    urls = urls[:IMG_COUNT]
    got = {}
    if urls and cache:
        os.makedirs(cache, mode=0o700, exist_ok=True)
        deadline = time.monotonic() + IMG_SECONDS
        ex = _futures.ThreadPoolExecutor(max_workers=6)
        futures = {u: ex.submit(fetch_image, u, cache) for u in urls}
        for u, f in futures.items():
            try:
                got[u] = f.result(timeout=max(0.1, deadline - time.monotonic()))
            except Exception:
                got[u] = ""
        ex.shutdown(wait=False, cancel_futures=True)       # the slow ones: shown next time (cached by then)
    def swap(m):
        t = m.group(0)
        src = attr(t, "src")
        if not REMOTE.match(src):
            return t
        p = got.get(src, "")
        return t.replace('src="' + html.escape(src, quote=True) + '"', 'src="' + html.escape("file://" + p, quote=True) + '"') if p else ""
    return IMG_TAG.sub(swap, out_html)


def sanitize_html(s, allow_remote=False, cids=None, adapt=False):
    """-> (html, number of remote things blocked). adapt: the sender's colors turned dark (dark mode)"""
    out = sanitize(s, allow_remote, cids, adapt)
    return out["html"], out["blocked"]


def sanitize(s, allow_remote=False, cids=None, adapt=False):
    """-> {html, blocked, width}; width: the layout's fixed width in px (0 = flows), the
    app scales such a message down to fit instead of cutting it off"""
    p = _Sanitizer(allow_remote, cids or {}, adapt)
    try:
        p.feed(s)
        p.close()
    except Exception:
        return {"html": html.escape(html_to_text(s)).replace("\n", "<br>"), "blocked": 0, "width": 0}
    return {"html": "".join(p.out), "blocked": p.blocked, "width": p.width}
