import importlib
import sys

from qsbackend import request, respond
from .common import MailError, friendly, secret_clear, secret_store


def test_login(req):
    from .compose import smtp_connect
    from .imap import Imap
    account = req["account"]
    try:
        with Imap(account, req) as im:
            fl = im.folders()
    except Exception as e:
        raise MailError(friendly(e))
    try:
        s = smtp_connect(account, req)
        s.quit()
    except Exception as e:
        raise MailError("Receiving works, sending doesn't: " + friendly(e))
    return {"folders": fl}


# command → (module, function). A command imports only its own module: opening
# a cached message must not load imaplib, smtplib, ssl … (python3 startup is most
# of a request's time, measured in REFACTOR_PLAN.md → Rust assessment).
COMMANDS = {
    "autoconfig": ("accounts", "autoconfig"), "test": ("cli", "test_login"), "folders": ("imap", "folders"),
    "sync": ("imap", "sync"), "body": ("read", "body"), "attachment": ("read", "attachment"),
    "save-eml": ("read", "save_eml"), "view": ("read", "view"), "export": ("accounts", "export_accounts"),
    "import-read": ("accounts", "import_read"), "import": ("accounts", "import_accounts"), "invite": ("compose", "invite"),
    "flags": ("imap", "flags"), "move": ("imap", "move"), "create-folder": ("imap", "create_folder"),
    "delete": ("imap", "delete"), "search": ("imap", "search"), "send": ("compose", "send"),
    "store-secret": ("cli", "store_secret"), "forget-secret": ("cli", "forget_secret"),
}


def store_secret(r):
    secret_store(r["id"], r.get("label") or "Quickshell mail", r["password"])
    return {}


def forget_secret(r):
    secret_clear(r["id"])
    return {}


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd not in COMMANDS:
        respond({"ok": False, "error": f"unknown command {cmd!r}"})
        return 2
    try:
        req = request("MAIL_REQUEST")
        mod, fn = COMMANDS[cmd]
        res = getattr(importlib.import_module("." + mod, __package__), fn)(req)
        respond(dict(res, ok=True))
    except Exception as e:
        respond({"ok": False, "error": friendly(e)})
    return 0
