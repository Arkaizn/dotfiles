"""The mail backend as a package (the shell runs ../mailsync.py).

  common     errors, keyring, server / TLS checks, friendly error text
  imapproto  IMAP wire format: modified UTF-7, tokens, FETCH / LIST parsing
  mime       headers, MIME structure, text previews
  files      the message cache, atomic writes, GnuPG
  htmlclean  the HTML sanitizer, dark mode colours, remote images
  accounts   autoconfig, account export / import
  imap       the IMAP connection, sync, flags, move, delete, search
  read       message bodies, attachments, the viewer
  compose    SMTP, building and sending messages, invitations
  cli        the command table and main()

Names are looked up in the modules on first use (PEP 562), so `import mailsync`
(the tests) sees everything without the command line loading it all.
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

_MODULES = ("common", "imapproto", "mime", "files", "htmlclean", "accounts", "imap", "read", "compose", "cli")


def __getattr__(name):
    for m in _MODULES:
        mod = importlib.import_module("." + m, __name__)
        if name in vars(mod):
            return vars(mod)[name]
    raise AttributeError(name)
