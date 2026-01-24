#!/usr/bin/env bash
set -e

WALLPAPER="${HOME}/.config/hypr/wallpapers/pywallpaper.png"
HYPRLOCK_COLORS_CACHE="${HOME}/.cache/wal/hyprlock_colors"

# Set wallpaper
pgrep -x swww-daemon >/dev/null 2>&1 || swww-daemon >/dev/null 2>&1 &
swww img "$WALLPAPER" --transition-type wipe --transition-angle 210 --transition-fps 60 --transition-duration .5

# Remove cache
rm -fr ~/.cache/wal/schemes

# Run pywal
wal -i "$WALLPAPER" 2>/dev/null || true

# pywalfox / Firefox
command -v pywalfox >/dev/null 2>&1 && pywalfox update 2>/dev/null || true

# Quickshell
[[ -e ~/.config/quickshell/Colors.qml ]] || ln -s ~/.cache/wal/Colors.qml ~/.config/quickshell/Colors.qml

# Reload swaync
command -v swaync-client >/dev/null 2>&1 && swaync-client --reload-css || true

# OpenRGB - use pywal color directly
export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:-}"
source "$HOME/.cache/wal/colors.sh"
openrgb --color "${color11#\#}" 2>/dev/null || true
