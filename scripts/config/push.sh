#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$HOME/.config"
TARGET_DIR="$HOME/git/dotfiles/.config"

choice=$(gum choose "push-lite" "push-all")

echo "You chose: $choice"

# Global always-skip files (never overwrite, never push)
GLOBAL_EXCEPTIONS=(
    "hypr/wallpapers/pywallpaper.png"
    "hypr/wallpapers/thumbs.db"
    "kitty/current-theme.conf"
)

copy_existing_only() {
    find "$TARGET_DIR" -mindepth 1 -maxdepth 1 | while read -r item; do
        rel_path="${item#$TARGET_DIR/}"
        src="$SOURCE_DIR/$rel_path"
        dst="$TARGET_DIR/$rel_path"

        if [ -e "$src" ]; then
            case "$choice" in
                "push-all")
                    if [ -d "$src" ]; then
                        rsync -av \
                            $(for g in "${GLOBAL_EXCEPTIONS[@]}"; do echo --exclude="$g"; done) \
                            "$src/" "$dst"
                    else
                        rsync -av \
                            $(for g in "${GLOBAL_EXCEPTIONS[@]}"; do echo --exclude="$g"; done) \
                            "$src" "$dst"
                    fi
                    ;;
                "push-lite")
                    if [ -d "$src" ]; then
                        rsync -av \
                            --exclude="custom" \
                            --exclude="hyprland/monitors.conf" \
                            $(for g in "${GLOBAL_EXCEPTIONS[@]}"; do echo --exclude="$g"; done) \
                            "$src/" "$dst"
                    else
                        rsync -av \
                            --exclude="custom" \
                            --exclude="hyprland/monitors.conf" \
                            $(for g in "${GLOBAL_EXCEPTIONS[@]}"; do echo --exclude="$g"; done) \
                            "$src" "$dst"
                    fi
                    ;;
            esac
        fi
    done
}

copy_existing_only

echo "Push done ✅"
