#!/usr/bin/env bash
set -euo pipefail

WALLPAPER_DIR="${HOME}/.config/hypr/wallpapers/wal"
TARGET_WALLPAPER="${HOME}/.config/hypr/wallpapers/pywallpaper.png"
APPLY_SCRIPT="${HOME}/.config/hypr/wallpapers/set_wallpaper.sh"
THUMBNAIL_DIR="${HOME}/.cache/wallpaper-thumbnails"

build_menu() {
  while IFS= read -r -d '' wallpaper; do
    hash=$(echo -n "$wallpaper" | md5sum | cut -d' ' -f1)
    thumbnail="${THUMBNAIL_DIR}/${hash}.png"
    [[ -f "$thumbnail" ]] && echo -e "img:${thumbnail}:text: \t${wallpaper}"
  done < <(find "$WALLPAPER_DIR" -type f \( -iname '*.jpg' -o -iname '*.png' \) -print0)
}

selected=$(build_menu | wofi --dmenu --allow-images --allow-markup \
  -c "${HOME}/.config/wofi/config1" -s "${HOME}/.config/wofi/style1.css" \
  --prompt 'Select Wallpaper:' --insensitive 2>/dev/null | cut -f2)

cp "$selected" "$TARGET_WALLPAPER" 
"$APPLY_SCRIPT"
