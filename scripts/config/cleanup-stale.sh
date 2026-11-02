#!/usr/bin/env bash
# Remove files from ~/.config that the repo used to ship but has since deleted
# or renamed (e.g. modules/Launcher -> modules/launcher). update.sh copies the
# repo over ~/.config without --delete, so those old copies would stay behind,
# and in quickshell an old QML file in an imported folder can shadow the new
# one and break the whole shell.
#
# Safe by design:
#   - only paths that exist in the repo's git history as deleted AND are not in
#     the repo now: files that were never in the repo are never touched
#   - per-device files (DEVICE_FILES in sync-excludes.sh) are always kept
#   - nothing is deleted: files are moved to ~/.local/state/dotfiles-sync/stale-<date>/
#
# usage: cleanup-stale.sh [--dry-run] [log file]
set -euo pipefail

REPO="$HOME/git/dotfiles"
SOURCE_DIR="$REPO/.config"
TARGET_DIR="$HOME/.config"

dry=0
if [[ "${1:-}" == "--dry-run" ]]; then dry=1; shift; fi
LOG_FILE="${1:-/dev/null}"

# shellcheck source=sync-excludes.sh disable=SC1091  # path is only known at runtime
source "$(dirname "$(readlink -f "$0")")/sync-excludes.sh"

log() { printf '%s\n' "$1" | tee -a "$LOG_FILE"; }

is_device_file() {
    local rel=$1 e
    for e in "${DEVICE_FILES[@]}"; do
        if [[ "$e" == */ ]]; then [[ "$rel" == "$e"* ]] && return 0
        else [[ "$rel" == "$e" ]] && return 0
        fi
    done
    return 1
}

BACKUP_DIR="$HOME/.local/state/dotfiles-sync/stale-$(date +%Y%m%d-%H%M%S)"
moved=0
dirs=()

# every path under .config/ that some commit deleted (renames count as delete + add)
while IFS= read -r path; do
    [[ "$path" == .config/* ]] || continue
    rel=${path#.config/}
    [[ -e "$SOURCE_DIR/$rel" || -L "$SOURCE_DIR/$rel" ]] && continue   # back in the repo
    [[ -f "$TARGET_DIR/$rel" || -L "$TARGET_DIR/$rel" ]] || continue   # not here anyway
    is_device_file "$rel" && continue

    if (( dry )); then
        log "[stale] would move: $rel"
    else
        mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
        mv "$TARGET_DIR/$rel" "$BACKUP_DIR/$rel"
        log "[stale] moved: $rel"
        dirs+=("$(dirname "$TARGET_DIR/$rel")")
    fi
    moved=$((moved + 1))
done < <(git -C "$REPO" log --no-renames --diff-filter=D --name-only --format= -- .config | sort -u)

# drop folders that are empty now (only the ones we emptied, up to ~/.config)
for d in "${dirs[@]}"; do
    while [[ "$d" != "$TARGET_DIR" && "$d" == "$TARGET_DIR"/* ]] && rmdir "$d" 2>/dev/null; do
        d=$(dirname "$d")
    done
done

if (( moved == 0 )); then
    log "Stale files: none"
elif (( dry )); then
    log "Stale files: $moved would be moved"
else
    log "Stale files: moved $moved to $BACKUP_DIR"
fi
