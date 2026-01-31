#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$HOME/git/dotfiles/.config"
TARGET_DIR="$HOME/.config"

echo "Pulling dotfiles"
cd $HOME/git/dotfiles && git pull > /dev/null 2>&1
echo "done."
clear

choice=$(gum choose "full-lite" "standard" "full")
echo "You chose: $choice"

# Files that should only be created if missing (never overwritten)
GLOBAL_EXCEPTIONS=(
  "hypr/wallpapers/pywallpaper.png"
  "hypr/wallpapers/thumbs.db"
  "kitty/current-theme.conf"
  "quickshell/Colors.qml"
)

# Base rsync flags
RSYNC_FLAGS=(-av)

# Always exclude custom/** so contents are handled by the missing-only copier,
# and also exclude every GLOBAL_EXCEPTION so rsync never overwrites them.
COMMON_EXCLUDES=(--exclude="custom/**")
for rel in "${GLOBAL_EXCEPTIONS[@]}"; do
  COMMON_EXCLUDES+=( "--exclude=$rel" )
done

copy_all() {
  rsync "${RSYNC_FLAGS[@]}" "${COMMON_EXCLUDES[@]}" \
    "$SOURCE_DIR/" "$TARGET_DIR/"
}

copy_with_excludes() {
  rsync "${RSYNC_FLAGS[@]}" "${COMMON_EXCLUDES[@]}" \
    --exclude="$1" \
    "$SOURCE_DIR/" "$TARGET_DIR/"
}

copy_with_multiple_excludes() {
  rsync "${RSYNC_FLAGS[@]}" "${COMMON_EXCLUDES[@]}" \
    --exclude="hypr/hyprland/monitors.conf" \
    --exclude="hypr/hyprlock/hyprlock.sh" \
    "$SOURCE_DIR/" "$TARGET_DIR/"
}

case "$choice" in
  "standard")
    echo "Copying everything except hypr… (custom/ + global exceptions preserved)"
    copy_with_excludes "hypr"
    ;;
  "full-lite")
    echo "Copying everything except monitors.conf + hyprlock.sh… (custom/ + global exceptions preserved)"
    copy_with_multiple_excludes
    ;;
  "full")
    echo "Copying everything… (custom/ + global exceptions preserved)"
    copy_all
    ;;
esac

# custom/: only create missing files (never replace existing)
if [ -d "$SOURCE_DIR/custom" ]; then
  echo "Checking custom/ for missing files..."
  while IFS= read -r -d '' src_file; do
    rel_path="${src_file#$SOURCE_DIR/}"
    dest_file="$TARGET_DIR/$rel_path"
    dest_dir="$(dirname "$dest_file")"
    if [ ! -f "$dest_file" ]; then
      mkdir -p "$dest_dir"
      cp -n "$src_file" "$dest_file"
      echo "Copied missing file: $rel_path"
    else
      echo "Kept existing file: $rel_path"
    fi
  done < <(find "$SOURCE_DIR/custom" -type f -print0)
fi

# Global exceptions: copy only if missing
for rel_path in "${GLOBAL_EXCEPTIONS[@]}"; do
  src_file="$SOURCE_DIR/$rel_path"
  dest_file="$TARGET_DIR/$rel_path"
  if [ -f "$src_file" ] && [ ! -f "$dest_file" ]; then
    mkdir -p "$(dirname "$dest_file")"
    cp -n "$src_file" "$dest_file"
    echo "Copied missing global exception file: $rel_path"
  else
    echo "Skipped global exception (exists or not present): $rel_path"
  fi
done

# Reload Hyprland (don’t fail script if not running)
hyprctl reload || true
pkill qs && hyprctl dispatch exec qs
pkill swaync && hyprctl dispatch exec swaync 

echo "Done ✅"
