#!/usr/bin/env bash
# Generate thumbnails using MD5 hash for unique naming

set -euo pipefail

WALLPAPER_DIR="${HOME}/.config/hypr/wallpapers/wal"
THUMBNAIL_DIR="${HOME}/.cache/wallpaper-thumbnails"
THUMBNAIL_WIDTH="400"

command -v magick >/dev/null 2>&1 || { echo "Missing: ImageMagick" >&2; exit 1; }
command -v md5sum >/dev/null 2>&1 || { echo "Missing: md5sum" >&2; exit 1; }

mkdir -p "$THUMBNAIL_DIR"

new_count=0
updated_count=0
skipped_count=0

echo "Generating thumbnails..."
echo ""

while IFS= read -r -d '' wallpaper; do
  # Use MD5 hash of full path for unique thumbnail name
  hash=$(echo -n "$wallpaper" | md5sum | cut -d' ' -f1)
  thumbnail="${THUMBNAIL_DIR}/${hash}.png"
  
  if [[ ! -f "$thumbnail" ]]; then
    echo "Creating: $(basename "$wallpaper")"
    magick "$wallpaper" -resize "${THUMBNAIL_WIDTH}x" "$thumbnail" 2>/dev/null && ((new_count++)) || true
  elif [[ "$wallpaper" -nt "$thumbnail" ]]; then
    echo "Updating: $(basename "$wallpaper")"
    magick "$wallpaper" -resize "${THUMBNAIL_WIDTH}x" "$thumbnail" 2>/dev/null && ((updated_count++)) || true
  else
    ((skipped_count++))
  fi
done < <(find "$WALLPAPER_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' \) -print0)

echo ""
echo "Complete! New: $new_count | Updated: $updated_count | Skipped: $skipped_count"
