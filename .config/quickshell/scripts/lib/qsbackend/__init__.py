"""Shared parts of the Python backends (mail, calendar): lazy imports, the
JSON protocol, the keyring, GnuPG and private / atomic file writes.

Standard library only. Each backend is a small launcher script (the path the
shell runs) plus a package of modules next to it; the launcher puts
scripts/lib and its own folder on sys.path (python3 -I leaves them off) and
keeps the compiled .pyc files in ~/.cache/quickshell/pycache, not in the
config folder (which is synced to the dotfiles repo).
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile


def setup(script_dir):
    """call first in a launcher: import paths + .pyc location"""
    lib = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    for p in (script_dir, lib):
        if p not in sys.path:
            sys.path.insert(0, p)


def lazy(name):
    """a module that is only imported when first used (imaplib, smtplib, … cost
    tens of milliseconds each, and most commands need none of them)"""
    if name in sys.modules:
        return sys.modules[name]
    spec = importlib.util.find_spec(name)
    loader = importlib.util.LazyLoader(spec.loader)
    spec.loader = loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    loader.exec_module(module)
    return module


# ── Protocol: request JSON in an environment variable, one JSON object out ───

def request(env_var):
    return json.loads(os.environ.get(env_var) or "{}")


def respond(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


# ── Keyring (secret-tool; secrets only on stdin) ─────────────────────────────

class Keyring:
    """secret-tool entries under `service` with one attribute (`attr` = key).
    The attribute names are what existing entries were stored with — the mail
    app uses "id", the calendar "account": don't change them."""

    def __init__(self, service, attr, error, fake_env=None):
        self.service, self.attr, self.error, self.fake_env = service, attr, error, fake_env

    def _fake(self):
        return os.environ.get(self.fake_env) if self.fake_env else None

    def lookup(self, key):
        fake = self._fake()                       # tests only
        if fake:
            return json.loads(fake).get(key, "")
        try:
            r = subprocess.run(["secret-tool", "lookup", "service", self.service, self.attr, key],
                               capture_output=True, text=True, timeout=25)
        except subprocess.TimeoutExpired:
            raise self.error("The keyring didn't answer — is it locked? Unlock it and try again")
        except OSError:
            return ""
        return r.stdout.rstrip("\n") if r.returncode == 0 else ""

    def store(self, key, label, secret):
        if self._fake():
            return
        try:
            r = subprocess.run(["secret-tool", "store", "--label=" + label, "service", self.service, self.attr, key],
                               input=secret, capture_output=True, text=True, timeout=30)
        except subprocess.TimeoutExpired:
            raise self.error("The keyring didn't answer — is it locked? Unlock it and try again")
        if r.returncode != 0:
            raise self.error("The keyring didn't take the password: " + (r.stderr.strip() or "secret-tool failed"))

    def clear(self, key):
        if self._fake():
            return
        try:
            subprocess.run(["secret-tool", "clear", "service", self.service, self.attr, key], capture_output=True, timeout=25)
        except (OSError, subprocess.TimeoutExpired):
            pass


# ── GnuPG (passphrase through a pipe fd, never argv) ─────────────────────────

def gpg_run(args, data, passphrase, error):
    r, w = os.pipe()
    try:
        p = subprocess.Popen(["gpg", "--batch", "--quiet", "--no-tty", "--yes", "--no-symkey-cache",
                              "--pinentry-mode", "loopback", "--passphrase-fd", str(r)] + args,
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, pass_fds=(r,))
    except FileNotFoundError:
        os.close(r)
        os.close(w)
        raise error("GnuPG (gpg) isn't installed")
    os.close(r)
    with os.fdopen(w, "w") as f:
        f.write(passphrase + "\n")
    try:
        out, err = p.communicate(data, timeout=60)
    except subprocess.TimeoutExpired:
        p.kill()            # communicate() doesn't: it would keep running
        p.wait()
        raise error("GnuPG took too long")
    return p.returncode, out, err.decode("utf-8", "replace")


# ── Files ────────────────────────────────────────────────────────────────────

def atomic_write(path, data):
    """write path (0600) through a unique temp file next to it + rename: two
    writers at once (sync and read lane, two saves) can't mix their files.
    data: bytes or str (UTF-8)"""
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", prefix=".", suffix=".tmp")
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb") as f:
            f.write(data.encode("utf-8") if isinstance(data, str) else data)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def write_private(path, data, error):
    """an export file the user chose (0600; the folder must exist)"""
    path = os.path.expanduser(path)
    d = os.path.dirname(path) or "."
    if not os.path.isdir(d):
        raise error("The folder doesn't exist: " + d)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(data.encode("utf-8") if isinstance(data, str) else data)
    os.chmod(path, 0o600)
    return path
