#!/usr/bin/env bash
set -euo pipefail
SOURCE_DIR="$HOME/.config"                         # where your live configs are
TARGET_DIR="$HOME/git/dotfiles/.config"             # where they get pushed to (repo)

# Files/dirs to leave alone when pushing (host-specific or repo-managed)
DEFAULT_EXCLUDES=(
"custom/hyprland/custom.lua"
"kitty/current-theme.conf"
"hypr/hyprlock/hyprlock.sh"
"quickshell/services/Colors.qml"
"niri/config/layout.kdl"
"custom"
"hypr/hyprland/monitors.lua"
"niri/config/output.kdl"
"cava"
)

profile=$(gum choose "default" "full")              # ask user which push mode to use
echo "Profile: $profile"

rsync_args=(-av --delete)

# only protect files in "default" mode
if [[ "$profile" == "default" ]]; then
    for e in "${DEFAULT_EXCLUDES[@]}"; do
        rsync_args+=(--exclude="$e")
    done
fi

# only sync top-level folders that already exist in TARGET_DIR
while IFS= read -r name; do
    rsync_args+=(--include="$name/" --include="$name/**")
done < <(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
rsync_args+=(--exclude="*")

gum spin --title "Pushing…" -- rsync "${rsync_args[@]}" "$SOURCE_DIR/" "$TARGET_DIR/"

echo "Push done ✅"