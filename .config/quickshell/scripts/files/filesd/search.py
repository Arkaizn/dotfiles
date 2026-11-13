"""Search by name, like Nautilus' search bar: the open folder and the folders
below it (breadth first, so near results come first), every word of the query
must match the name — whole, at its start, at a word's start, inside, or
loosely (its letters in order, for typos like "dcmnt") — and the better the
match and the shallower, the higher it ranks. Never follows links to folders,
never leaves for hidden folders unless hidden items are wanted.

    run(base, query, opts, cancelled, emit)   emit(items) gets batches; returns {count, more, scanned}
    score(name, words)                        0 = no match (tested on its own)
    kind_of(item)                             the filter kind of an item: folder, document, image, …
"""
import collections
import os
import re
import stat
import time

from . import listing

MAX_RESULTS = 2000
# "everywhere" (a search from /): never into these, nor into network / pseudo file systems
SKIP_ROOTS = frozenset(("/proc", "/sys", "/dev", "/run", "/tmp", "/var/tmp", "/lost+found"))
PSEUDO_FS = frozenset(("proc", "sysfs", "devtmpfs", "devpts", "tmpfs", "cgroup", "cgroup2", "securityfs", "debugfs",
                       "tracefs", "pstore", "bpf", "configfs", "fusectl", "mqueue", "hugetlbfs", "autofs", "efivarfs",
                       "binfmt_misc", "overlay", "squashfs", "nsfs"))
BATCH_EVERY = 0.15            # seconds between batches while results come in
_bound = re.compile(r"[\s._\-()\[\]]")

KINDS = ("folder", "document", "image", "audio", "video", "archive", "text", "other")
_DOC = ("application/pdf", "application/vnd.oasis.opendocument", "application/vnd.openxmlformats",
        "application/msword", "application/vnd.ms-", "application/rtf", "application/epub", "text/markdown")
_ARCHIVE = ("zip", "x-7z", "x-rar", "vnd.rar", "x-tar", "compressed-tar", "gzip", "x-xz", "x-bzip", "zstd", "x-iso9660")


def kind_of(item):
    if item["dir"]:
        return "folder"
    t = item.get("type", "")
    if t.startswith("image/"):
        return "image"
    if t.startswith("audio/"):
        return "audio"
    if t.startswith("video/"):
        return "video"
    if t.startswith(_DOC):
        return "document"
    if t.startswith("application/") and any(a in t for a in _ARCHIVE):
        return "archive"
    if t.startswith("text/") or t in ("application/json", "application/xml", "application/x-shellscript"):
        return "text"
    return "other"


def words_of(query):
    return [w for w in query.lower().split() if w]


def _loose(word, name):
    """the word's letters in order in name: a small score, more when they bunch up"""
    i, gaps, last = 0, 0, -1
    for ch in word:
        j = name.find(ch, i)
        if j < 0:
            return 0
        if last >= 0:
            gaps += j - last - 1
        last, i = j, j + 1
    return max(1, 10 - gaps // 2)


def score(name, words):
    if not words:
        return 0
    low = name.lower()
    stem = low.rsplit(".", 1)[0] if "." in low[1:] else low
    total = 0
    for w in words:
        if low == w or stem == w:
            s = 100
        elif low.startswith(w):
            s = 80
        else:
            at = low.find(w)
            if at > 0 and _bound.match(low[at - 1]):
                s = 60
            elif at >= 0:
                s = 40
            elif len(w) >= 3:
                s = _loose(w, low)
            else:
                s = 0
        if s == 0:
            return 0
        total += s
    return total


def run(base, query, opts, cancelled, emit):
    words = words_of(query)
    if not words:
        return {"count": 0, "more": False, "scanned": 0}
    depth_max = opts.get("depth", 64)
    hidden = opts.get("hidden", False)
    kinds = set(opts.get("kinds") or ())
    since = opts.get("since") or 0
    skip = opts.get("skip") or frozenset()
    found, batch, scanned = 0, [], 0
    last = time.monotonic()

    def flush(force=False):
        # what's found goes out on the clock, not only when the next match turns up: the
        # first match at once, then every BATCH_EVERY (a match found early used to wait for
        # the end of the whole search when nothing else matched)
        nonlocal batch, last
        now = time.monotonic()
        if batch and (force or now - last >= BATCH_EVERY):
            emit(batch)
            batch, last = [], now
    queue = collections.deque([(base, 0)])
    while queue:
        folder, depth = queue.popleft()
        if cancelled():
            return None
        flush()
        try:
            entries = list(os.scandir(folder))
        except OSError:
            continue
        hidden_names = listing.read_hidden(folder)
        budget = [listing.SNIFF_MAX]
        for e in entries:
            scanned += 1
            if scanned % 500 == 0:
                if cancelled():
                    return None
                flush()
            name = e.name
            is_hidden = listing.is_hidden(name, hidden_names)
            if is_hidden and not hidden:
                continue
            try:
                lst = e.stat(follow_symlinks=False)
            except OSError:
                continue
            if stat.S_ISDIR(lst.st_mode) and depth < depth_max and e.path not in skip:
                queue.append((e.path, depth + 1))
            sc = score(name, words)
            if sc == 0:
                continue
            item = listing.make_item(folder, name, lst, hidden_names, budget)
            if kinds and kind_of(item) not in kinds:
                continue
            if since and item["mtime"] < since:
                continue
            rel = os.path.relpath(folder, base)
            item["loc"] = "" if rel == "." else rel
            item["path"] = e.path
            item["score"] = sc - depth * 3
            batch.append(item)
            found += 1
            if found >= MAX_RESULTS:
                emit(batch)
                return {"count": found, "more": True, "scanned": scanned}
            flush(found == 1)
    flush(True)
    return {"count": found, "more": False, "scanned": scanned}
