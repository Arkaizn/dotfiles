#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$HOME/git/dotfiles/.config"
TARGET_DIR="$HOME/.config"

# Files "default" protects from overwrite; "full" ignores this list
DEFAULT_EXCLUDES=(
    "custom/"
    "hypr/wallpapers/pywallpaper.png"
    "hypr/wallpapers/thumbs.db"
    "kitty/current-theme.conf"
    "quickshell/services/Colors.qml"
    "niri/config/layout.kdl"
    "hypr/hyprland/monitors.lua"
    "hypr/hyprlock/hyprlock.sh"
    "niri/config/output.kdl"
)

gum spin --title "Pulling dotfiles…" -- git -C "$HOME/git/dotfiles" pull --quiet

profile=$(gum choose "default" "full")
echo "Profile: $profile"

if [[ "$profile" == "default" ]]; then
    gum spin --title "Syncing…" -- \
        rsync -av --exclude-from=<(printf '%s\n' "${DEFAULT_EXCLUDES[@]}") "$SOURCE_DIR/" "$TARGET_DIR/"

    gum spin --title "Filling in protected files (existing files kept)…" -- \
        bash -c 'printf "%s\n" "$@" | rsync -avr --ignore-existing --files-from=- "$0/" "$1/"' \
        "$SOURCE_DIR" "$TARGET_DIR" "${DEFAULT_EXCLUDES[@]}"
else
    gum spin --title "Syncing…" -- rsync -av "$SOURCE_DIR/" "$TARGET_DIR/"
fi

gum spin --title "Reloading…" -- bash -c 'pkill qs && niri msg action spawn -- sh -c "QS_NO_RELOAD_POPUP=1 qs"'

echo "Done ✅"