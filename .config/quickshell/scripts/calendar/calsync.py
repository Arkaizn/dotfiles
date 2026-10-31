#!/usr/bin/env python3
"""Calendar backend for the quickshell calendar app (modules/calendar).

Speaks the standard protocols, so most providers work:
  caldav  CalDAV server: iCloud (https://caldav.icloud.com + app-specific
          password), Nextcloud, Fastmail, mailbox.org, Radicale, Baïkal, …
  ics     read-only .ics / webcal:// subscription (Google's and Outlook's
          "secret iCal address", holiday calendars, …)
  local   a .ics file on disk, read/write
  graph   Microsoft 365 work / school account (Exchange Online) through
          Microsoft Graph, read/write; signed in with a device code

Only the standard library + python-dateutil. Passwords (and Microsoft's
sign-in tokens) live in the keyring (secret-tool), never in the accounts file.

Usage:  calsync.py <command>   with the request JSON in $CAL_REQUEST,
        the answer is JSON on stdout: {"ok": true, ...} or {"ok": false, "error": "..."}

  discover      {type, url, username, password}  -> {calendars: [{href, name, color, readOnly}]}
  sync          {accounts, start, end}           -> {events: [...], errors: [...]}
  save          {account, calendar, event}       -> {}
  delete        {account, calendar, event, occurrence: bool}
  set-color     {account, calendar, color}       -> {}   (CalDAV: writes the calendar's color)
  store-secret  {id, label, password}
  forget-secret {id}
  graph-login   {id, tenant, clientId}  -> first line {step: "code", userCode, url, expiresIn},
                                           then waits for the sign-in and answers like discover
                                           (+ username); the tokens go to the keyring under id
  rediscover    {account}               -> like discover, with the account's keyring login
  import-read   {paths}                 -> {sources, total, upcoming, recurring, first, last, preview, errors}
  import        {paths, target, duplicates, upcomingOnly, alarms}
                                        -> lines {step: "progress", done, total}, then
                                           {imported, replaced, skipped, failed, created, newCalendars}
  import-undo   {account, calendar, created}  -> {removed}
  export-accounts {accounts, withPasswords, passphrase, path}  -> {path, count, encrypted}
                  (a local calendar's .ics goes with it; passwords / sign-ins only encrypted, GnuPG AES-256)
  import-accounts-read {path, passphrase}   -> {encrypted, needPassphrase, accounts: [… no secrets, hasPassword, hasData]}
  import-accounts {path, passphrase, pick: {index: newId}}  -> {accounts: [account + passwordStored, dataWritten]}

The code lives in the calsync/ package next to this file (cached as .pyc in
~/.cache/quickshell/pycache, not here); shared parts in scripts/lib/qsbackend.
"""
import os
import sys

# compiled modules go to the cache, not into the config folder (dotfiles repo)
sys.pycache_prefix = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "quickshell", "pycache")
_here = os.path.dirname(os.path.realpath(__file__))
sys.path[:0] = [_here, os.path.join(os.path.dirname(_here), "lib")]     # python3 -I leaves both off

from calsync.cli import main  # noqa: E402

if __name__ == "__main__":
    main()
