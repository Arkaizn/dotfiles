#!/usr/bin/env python3
"""Mail backend for the quickshell mail app (modules/mail, services/MailStore.qml).

IMAP + SMTP, so most providers work: iCloud, Gmail, Yahoo, Fastmail, GMX / Web.de,
mailbox.org, Posteo, your own server, Proton Mail Bridge (on this computer).
Standard library only. Passwords live in the keyring (secret-tool, service
quickshell-mail, id <account id>), never in the accounts file or a command line.

Usage:  mailsync.py <command>   with the request JSON in $MAIL_REQUEST,
        the answer is JSON on stdout: {"ok": true, ...} or {"ok": false, "error": "..."}

  autoconfig    {email}                     -> {imap, smtp, username, source, provider, hint, url}
  test          {account, password}         -> {folders}   (IMAP and SMTP login both checked)
  folders       {account}                   -> {folders: [{path, name, role, unread, total}]}
  sync          {accounts: [{account, folders: [{path, uidvalidity, uids}]}], limit}
                                            -> {results: [{account, folders: [...], error}]}
  body          {account, folder, uid, cache, allowRemote}
                                            -> {text, html, attachments, headers, remoteBlocked, source}
  attachment    {account, folder, uid, cache, index, dest}  -> {path}
  save-eml      {account, folder, uid, cache, dest}         -> {path}   (the whole message as .eml)
                body / attachment / view / save-eml also take {file, cache}: an .eml from disk
  flags         {account, folder, uids, add, remove}
  move          {account, folder, uids, to}
  delete        {account, folder, uids, trash}     (to trash, or for good when already there)
  search        {account, folder, query, known}     -> {uids, messages}
  send          {account, message, sentFolder}      -> {messageId}
  view          {account, folder, uid, cache, index}   -> {kind: image|pdf|text|other, path, name, type, pages, pageCount, text}
  export        {accounts, withPasswords, passphrase, path}   -> {path, count, encrypted}
  import-read   {path, passphrase}           -> {encrypted, needPassphrase, accounts: [… no passwords, hasPassword, errors]}
  import        {path, passphrase, pick: {email: newId}}  -> {accounts}   (passwords go straight to the keyring)
  invite        {account, event, method: REQUEST|CANCEL, sentFolder}  -> {messageId}   (iMIP, RFC 6047)
  store-secret  {id, label, password}
  forget-secret {id}

An account: {id, name, email, displayName, username, provider,
             imap: {host, port, security: ssl|starttls|none}, smtp: {…}}
("none" = no TLS, only for this computer: tests, Proton Mail Bridge).

The code lives in the mailsync/ package next to this file (cached as .pyc in
~/.cache/quickshell/pycache, not here); shared parts in scripts/lib/qsbackend.
"""
import os
import sys

# compiled modules go to the cache, not into the config folder (dotfiles repo)
sys.pycache_prefix = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "quickshell", "pycache")
_here = os.path.dirname(os.path.realpath(__file__))
sys.path[:0] = [_here, os.path.join(os.path.dirname(_here), "lib")]     # python3 -I leaves both off

from mailsync.cli import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
