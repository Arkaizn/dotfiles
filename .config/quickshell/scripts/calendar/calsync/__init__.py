"""The calendar backend as a package (the shell runs ../calsync.py).

  common    errors, constants, keyring
  files     atomic writes, the lock for local calendars, GnuPG
  net       HTTP with safe redirects and a size cap, CalDAV XML
  ical      iCalendar: parse, expand repeating events, write, edit
  graph     Microsoft 365 (Graph API, device-code sign-in)
  caldav    discover, sync, save, delete, colours (CalDAV, .ics, local, Graph)
  importer  importing .ics / .zip files into a calendar
  accounts  account export / import
  cli       the command table and main()

Names are looked up in the modules on first use (PEP 562), so `import calsync`
sees everything without the command line loading it all.
"""
import importlib
import os
import sys

# the shared backend library (scripts/lib/qsbackend), also when imported
# without the launcher (tests)
_lib = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "lib")
if _lib not in sys.path:
    sys.path.insert(0, _lib)
# compiled modules into the cache, never the config folder (dotfiles repo)
if not sys.pycache_prefix:
    sys.pycache_prefix = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "quickshell", "pycache")

_MODULES = ("common", "files", "net", "ical", "graph", "caldav", "importer", "accounts", "cli")


def __getattr__(name):
    for m in _MODULES:
        mod = importlib.import_module("." + m, __name__)
        if name in vars(mod):
            return vars(mod)[name]
    raise AttributeError(name)
