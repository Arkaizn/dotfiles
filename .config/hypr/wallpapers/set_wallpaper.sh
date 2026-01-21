#!/usr/bin/env bash
set -Eeuo pipefail

WALLPAPER="${HOME}/.config/hypr/wallpapers/pywallpaper.png"
KITTY_CURRENT_THEME="${HOME}/.config/kitty/current-theme.conf"
HYPRLOCK_COLORS_CACHE="${HOME}/.cache/wal/hyprlock_colors"

# Set wallpaper
pgrep -x swww-daemon >/dev/null 2>&1 || swww-daemon >/dev/null 2>&1 &
swww img "$WALLPAPER" --transition-type wipe --transition-angle 210 --transition-fps 60 --transition-duration .5

# Remove cache
rm -fr ~/.cache/wal/schemes

# Run pywal
wal -i "$WALLPAPER"

# Reload hyprland
hyprctl reload

# Kitty
[[ -f "$HOME/.cache/wal/colors-kitty.conf" ]] && cp "$HOME/.cache/wal/colors-kitty.conf" "$KITTY_CURRENT_THEME"

# pywalfox / Firefox
command -v pywalfox >/dev/null 2>&1 && pywalfox update 2>/dev/null || true

# Hyprlock
[[ -f "$HOME/.cache/wal/colors" ]] && awk '{hex=substr($0,2);r=strtonum("0x"substr(hex,1,2));g=strtonum("0x"substr(hex,3,2));b=strtonum("0x"substr(hex,5,2));printf"export color%d=\"rgb(%d,%d,%d)\"\n",NR-1,r,g,b}' "$HOME/.cache/wal/colors" > "$HYPRLOCK_COLORS_CACHE"

# Quickshell
cp ~/.cache/wal/Colors.qml ~/.config/quickshell
chmod +x ~/.config/quickshell/Colors.qml

# Reload swaync
command -v swaync-client >/dev/null 2>&1 && swaync-client --reload-css || true

# OpenRGB - use pywal color directly
if [[ -f "$HOME/.cache/wal/colors.sh" ]]; then
  source "$HOME/.cache/wal/colors.sh"
  [[ -n "${color11:-}" ]] && openrgb --color "${color11#\#}" 2>/dev/null || true
fi
