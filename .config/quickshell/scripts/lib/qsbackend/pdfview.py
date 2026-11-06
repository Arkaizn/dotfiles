"""PDF pages as pictures, for the built-in viewers (Mail's attachments, the
file manager's quick preview): poppler's pdftoppm in a subprocess (no
scripting, a time limit), the pages cached in a private folder.

    render(pdf_path, cache_dir, max_pages=30) -> {"pages": [png paths], "pageCount": n}
    raises ViewError with a one-line message for the UI
"""
import os
import re
import subprocess

MAX_PAGES = 30


class ViewError(Exception):
    pass


def page_count(pdf):
    try:
        info = subprocess.run(["pdfinfo", "--", pdf], capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return 0
    m = re.search(r"^Pages:\s+(\d+)", info.stdout, re.M)
    return int(m.group(1)) if m else 0


def render(pdf, cache_dir, max_pages=MAX_PAGES):
    """the first max_pages pages; rendered once, then read from cache_dir/pages"""
    pdir = os.path.join(cache_dir, "pages")
    pages = sorted(os.listdir(pdir)) if os.path.isdir(pdir) else []
    count = page_count(pdf)
    if not pages:
        os.makedirs(pdir, mode=0o700, exist_ok=True)
        last = min(count or max_pages, max_pages)
        try:
            r = subprocess.run(["pdftoppm", "-png", "-r", "110", "-f", "1", "-l", str(last), "--", pdf, os.path.join(pdir, "p")],
                               capture_output=True, text=True, timeout=90)
        except FileNotFoundError:
            raise ViewError("pdftoppm isn't installed (sudo pacman -S poppler)")
        except subprocess.TimeoutExpired:
            raise ViewError("The PDF took too long to render")
        pages = sorted(os.listdir(pdir))
        if r.returncode != 0 and not pages:
            raise ViewError("The PDF couldn't be shown: " + (r.stderr.strip().splitlines() or ["damaged file"])[-1])
    return {"pages": [os.path.join(pdir, p) for p in pages], "pageCount": count or len(pages)}
