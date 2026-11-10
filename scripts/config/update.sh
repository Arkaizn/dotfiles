#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$HOME/git/dotfiles/.config"           # where dotfiles live in the repo
TARGET_DIR="$HOME/.config"                        # where they get synced to

LOG_DIR="$HOME/.local/state/dotfiles-sync"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/sync-$(date +%Y%m%d-%H%M%S).log"

# Prints AND appends to the log file. Plain echo, so it's not swallowed by
# gum spin (that only hides the output of the command it wraps).
log() {
    printf '%s\n' "$1" | tee -a "$LOG_FILE" >/dev/null
}

log "=== Dotfiles sync started $(date) ==="

# Files "default" protects from overwrite; "full" ignores this list.
# NOTE: these are root-relative paths (relative to SOURCE_DIR).
# Per-device files (protected): see sync-excludes.sh — one list for all sync scripts.
# shellcheck source=sync-excludes.sh disable=SC1091  # path is only known at runtime
source "$(dirname "$(readlink -f "$0")")/sync-excludes.sh"
DEFAULT_EXCLUDES=("${DEVICE_FILES[@]}")

# profile: first argument (default | full), or ask (e.g. the quickshell settings app passes it)
profile=${1:-}
case "$profile" in
    default|full) ;;
    "") profile=$(gum choose "default" "full") ;;
    *) echo "usage: $0 [default|full]" >&2; exit 2 ;;
esac
echo "Profile: $profile"

if [[ "$profile" == "default" ]]; then
    # Build exclude patterns anchored to the source root.
    # A leading "/" forces rsync to match only "<root>/custom/", not
    # "<root>/anything/.../custom/" (which is what an unanchored "custom/"
    # would do, e.g. quickshell/.../custom/ getting silently skipped).
    anchored_excludes=()
    for e in "${DEFAULT_EXCLUDES[@]}"; do
        anchored_excludes+=("/$e")
    done

    log "[mode] default — overwriting everything except protected files"

    # IMPORTANT: use a real temp file, not <(process substitution).
    # gum runs rsync as ITS OWN subprocess, and a /dev/fd/NN path from process
    # substitution only exists in the shell that created it — it does not
    # survive being passed through gum to a grandchild process. rsync would
    # fail instantly ("No such file or directory") with no visible error
    # (gum spin hides it), and set -e would silently kill the script here —
    # which is exactly what was happening.
    EXCLUDE_FILE=$(mktemp)
    trap 'rm -f "$EXCLUDE_FILE"' EXIT
    printf '%s\n' "${anchored_excludes[@]}" > "$EXCLUDE_FILE"

    # copy everything except the protected files, overwriting existing configs
    gum spin --title "Syncing…" -- \
        rsync -a --exclude-from="$EXCLUDE_FILE" \
            --log-file="$LOG_FILE" --log-file-format='%t [copy] %i %n' \
            "$SOURCE_DIR/" "$TARGET_DIR/"

    # log, per protected file, whether it already exists (kept) or is missing (about to be copied)
    for f in "${DEFAULT_EXCLUDES[@]}"; do
        if [[ -e "$TARGET_DIR/$f" ]]; then
            log "[check] protected, exists — keeping local: $f"
        else
            log "[check] protected, missing — will copy from repo: $f"
        fi
    done

    # for protected files only, copy from source but never overwrite what's already there
    # shellcheck disable=SC2016  # the script is for the inner bash, single quotes on purpose
    gum spin --title "Filling in protected files (existing files kept)…" -- \
        bash -c '
            src="$1"; dst="$2"; log="$3"; shift 3                                  # split args into named vars, leave excludes in "$@"
            printf "%s\n" "$@" | rsync -ar --ignore-existing --ignore-missing-args --files-from=- \
                --log-file="$log" --log-file-format="%t [protected-copy] %i %n" "$src/" "$dst/"
        ' _ "$SOURCE_DIR" "$TARGET_DIR" "$LOG_FILE" "${DEFAULT_EXCLUDES[@]}"
