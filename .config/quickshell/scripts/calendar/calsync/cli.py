import importlib
import sys

from qsbackend import request, respond
from .common import CalError, secret_clear, secret_store


def discover_any(req):
    kind = req.get("type")
    caldav = importlib.import_module(".caldav", __package__)
    return caldav.discover_ics(req) if kind == "ics" else caldav.discover_local(req) if kind == "local" else caldav.discover(req)


def store_secret(req):
    secret_store(req["id"], req.get("label") or "Quickshell calendar", req.get("password") or "")
    return {}


def forget_secret(req):
    secret_clear(req["id"])
    return {}


def rediscover(req):
    return importlib.import_module(".caldav", __package__).rediscover(req["account"])


# command → (module, function). A command imports only its own module (python3
# startup and imports are most of a request's time; see REFACTOR_PLAN.md).
COMMANDS = {
    "discover": ("cli", "discover_any"), "sync": ("caldav", "sync"), "save": ("caldav", "save"),
    "delete": ("caldav", "delete"), "set-color": ("caldav", "set_color"),
    "store-secret": ("cli", "store_secret"), "forget-secret": ("cli", "forget_secret"),
    "graph-login": ("graph", "graph_login"), "rediscover": ("cli", "rediscover"),
    "import-read": ("importer", "import_read"), "import": ("importer", "import_events"),
    "import-undo": ("importer", "import_undo"), "export-accounts": ("accounts", "export_accounts"),
    "import-accounts-read": ("accounts", "import_accounts_read"), "import-accounts": ("accounts", "import_accounts"),
}


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        req = request("CAL_REQUEST")
        if cmd not in COMMANDS:
            raise CalError(f"unknown command {cmd!r}")
        mod, fn = COMMANDS[cmd]
        res = getattr(importlib.import_module("." + mod, __package__), fn)(req)
        respond(dict(res, ok=True))
    except CalError as e:
        respond({"ok": False, "error": str(e)})
    except Exception as e:
        respond({"ok": False, "error": f"{type(e).__name__}: {e}"})
