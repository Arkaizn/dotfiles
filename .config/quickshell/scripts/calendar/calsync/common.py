from datetime import timezone
from dateutil import tz as dtz
import subprocess


LOCAL = dtz.tzlocal()


UTC = timezone.utc


SECRET_SERVICE = "quickshell-calendar"


NS = {
    "d": "DAV:",
    "c": "urn:ietf:params:xml:ns:caldav",
    "a": "http://apple.com/ns/ical/",
    "cs": "http://calendarserver.org/ns/",
}


from qsbackend import Keyring  # noqa: E402


class CalError(Exception):
    pass


_keyring = Keyring(SECRET_SERVICE, "account", CalError)   # "account": what entries were stored with


def secret_lookup(acc_id):
    return _keyring.lookup(acc_id)


def secret_store(acc_id, label, password):
    _keyring.store(acc_id, label, password)


def secret_clear(acc_id):
    _keyring.clear(acc_id)


def credentials(account):
    return account.get("username") or None, secret_lookup(account["id"]) if account.get("username") else None


ICS_DAYS = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