else
    log "[mode] full — overwriting everything, no exceptions"

    # full profile: overwrite everything, no exceptions
    gum spin --title "Syncing…" -- \
        rsync -a --log-file="$LOG_FILE" --log-file-format='%t [copy] %i %n' "$SOURCE_DIR/" "$TARGET_DIR/"
fi

gum spin --title "Syncing .zshrc" -- \
    rsync -a --log-file="$LOG_FILE" --log-file-format='%t [copy] %i %n' ~/git/dotfiles/.config/.zshrc ~/

# files the repo deleted or renamed: move the old copies out of ~/.config
# (the rsync above doesn't --delete; leftovers can shadow new QML files and break quickshell)
bash "$HOME/git/dotfiles/scripts/config/cleanup-stale.sh" "$LOG_FILE" || log "[stale] cleanup failed, continuing"

# link launcher entries (~/.config/*/applications/*.desktop) if they aren't linked yet
"$HOME/git/dotfiles/scripts/config/desktop-entries.sh" | tee -a "$LOG_FILE"

changed=$(grep -cE '\[(copy|protected-copy)\]' "$LOG_FILE" 2>/dev/null || echo 0)
log ""
log "=== Sync finished: $changed file(s) touched. Full log: $LOG_FILE ==="
gum style --foreground 2 "$(printf '%s file(s) touched. Full log: %s' "$changed" "$LOG_FILE")"

# reload compositor config and restart quickshell, depending on which session is running.
# Two qs processes run from ~/.config/quickshell: the shell (shell.qml) and, when
# open, the file manager (files.qml, scripts/files/files.sh). Both are stopped by
# their command line (the shell: `qs` with no -p / -c; test copies and other
# configs are left alone — `pkill -x qs` hit those too),
# the shell is started again, and the file manager only if it was running (its
# windows come back from its state file).
# shellcheck disable=SC2016  # the scripts are for the inner bash, single quotes on purpose
stop_qs='qs_pids() { for p in $(pgrep -u "$(id -u)" -x qs); do c=$(tr "\0" " " < "/proc/$p/cmdline" 2>/dev/null) || continue; case "$c" in *"/quickshell/files.qml "*) [ "$1" = files ] && echo "$p" ;; *" -p "*|*" -c "*|*" --path"*|*" --config"*) ;; *) [ "$1" = shell ] && echo "$p" ;; esac; done; }
    files=0; [ -n "$(qs_pids files)" ] && files=1
    for w in shell files; do pids=$(qs_pids $w); [ -n "$pids" ] && kill $pids; done
    for _ in $(seq 50); do [ -z "$(qs_pids shell)$(qs_pids files)" ] && break; sleep 0.1; done
    pids="$(qs_pids shell) $(qs_pids files)"; [ -n "${pids// }" ] && kill -9 $pids || true'
files_start='[ "$files" = 1 ] && '
if [[ -n "${NIRI_SOCKET:-}" ]]; then
    gum spin --title "Reloading (niri)…" -- bash -c "$stop_qs"'
    niri msg action spawn -- sh -c "QS_NO_RELOAD_POPUP=1 QT_QPA_PLATFORMTHEME=qt6ct qs"
    '"$files_start"'niri msg action spawn -- bash "$HOME/.config/quickshell/scripts/files/files.sh" --start || true'
