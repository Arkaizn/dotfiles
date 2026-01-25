#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="${HOME}/.config"
TARGET_DIR="${HOME}/git/dotfiles/.config"

# Never overwrite or delete these (if they exist in target, they stay as-is)
SKIP_ALWAYS=(
  "hypr/wallpapers/pywallpaper.png"
  "custom/hyprland/custom.conf"
  "kitty/current-theme.conf"
  "hypr/hyprlock/hyprlock.sh"
  "quickshell/Colors.qml"
)

# Extra excludes for "push-lite"
LITE_EXCLUDES=(
  "custom"
  "hyprland/monitors.conf"
)

# Mode selection (gum if available, else arg or default)
if command -v gum >/dev/null 2>&1; then
  choice=$(gum choose "push-lite" "push-all")
else
  choice="${1:-push-lite}"
fi
echo "Mode: $choice"

# Safety: target must not be inside source
src_real="$(realpath -m "$SOURCE_DIR")"
dst_real="$(realpath -m "$TARGET_DIR")"
if [[ "$dst_real" == "$src_real"* ]]; then
  echo "ERROR: TARGET_DIR must not be inside SOURCE_DIR" >&2
  exit 1
fi

mkdir -p "$dst_real"

# Build an rsync filter that:
#  - Excludes SKIP_ALWAYS (protects them from overwrite/delete)
#  - Includes ONLY the top-level items that already exist in TARGET_DIR
#  - For dirs, includes everything under them
#  - Finally excludes everything else
filter_file="$(mktemp)"
trap 'rm -f "$filter_file"' EXIT

# 1) Protect "never-touch" files/paths
for p in "${SKIP_ALWAYS[@]}"; do
  printf -- "- %s\n" "$p" >>"$filter_file"
done

# 2) push-lite extra excludes
if [[ "$choice" == "push-lite" ]]; then
  for p in "${LITE_EXCLUDES[@]}"; do
    printf -- "- %s\n" "$p" >>"$filter_file"
  done
fi

# 3) Include only items that already exist in TARGET_DIR (top-level)
#    - For directories: include dir itself and all descendants
#    - For files: include the file
while IFS= read -r rel; do
  # Skip empty lines defensively
  [[ -z "$rel" ]] && continue
  if [[ -d "$dst_real/$rel" ]]; then
    printf -- "+ %s/\n"   "$rel" >>"$filter_file"
    printf -- "+ %s/***\n" "$rel" >>"$filter_file"
  elif [[ -f "$dst_real/$rel" ]]; then
    printf -- "+ %s\n" "$rel" >>"$filter_file"
  fi
done < <(find "$dst_real" -mindepth 1 -maxdepth 1 -printf "%f\n" | sort)

# 4) Exclude everything else
printf -- "- *\n" >>"$filter_file"

# Run rsync:
#  - Mirrors only included entries, deletes inside those dirs,
#  - Leaves SKIP_ALWAYS and excluded items untouched,
#  - Does NOT create new top-level entries in target.
rsync -a --delete --filter="merge $filter_file" "$src_real/" "$dst_real/"

echo "Push done ✅"
