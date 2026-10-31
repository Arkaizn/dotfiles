import json
import os
import re
import subprocess

from qsbackend import Keyring, lazy
imaplib = lazy('imaplib')
smtplib = lazy('smtplib')
ssl = lazy('ssl')


SECRET_SERVICE = "quickshell-mail"


TIMEOUT = 30


PREVIEW = 2048           # bytes of the first text part fetched for the list preview


LIMIT = 300              # newest messages kept per folder


LOCAL_HOSTS = ("127.0.0.1", "localhost", "::1")


class MailError(Exception):
    pass


_keyring = Keyring(SECRET_SERVICE, "id", MailError, fake_env="MAIL_FAKE_SECRETS")   # "id": what entries were stored with


def secret_lookup(acc_id):
    return _keyring.lookup(acc_id)


def secret_store(acc_id, label, password):
    _keyring.store(acc_id, label, password)


def secret_clear(acc_id):
    _keyring.clear(acc_id)


def password_of(account, req=None):
    pw = (req or {}).get("password") or secret_lookup(account["id"])
    if not pw:
        raise MailError("No password in the keyring for " + (account.get("name") or account.get("email") or "this account")
                        + " — edit the account and enter it again")
    return pw


HOST_RE = re.compile(r"^(?=.{1,253}$)[A-Za-z0-9]([A-Za-z0-9-]{0,62}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,62}[A-Za-z0-9])?)*$|^\d{1,3}(\.\d{1,3}){3}$|^::1$")


def server_of(account, kind):
    s = account.get(kind) or {}
    host = str(s.get("host") or "").strip()
    if not HOST_RE.match(host):
        raise MailError(f"The {kind.upper()} server name isn't valid: {host or '(empty)'}")
    try:
        port = int(s.get("port"))
    except (TypeError, ValueError):
        raise MailError(f"The {kind.upper()} port isn't a number")
    if not 0 < port < 65536:
        raise MailError(f"The {kind.upper()} port is out of range")
    sec = s.get("security") or "ssl"
    if sec not in ("ssl", "starttls", "none"):
        raise MailError(f"Unknown {kind.upper()} security: {sec}")
    if sec == "none" and host not in LOCAL_HOSTS:
        raise MailError("Without encryption only servers on this computer are allowed (like Proton Mail Bridge)")
    return host, port, sec


def tls_context(host):
    ctx = ssl.create_default_context()
    if host in LOCAL_HOSTS:          # local bridges (Proton) use a self-signed certificate
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    return ctx


def friendly(e):
    """network / login exceptions -> one readable line"""
    if isinstance(e, MailError):
        return str(e)
    if isinstance(e, imaplib.IMAP4.error):
        m = str(e)
        m = re.sub(r"^b?['\"]|['\"]$", "", m)
        if re.search(r"AUTHENTICATIONFAILED|Invalid credentials|LOGIN failed|authentication failed|Web login required|Application-specific password",
                     m, re.I):
            return "The server didn't accept the login (" + m.strip() + "). Most providers want an app password here."
        return "IMAP: " + m
    if isinstance(e, smtplib.SMTPAuthenticationError):
        return "The mail server (SMTP) didn't accept the login: " + (e.smtp_error.decode(errors="replace") if isinstance(e.smtp_error, bytes) else str(e.smtp_error))
    if isinstance(e, smtplib.SMTPRecipientsRefused):
        return "Refused recipients: " + ", ".join(e.recipients)
    if isinstance(e, smtplib.SMTPException):
        return "SMTP: " + str(e)
    if isinstance(e, ssl.SSLCertVerificationError):
        return "The server's certificate isn't valid: " + (e.verify_message or str(e))
    if isinstance(e, ssl.SSLError):
        return "Encryption failed (" + str(e.reason or e) + ") — is the security setting / port right?"
    if isinstance(e, TimeoutError) or "timed out" in str(e):
        return "The server didn't answer (timeout)"
    if isinstance(e, ConnectionRefusedError):
        return "Connection refused — wrong port, or the server is down"
    if isinstance(e, OSError) and getattr(e, "errno", None) in (-2, -3, -5):
        return "Server not found — check the name, or the internet connection"
    return str(e) or e.__class__.__name__
