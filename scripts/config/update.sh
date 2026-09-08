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
DEFAULT_EXCLUDES=(
    "custom/"
    "kitty/current-theme.conf"
    "quickshell/services/Colors.qml"
    "niri/config/layout.kdl"
    "hypr/hyprland/monitors.lua"
    "hypr/hyprlock/hyprlock.sh"
    "niri/config/output.kdl"
)

profile=$(gum choose "default" "full")            # ask user which sync mode to use
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

    # copy everything except the protected files, overwriting existing configs
    gum spin --title "Syncing…" -- \
        rsync -a --exclude-from=<(printf '%s\n' "${anchored_excludes[@]}") \
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

changed=$(grep -cE '\[(copy|protected-copy)\]' "$LOG_FILE" 2>/dev/null || echo 0)
log ""
log "=== Sync finished: $changed file(s) touched. Full log: $LOG_FILE ==="
gum style --foreground 2 "$(printf '%s file(s) touched. Full log: %s' "$changed" "$LOG_FILE")"

# reload compositor config and restart quickshell, depending on which session is running
if [[ -n "${NIRI_SOCKET:-}" ]]; then
    gum spin --title "Reloading (niri)…" -- bash -c 'pkill qs && niri msg action spawn -- sh -c "QS_NO_RELOAD_POPUP=1 QT_QPA_PLATFORMTHEME=qt6ct qs"'
elif [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    gum spin --title "Reloading (Hyprland)…" -- bash -c 'hyprctl reload || true; pkill qs && hyprctl dispatch "hl.dsp.exec_cmd(\"QS_NO_RELOAD_POPUP=1 QT_QPA_PLATFORMTHEME=qt6ct qs\")"'
else
    gum style --foreground 1 "Could not detect niri or Hyprland session — skipping reload."
fi

# temp (delete after a while / 1 Month?)

## 20/07/26
pacman -Qi niri &>/dev/null || sudo pacman -S niri --noconfirm
pacman -Qi xwayland-satellite &>/dev/null || sudo pacman -S xwayland-satellite --noconfirm
pacman -Qi xdg-desktop-portal-gnome &>/dev/null || sudo pacman -S xdg-desktop-portal-gnome --noconfirm
pacman -Qi swaybg &>/dev/null || sudo pacman -S swaybg --noconfirm
pacman -Qi swayidle &>/dev/null || sudo pacman -S swayidle --noconfirm
pacman -Qi qml-niri &>/dev/null || yay -S qml-niri --noconfirm

pacman -Qi wofi &>/dev/null && yay -Rns wofi --noconfirm
pacman -Qi swaylock &>/dev/null && yay -Rns swaylock --noconfirm
[ -d ~/.config/wofi ] && rm -fr ~/.config/wofi

## 07/08/26

pacman -Qi kdbusaddons &>/dev/null || yay -S kdbusaddons --noconfirm

## 08/09/26
pacman -Qi polkit &>/dev/null || sudo pacman -S polkit
pacman -Qi polkit-gnome &>/dev/null || sudo pacman -S polkit-gnome

##

echo "Done ✅"