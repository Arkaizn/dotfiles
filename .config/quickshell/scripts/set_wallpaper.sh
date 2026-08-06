#!/usr/bin/env bash

WALLPAPER="${HOME}/.local/share/backgrounds/pywallpaper.png"
HYPRLOCK_COLORS_CACHE="${HOME}/.cache/wal/hyprlock_colors"

# Generate blurred wallpaper (same directory as the source wallpaper)
filename=$(basename -- "$WALLPAPER")
base="${filename%.*}"
ext="${filename##*.}"
WALLPAPER_DIR="$(dirname -- "$WALLPAPER")"
BLURRED="${WALLPAPER_DIR}/${base}-blurred.${ext}"

magick "$WALLPAPER" -resize 10% -blur 0x6 -resize 1000% "$BLURRED"

# kill wallpaper
pkill swaybg 2>/dev/null || true
pgrep -x awww-daemon >/dev/null 2>&1 || awww-daemon >/dev/null 2>&1 &

# Set wallpaper awww
awww img "$WALLPAPER" --transition-type wipe --transition-angle 210 --transition-fps 60 --transition-duration .5

# Set wallpaper swaybg
swaybg -i "$BLURRED" -m fill &

# Remove cache
rm -fr ~/.cache/wal/schemes

# Run pywal
wal -i "$WALLPAPER" -n 2>/dev/null || true

# Quickshell
cp -fr ~/.cache/wal/Colors.qml ~/.config/quickshell/services/Colors.qml

# Niri
bash ~/.config/niri/niri-colors.sh

# OpenRGB - use pywal color directly
export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:-}"
source "$HOME/.cache/wal/colors.sh"
openrgb --color "${color11#\#}" 2>/dev/null || true

