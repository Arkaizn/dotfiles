#!/usr/bin/env bash
set -e

WALLPAPER="${HOME}/.local/share/backgrounds/pywallpaper.png"
HYPRLOCK_COLORS_CACHE="${HOME}/.cache/wal/hyprlock_colors"

# Generate blurred wallpaper (same directory as the source wallpaper)
filename=$(basename -- "$WALLPAPER")
base="${filename%.*}"
ext="${filename##*.}"
WALLPAPER_DIR="$(dirname -- "$WALLPAPER")"
BLURRED="${WALLPAPER_DIR}/${base}-blurred.${ext}"
magick "$WALLPAPER" -blur 0x15 "$BLURRED"

# Set wallpaper
pkill swaybg 2>/dev/null || true
pgrep -x awww-daemon >/dev/null 2>&1 || awww-daemon >/dev/null 2>&1 &

# Set wallpaper
awww img "$WALLPAPER" --transition-type wipe --transition-angle 210 --transition-fps 60 --transition-duration .5
swaybg -i "$BLURRED" -m fill &

# Remove cache
rm -fr ~/.cache/wal/schemes

# Run pywal
wal -i "$WALLPAPER" -n 2>/dev/null || true

# Quickshell
[[ -e ~/.config/quickshell/services/Colors.qml ]] || rm -fr ~/.cache/wal/Colors.qml
cp -fr ~/.cache/wal/Colors.qml ~/.config/quickshell/services/Colors.qml

bash ~/.config/niri/niri-colors.sh

# Reload Hyprland
# hyprctl reload

# OpenRGB - use pywal color directly
export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:-}"
source "$HOME/.cache/wal/colors.sh"
openrgb --color "${color11#\#}" 2>/dev/null || true

