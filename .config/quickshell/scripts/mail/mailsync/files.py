import hashlib
import os
import shutil
import subprocess
import tempfile
import qsbackend
from .common import MailError


def cache_file(cache, acc_id, folder, uidvalidity, uid):
    d = os.path.expanduser(cache or "")
    if not d:
        return ""
    os.makedirs(d, mode=0o700, exist_ok=True)
    # UIDVALIDITY in the key: after a folder reset the same UID is another message
    key = hashlib.sha1(f"{acc_id}|{folder}|{int(uidvalidity or 0)}|{int(uid)}".encode()).hexdigest()
    return os.path.join(d, key + ".eml")


def cache_path(req):
    return cache_file(req.get("cache"), req["account"]["id"], req["folder"], req.get("uidvalidity"), req["uid"])




def atomic_write(path, data):
    qsbackend.atomic_write(path, data)


def gpg_run(args, data, passphrase):
    return qsbackend.gpg_run(args, data, passphrase, MailError)


def write_private(path, data):
    return qsbackend.write_private(path, data, MailError)


def store_raw(path, raw):
    atomic_write(path, raw)


def cache_dir(req):
    """the app's private cache folder (never a shared one like /tmp)"""
    c = req.get("cache")
    if not c:
        raise MailError("No cache folder")
    return os.path.expanduser(c)


CACHE_MAX = 400 * 1024 * 1024    # bodies/ (messages, their inline images, viewed pages) at most this big


def prune_cache(cache):
    """oldest first until the cache is under CACHE_MAX"""
    d = os.path.expanduser(cache or "")
    if not d or not os.path.isdir(d):
        return
    entries = []
    for name in os.listdir(d):
        p = os.path.join(d, name)
        try:
            if os.path.isdir(p):
                size = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(p) for f in fs)
            else:
                size = os.path.getsize(p)
            entries.append((os.path.getmtime(p), size, p))
        except OSError:
            continue
    total = sum(e[1] for e in entries)
    for _, size, p in sorted(entries):
        if total <= CACHE_MAX:
            break
        try:
            shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)
            total -= size
        except OSError:
            pass



