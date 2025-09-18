#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$HOME/git/dotfiles/.config"
TARGET_DIR="$HOME/.config"

# Let user choose mode with gum
choice=$(gum choose "standard" "full-lite" "full")

echo "You chose: $choice"

# Global always-skip files (only copy if missing)
GLOBAL_EXCEPTIONS=(
    "hypr/wallpapers/pywallpaper.png"
    "hypr/wallpapers/thumbs.db"
    "kitty/current-theme.conf"
)

# Function to copy all except exclusions
copy_all() {
    rsync -av "$SOURCE_DIR/" "$TARGET_DIR/"
}

copy_with_excludes() {
    rsync -av \
        --exclude="$1" \
        "$SOURCE_DIR/" "$TARGET_DIR/"
}

copy_with_multiple_excludes() {
    rsync -av \
        --exclude="hypr/hyprland/monitors.conf" \
        --exclude="hypr/hyprlock/hyprlock.sh" \
        "$SOURCE_DIR/" "$TARGET_DIR/"
}

case "$choice" in
    "standard")
        echo "Copying everything except hypr..."
        copy_with_excludes "hypr"
        ;;
    "full-lite")
        echo "Copying everything except monitors.conf and hyprlock.sh..."
        copy_with_multiple_excludes
        ;;
    "full")
        echo "Copying everything..."
        copy_all
        ;;
esac

# Handle custom/ → only copy missing files
if [ -d "$SOURCE_DIR/custom" ]; then
    echo "Checking custom/ for missing files..."
    find "$SOURCE_DIR/custom" -type f | while read -r src_file; do
        rel_path="${src_file#$SOURCE_DIR/}"
        dest_file="$TARGET_DIR/$rel_path"
        dest_dir="$(dirname "$dest_file")"
        if [ ! -f "$dest_file" ]; then
            mkdir -p "$dest_dir"
            cp "$src_file" "$dest_file"
            echo "Copied missing file: $rel_path"
        fi
    done
fi

# Handle global exceptions → copy only if missing
for rel_path in "${GLOBAL_EXCEPTIONS[@]}"; do
    src_file="$SOURCE_DIR/$rel_path"
    dest_file="$TARGET_DIR/$rel_path"
    if [ -f "$src_file" ] && [ ! -f "$dest_file" ]; then
        mkdir -p "$(dirname "$dest_file")"
        cp "$src_file" "$dest_file"
        echo "Copied missing global exception file: $rel_path"
    else
        echo "Skipped global exception (exists or not present): $rel_path"
    fi
done

# reload applications
hyprctl reload


echo "Done ✅"
