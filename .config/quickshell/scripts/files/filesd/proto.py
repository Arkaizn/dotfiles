"""Writing replies and events, error codes, checking arguments."""
import errno
import json
import os
import sys
import threading

VERSION = 1
_lock = threading.Lock()
_out = sys.stdout.buffer


def send(obj):
    """one JSON line; any thread (workers answer straight from the pool)"""
    # ensure_ascii: a name that isn't UTF-8 (surrogateescape) still goes out as \udcXX
    line = json.dumps(obj, ensure_ascii=True, separators=(",", ":")).encode() + b"\n"
    with _lock:
        try:
            _out.write(line)
            _out.flush()
        except BrokenPipeError:
            os._exit(0)          # the file manager went away


class Fail(Exception):
    """a request that can't be done: the message is shown in the UI"""
    def __init__(self, message, code="io"):
        super().__init__(message)
        self.code = code


_CODES = {
    errno.EACCES: "denied", errno.EPERM: "denied", errno.ENOENT: "missing",
    errno.ENOTDIR: "notdir", errno.EEXIST: "exists", errno.ENOSPC: "nospace",
    errno.EDQUOT: "nospace", errno.EROFS: "readonly", errno.ECANCELED: "cancelled",
}
_TEXT = {
    "denied": "You don't have permission to open this",
    "missing": "This doesn't exist (any more)",
    "notdir": "This isn't a folder",
    "nospace": "There's no space left on this drive",
    "readonly": "This drive is read-only",
}


def from_os(e):
    """an OSError as a Fail with a short message (no paths: the UI knows where)"""
    code = _CODES.get(e.errno, "io")
    return Fail(_TEXT.get(code) or (e.strerror or "Input / output error"), code)


def error_reply(rid, e):
    if isinstance(e, OSError):
        e = from_os(e)
    if isinstance(e, Fail):
        return {"id": rid, "type": "error", "error": str(e), "code": e.code}
    return {"id": rid, "type": "error", "error": "Internal error: " + type(e).__name__, "code": "io"}


def path_arg(args, key="path"):
    """an absolute local path from a request"""
    p = args.get(key)
    if not isinstance(p, str) or not p.startswith("/") or "\0" in p or len(p) > 4096:
        raise Fail("not an absolute path", "invalid")
    # lexical, like the path bar: "a/b/.." is "a"; a leading "//" is just "/"
    return os.path.normpath("/" + p.lstrip("/"))


def choice_arg(args, key, options, default):
    v = args.get(key, default)
    if v not in options:
        raise Fail(key + " must be one of " + ", ".join(options), "invalid")
    return v
