#!/usr/bin/env bash
# The one way into the file manager from outside: the desktop entry, the
# niri / Hyprland binds, the main shell's Panels proxy and update.sh all call
# this. Starts the file manager's Quickshell process (files.qml) if it isn't
# running, waits until its IPC answers, then hands each request over.
#
#   files.sh                       a new window on home (Mod+E, the launcher)
#   files.sh [PATH|file://URI]...  each in the window used last (the tab on it, else a new tab;
#                                  a file: its folder with the file selected); no window yet: a new one
#   files.sh --select PATH         its folder, with it selected
#   files.sh --new-window [PATH]   a new window (default: home)
#   files.sh --start               only start the process (update.sh)
#
# Arguments only ever go to qs as single argv entries; nothing is evaluated.
set -euo pipefail

# BASH_SOURCE, not $0: the desktop entry sources this file (bash -c ". …/files.sh" files %U),
# which keeps its Exec line free of quotes — xdg-open splits Exec on spaces and
# ignores quoting, GLib strips it; this form means the same to both
here=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
qml="$(dirname "$(dirname "$here")")/files.qml"

# the answer is the last line: under a non-UTF-8 locale qs prints a warning on stdout first
ipc() { qs ipc -p "$qml" call files "$@" | tail -n 1; }
alive() { [[ "$(ipc ping 2>/dev/null)" == ok ]]; }

if ! alive; then
    # -n: a second start at the same moment exits instead of making another instance;
    # -d: detached, so it outlives the caller (a launcher, a terminal)
    # the GTK icon theme (Preferences → "Use the icon theme's icons"; Qt alone falls back to
    # hicolor, which has no folder / file-type icons); read when the process starts
    theme=${QS_ICON_THEME:-$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'" || true)}
    QS_SETTINGS_REMOTE=1 QS_NO_RELOAD_POPUP=1 QT_QPA_PLATFORMTHEME="${QT_QPA_PLATFORMTHEME:-qt6ct}" QS_ICON_THEME="$theme" \
        qs -n -d -p "$qml" >/dev/null 2>&1 || true
    for _ in $(seq 100); do alive && break; sleep 0.05; done
    alive || { echo "files.sh: the file manager didn't start (qs log -p $qml)" >&2; exit 1; }
fi

# a path relative to the caller's folder becomes absolute; URIs and absolute paths stay
abs() { case "$1" in *://*|/*) printf '%s' "$1" ;; *) readlink -m -- "$1" ;; esac; }
say() { r=$(ipc "$@") || return 1; [[ "$r" == ok ]] || { echo "files.sh: $r" >&2; return 1; }; }

case "${1:-}" in
    --start) exit 0 ;;
    "") say newWindow "$HOME" ;;
    --new-window) say newWindow "$(abs "${2:-$HOME}")" ;;
    --select) [[ -n "${2:-}" ]] || { echo "files.sh: --select needs a path" >&2; exit 2; }
              say select "$(abs "$2")" ;;
    *)
        st=0
        for a in "$@"; do say open "$(abs "$a")" || st=1; done
        exit $st ;;
esac
