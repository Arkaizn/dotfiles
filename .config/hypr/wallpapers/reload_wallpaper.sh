#!/usr/bin/env bash
#
# Single‐script wallpaper switcher:
# – wal -i
# – Inline “hook”: updates Kitty, Firefox (pywalfox), hyprlock_colors
# – Throttles rapid invocations (0.5 s cooldown)
# – Runs non‐blocking tasks (reload SwayNC, copy wallpaper) in background
#
# Dependencies:
#   swww, wofi, wal, ImageMagick, swaync-client, pywalfox, awk, bc

# ─── CONFIG ─────────────────────────────────────────────────────────────────────

WALLPAPER_DIR="$HOME/.config/hypr/wallpapers/wal"
COOLDOWN=0.5                        # seconds between allowed runs
KITTY_CURRENT_THEME="$HOME/.config/kitty/current-theme.conf"
HYPRLOCK_COLORS_CACHE="$HOME/.cache/wal/hyprlock_colors"
PYWALLPAPER="$HOME/.config/hypr/wallpapers/pywallpaper.png"

# ─── HELPERS ────────────────────────────────────────────────────────────────────

set_wallpaper() {
    local img="$PYWALLPAPER"
    swww img "$img" \
        --transition-type wipe \
        --transition-angle 210 \
        --transition-fps 60 \
        --transition-duration .5
}

run_wal() {
    wal -i "$PYWALLPAPER"
}

wal_hook_tasks() {
    if [[ -f "$HOME/.cache/wal/colors-kitty.conf" ]]; then
        cp "$HOME/.cache/wal/colors-kitty.conf" "$KITTY_CURRENT_THEME"
    fi
    if command -v pywalfox &>/dev/null; then
        pywalfox update
    fi
    if [[ -f "$HOME/.cache/wal/colors" ]]; then
        awk '{
            hex = substr($0, 2)
            r = strtonum("0x" substr(hex, 1, 2))
            g = strtonum("0x" substr(hex, 3, 2))
            b = strtonum("0x" substr(hex, 5, 2))
            printf "export color%d=\"rgb(%d,%d,%d)\"\n", NR-1, r, g, b
        }' "$HOME/.cache/wal/colors" > "$HYPRLOCK_COLORS_CACHE"
    fi
}

sync_openrgb() {
    RAW=$(grep -m1 '^color9=' ~/.cache/wal/colors.sh)
    COLOR=${RAW#*\#}
    COLOR=${COLOR%\'}
    openrgb --color "$COLOR"
    echo "Applied color: $COLOR"
}

reload_swaync() {
    if command -v swaync-client &>/dev/null; then
        swaync-client --reload-css
    fi
}

copy_current_wallpaper() {
    local img="$1"
    cp "$img" "$PYWALLPAPER_DST"
}

# ─── MAIN ───────────────────────────────────────────────────────────────────────

main() {
    set_wallpaper "$selected"
    copy_current_wallpaper "$selected" &
    run_wal "$selected" && wal_hook_tasks
    reload_swaync
    sync_openrgb
}

main