elif [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    gum spin --title "Reloading (Hyprland)…" -- bash -c 'hyprctl reload || true; '"$stop_qs"'
    hyprctl dispatch "hl.dsp.exec_cmd(\"QS_NO_RELOAD_POPUP=1 QT_QPA_PLATFORMTHEME=qt6ct qs\")"
    '"$files_start"'hyprctl dispatch "hl.dsp.exec_cmd(\"bash $HOME/.config/quickshell/scripts/files/files.sh --start\")" || true'
else
    gum style --foreground 1 "Could not detect niri or Hyprland session — skipping reload."
fi

# temp (delete after a while / 2 Month?)

## 18/09/26
pacman -Qi satty &>/dev/null || yay -S satty --noconfirm
pacman -Qi grim &>/dev/null || yay -S grim --noconfirm
pacman -Qi slurp &>/dev/null || yay -S slurp --noconfirm

pacman -Qi tesseract &>/dev/null || yay -S tesseract --noconfirm
pacman -Qi tesseract-data-eng &>/dev/null || yay -S tesseract-data-eng --noconfirm
pacman -Qi tesseract-data-deu &>/dev/null || yay -S tesseract-data-deu --noconfirm

## 17/10/26
# calendar app: calsync.py needs dateutil, account passwords go to the keyring (secret-tool)
pacman -Qi python-dateutil &>/dev/null || sudo pacman -S python-dateutil --noconfirm
pacman -Qi libsecret &>/dev/null || sudo pacman -S libsecret --noconfirm
pacman -Qi gnome-keyring &>/dev/null || sudo pacman -S gnome-keyring --noconfirm

## 03/11/26
# file manager (Quickshell): backend, thumbnails, devices, network, archives — official repos only
for p in python-gobject gnome-desktop-4 gvfs gvfs-mtp gvfs-gphoto2 gvfs-nfs gvfs-dnssd gvfs-wsdd udisks2 ffmpegthumbnailer poppler 7zip unzip zip; do
    pacman -Qi "$p" &>/dev/null || sudo pacman -S "$p" --noconfirm
done
# Files opens folders, once per machine (the marker keeps a later choice in Settings →
# Default apps from being undone by the next update); mimeapps.list is backed up first,
# like the Default apps page does. desktop-entries.sh above linked the entry.
files_marker="$HOME/.local/state/quickshell/files-default-set"
if [[ ! -e "$files_marker" && -e "${XDG_DATA_HOME:-$HOME/.local/share}/applications/quickshell-files.desktop" ]]; then
    mkdir -p "$HOME/.local/state/quickshell/backups"
    mimeapps="${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"
    [[ -f "$mimeapps" ]] && cp -p -- "$mimeapps" "$HOME/.local/state/quickshell/backups/mimeapps.list.$(date +%Y%m%d-%H%M%S)"
    xdg-mime default quickshell-files.desktop inode/directory && touch "$files_marker"
fi

## 09/11/26
# mediasync (music card: queue, lyrics, playlists) comes from the AUR package now.
# Older hand installs left a binary in ~/.local/bin and a user unit in ~/.config/systemd/user
# that starts it; both shadow the package, so the card misses its newer features.
# Nothing is deleted: the old files go to ~/.local/state/dotfiles-sync/mediasync-old/.
if [[ ! -x /usr/bin/mediasyncd ]]; then
    yay -S --needed --noconfirm mediasync || echo "mediasync: install failed, run: yay -S mediasync"
fi
ms_old="$HOME/.local/state/dotfiles-sync/mediasync-old"
ms_unit="$HOME/.config/systemd/user/mediasyncd.service"
if [[ -f "$ms_unit" ]] && grep -q '\.local/bin/mediasyncd' "$ms_unit"; then
    mkdir -p "$ms_old"; mv -f "$ms_unit" "$ms_old/"
fi
for b in mediasyncd mediasyncctl; do
    if [[ -e "$HOME/.local/bin/$b" ]]; then mkdir -p "$ms_old"; mv -f "$HOME/.local/bin/$b" "$ms_old/"; fi
done
if [[ -x /usr/bin/mediasyncd ]]; then
    systemctl --user daemon-reload
    systemctl --user enable mediasyncd.service &>/dev/null || true
    # pacman doesn't restart user services: restart when the binary is newer than the running daemon
    ms_started=$(systemctl --user show -p ActiveEnterTimestamp --value mediasyncd.service)
    if ! systemctl --user is-active -q mediasyncd.service || [[ -z "$ms_started" ]] \
        || (( $(stat -c %Y /usr/bin/mediasyncd) > $(date -d "$ms_started" +%s) )); then
        systemctl --user restart mediasyncd.service || true
    fi
fi



echo "Done ✅"