"""Thumbnails in the shared cache (~/.cache/thumbnails, the freedesktop spec:
other file managers and file dialogs see the same ones). GNOME's thumbnail
factory finds an existing one or makes it with the system's thumbnailers
(sandboxed by them: glycin for images, ffmpegthumbnailer for videos, gsf for
office files). PDFs have no thumbnailer here: pdftoppm renders the first page
and it's saved the way the factory would (Thumb::URI / Thumb::MTime).
A file that failed once isn't tried again until it changes.

    thumbnail(path, mime, mtime, large) -> png path | None
"""
import os
import subprocess
import tempfile
import threading

import gi
gi.require_version("GnomeDesktop", "4.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf, Gio, GnomeDesktop  # noqa: E402

_local = threading.local()


def _factory(large):
    """one factory per thread and size (it isn't shared between threads)"""
    key = "large" if large else "normal"
    f = getattr(_local, key, None)
    if f is None:
        f = GnomeDesktop.DesktopThumbnailFactory.new(
            GnomeDesktop.DesktopThumbnailSize.LARGE if large else GnomeDesktop.DesktopThumbnailSize.NORMAL)
        setattr(_local, key, f)
    return f


def _pdf(path, size):
    """the first page, at most size px, as a pixbuf"""
    rt = os.environ.get("XDG_RUNTIME_DIR")
    if not rt:
        return None
    with tempfile.TemporaryDirectory(dir=rt) as tmp:
        try:
            r = subprocess.run(["pdftoppm", "-png", "-singlefile", "-f", "1", "-l", "1", "-scale-to", str(size),
                                "--", path, os.path.join(tmp, "t")], capture_output=True, timeout=30)
        except (OSError, subprocess.TimeoutExpired):
            return None
        out = os.path.join(tmp, "t.png")
        if r.returncode != 0 or not os.path.exists(out):
            return None
        return GdkPixbuf.Pixbuf.new_from_file(out)


def thumbnail(path, mime, mtime, large=False):
    f = _factory(large)
    uri = Gio.File.new_for_path(path).get_uri()
    have = f.lookup(uri, mtime)
    if have:
        return have
    if f.has_valid_failed_thumbnail(uri, mtime):
        return None
    pix = None
    try:
        if mime == "application/pdf":
            pix = _pdf(path, 256 if large else 128)
        elif f.can_thumbnail(uri, mime, mtime):
            pix = f.generate_thumbnail(uri, mime, None)
    except Exception:  # noqa: BLE001  (GLib.Error, a thumbnailer that crashed)
        pix = None
    if pix is None:
        try:
            f.create_failed_thumbnail(uri, mtime, None)
        except Exception:  # noqa: BLE001
            pass
        return None
    try:
        f.save_thumbnail(pix, uri, mtime, None)
    except Exception:  # noqa: BLE001
        return None
    return f.lookup(uri, mtime)
