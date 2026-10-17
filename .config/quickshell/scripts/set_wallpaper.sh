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
# setsid -f: fully detached, so stopping this script from quickshell leaves them running
pgrep -x awww-daemon >/dev/null 2>&1 || setsid -f awww-daemon >/dev/null 2>&1
# wait (max ~2s) for the daemon to answer before sending it an image
for _ in {1..20}; do awww query >/dev/null 2>&1 && break; sleep 0.1; done

# Set wallpaper awww
awww img "$WALLPAPER" --transition-type wipe --transition-angle 210 --transition-fps 60 --transition-duration .5

# Set wallpaper swaybg
setsid -f swaybg -i "$BLURRED" -m fill >/dev/null 2>&1

# Remove cache
rm -fr ~/.cache/wal/schemes

# Run pywal
wal -i "$WALLPAPER" -n 2>/dev/null || true

# Quickshell: services/Colors.qml reads ~/.cache/wal/colors.json (written by wal
# above) and updates live — no generated QML copied in, so the shell doesn't
# reload and open windows (settings, calendar) stay open.

# Niri
bash ~/.config/niri/niri-colors.sh

# OpenRGB - use pywal color directly
export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:-}"
source "$HOME/.cache/wal/colors.sh"
openrgb --color "${color11#\#}" 2>/dev/null || true

