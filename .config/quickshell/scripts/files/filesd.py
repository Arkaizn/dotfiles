#!/usr/bin/env python3
"""File manager backend (modules/files, FmBackend.qml): one long-running
process per file-manager instance, JSON lines on stdin / stdout.

Uses PyGObject (Gio, GLib): a conscious exception to the backends'
"standard library only" rule. Gio brings GVfs (remote places), the volume
monitor, file monitors, content types and default apps, which would each be
a project of their own. python-gobject is in packages.sh, Jobs.packages, the
update.sh package block and the Health check "filemanager". Run it as
`python3 -I` (no current folder or user site on sys.path).

Protocol (version 1). A request is one line:
    {"id": <int>, "op": "<name>", "args": {...}}
Each request ends with exactly one "done" or "error"; before that it may send
"batch" (part of a result) or "progress" lines:
    {"id": n, "type": "batch", "items": [item, ...]}
    {"id": n, "type": "done", ...result}
    {"id": n, "type": "error", "error": "<one line for the UI>", "code": <code>}
codes: denied | missing | notdir | exists | nospace | readonly | cancelled | io |
       invalid | unsupported
Events (no id):
    {"event": "ready", "pid": n, "version": 1}
    {"event": "changed", "watch": w, "changes": [{"kind": "upsert", "item": item} |
                                                 {"kind": "delete", "name": name}]}
    {"event": "changed", "watch": w, "rescan": true}     (too many at once: list again)
    {"event": "gone", "watch": w}                         (the folder itself went away)
    {"event": "places"}                                   (bookmarks / mounts / XDG dirs changed)

An item: {name, dir, size, mtime (s), type (content type), hidden, link, mode,
          owner, group (names), exec?, ro? (not writable by you), target? (a link's target), broken? (a link to nothing)}
          search results add {loc (folder relative to the search's), path, score}

Ops:
    ping                                  -> {pong}
    list    {path, hidden, sort, reverse, dirsFirst}
                                          -> batches of sorted items, then
                                             {count, hiddenCount, path, canWrite, fs (its file system type)}
            sort: name | size | mtime | type
    watch   {path}                        -> {watch}     (then "changed" / "gone" events)
    unwatch {watch}                       -> {}
    info    {paths: [...]}                -> {items: [item | null]}
    free    {path}                        -> {size, free}   (bytes of its file system)
    dirs    {path}                        -> {path, names, more}   its subfolders' names (links to
                                             folders too), sorted; at most 5000 (more: there were more)
    places                                -> {home, xdg: [...], bookmarks: [...], mounts: [...]}
    launch  {path}                        -> {}   (the default app for its type; never runs it)
    cancel  {target}                      -> {found}   (a listing, or an operation below)

Operations (filesd/ops.py has the "ask" lines and how they're answered). The long
ones send "progress" {done, total, bytes, totalBytes, current, paused} and may "ask":
    copy     {sources, dest, mode: copy|move|link|auto}   -> {made: [{src, dst}], skipped, mode, cancelled?}
             (into the same folder: "x (copy).txt"; a move there does nothing; auto: a move
             when every source is on dest's drive, else a copy — a drag without keys)
    relocate {pairs: [{from, to}]}        -> like copy (exact targets; undo of a move)
    trash    {paths}                      -> {trashed, deleted, skipped}   (freedesktop trash, via Gio)
    restore  {paths}                      -> {restored, missing, skipped}  (undo of trash: by original path)
    delete   {paths}                      -> {deleted, skipped}   (for good; never "/" or home)
    answer   {target, action, all?, name?} -> {found}
    pause    {target, paused}             -> {found}
Quick ones:
    rename   {path, name}                 -> {path, old}
    mkdir    {dir, name} · newfile {dir, name, template?}   -> {path}
    templates                             -> {dir, items: [{name, path, group}]}   (~/Templates)
    clipSet  {paths, cut}                 -> {count, cut}   (fmclip.py: gnome-copied-files, uri-list, text)
    clipGet                               -> {types, paths, cut, ours}
Knowing (Phase 4):
    search   {path, query, depth, hidden, kinds?, since?}  -> batches of items (+ loc, path, score), then
                                             {count, more (stopped at 2000), scanned}   cancellable
    thumb    {path, type, mtime, large?}   -> {thumb: png path | ""}   (shared ~/.cache/thumbnails)
    preview  {path, type}                  -> {kind: image | pdf | text | other, path, mime, pages, pageCount, text, truncated}
    props    {path}                        -> the item ("type" as "mime") + {owner, group, mine, atime, ctime, canWrite, width?, height?}
    du       {paths}                       -> {size, disk, files, dirs}   (a job: progress, cancel)
    counts   {dir, names, hidden}          -> {counts: {name: n | -1}}
    apps     {type}                        -> {mime, description, default, apps: [{id, name, icon, default}]}
             {all: true}                   -> {apps: [{id, name, icon}]}   every app (Open with → all apps)
    launchWith {paths, app}                -> {} · setDefault {type, app} -> {default}   (mimeapps.list backed up)
    chmod    {path, mode}                  -> {mode}   (yours only)
    chown    {path, owner, group, recursive?} -> {owner, group}   (pkexec: the shell's polkit agent asks)
Reaching (Phase 5; filesd/devices.py has the password "ask" lines):
    places                                 (+ volumes: [{id, name, canMount, canEject, icon, device, encrypted}])
    mount    {volume}                      -> {path, name}       (may ask: password / question)
    unmount  {uri, eject?}                 -> {}                 (a disk image's loop device goes too)
    connect  {uri}                         -> {path, uri}        smb / sftp / ftp / dav / nfs …: GVfs' FUSE folder
    network                                -> {items: [{name, uri, icon}]}
    mountImage {path}                      -> {path, device}     (.iso / .img read-only, udisksctl)
    compress {paths, dest, name, format: zip|tar.xz|tar.gz|tar.zst|7z, password?} -> {path}   (a job)
    extract  {path, dest}                  -> {path}   (a job; asks "password" when encrypted)
    trashList -> {items (+ path in the trash, info, orig, deleted)} · trashRestore / trashDelete {items: [{file, info, orig}]}
    bookmark {action: add {path, label?} | remove {uri} | rename {uri, label} | move {uri, step: ±1} | order {uris}}
    fileManager1 {on}                      -> {on}   own org.freedesktop.FileManager1 (events "fm1")
    trashEmpty · recent -> {items} · addRecent {path, type} · scripts -> {dir, scripts} · runScript {script, paths, cwd}
    save     {dir, name, text | base64}   -> {path}   (a drop that isn't a file; ≤ 50 MB, a free name)
    openUri  {uri}                        -> {}   (http(s) / mailto only: a saved web link)
    run      {path, terminal?}            -> {}   (an executable, only after the user said so)
    desktop  {path}                       -> {type, name, exec, url, comment, trusted}
    trust    {path} · launchDesktop {path} -> {}   (a .desktop launcher: trusted = yours, executable,
                                              writable only by you)

Paths are absolute local paths. File names travel only as JSON strings and
Gio / os arguments, never through a shell. Names that aren't valid UTF-8
come out as \\udcXX escapes (surrogateescape) and work when sent back.

One-shot (the launcher's Files mode): filesd.py --search BASE QUERY prints up to 60
results as JSON lines {name, path, loc, dir, type} and exits.

The code is in the filesd/ package next to this file (.pyc in
~/.cache/quickshell/pycache); tests: tests/files/test_filesd.py.
"""
import os
import sys

# compiled modules go to the cache, not into the config folder (dotfiles repo)
sys.pycache_prefix = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "quickshell", "pycache")
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))     # python3 -I leaves it off
# the backends' shared library (qsbackend: the PDF pages for the preview)
sys.path.insert(1, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))



def search_once(base, query):
    """the launcher's Files mode (the shell, without the file manager running):
    filesd.py --search BASE QUERY → up to 60 results as JSON lines, best first"""
    import json
    from filesd import search
    found = []
    search.run(base, query, {"depth": 64}, lambda: len(found) >= 200, found.extend)
    found.sort(key=lambda r: -r["score"])
    for r in found[:60]:
        sys.stdout.write(json.dumps({k: r[k] for k in ("name", "path", "loc", "dir", "type")}, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--search" and sys.argv[2].startswith("/"):
        sys.exit(search_once(sys.argv[2], sys.argv[3]))
    from filesd.server import main  # noqa: E402
    sys.exit(main())
