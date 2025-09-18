#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$HOME/.config"
TARGET_DIR="$HOME/git/dotfiles/.config"

echo "Checking differences (lite mode)…"

# Global always-skip files (never overwrite, never push)
GLOBAL_EXCEPTIONS=(
    "hypr/wallpapers/pywallpaper.png"
    "hypr/wallpapers/thumbs.db"
    "kitty/current-theme.conf"
)

# Build exclude args dynamically
GLOBAL_EXCLUDES=()
for g in "${GLOBAL_EXCEPTIONS[@]}"; do
    GLOBAL_EXCLUDES+=( --exclude="$g" )
done

DIFF_FOUND=0

check_existing_only() {
    find "$TARGET_DIR" -mindepth 1 -maxdepth 1 | while read -r item; do
        rel_path="${item#$TARGET_DIR/}"
        src="$SOURCE_DIR/$rel_path"
        dst="$TARGET_DIR/$rel_path"

        if [ -e "$src" ]; then
            if [ -d "$src" ]; then
                out=$(rsync -av --dry-run --itemize-changes \
                    --exclude="custom" \
                    --exclude="hyprland/monitors.conf" \
                    "${GLOBAL_EXCLUDES[@]}" \
                    "$src/" "$dst")
            else
                out=$(rsync -av --dry-run --itemize-changes \
                    --exclude="custom" \
                    --exclude="hyprland/monitors.conf" \
                    "${GLOBAL_EXCLUDES[@]}" \
                    "$src" "$dst")
            fi

            if [ -n "$out" ]; then
                echo "$out"
                DIFF_FOUND=1
            fi
        fi
    done
}

check_existing_only

if [ "$DIFF_FOUND" -eq 0 ]; then
    echo "✅ Up to date"
    exit 0
else
    echo "❌ Differences found"
    exit 1
fi
