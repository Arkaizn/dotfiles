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
LOCKFILE="/tmp/.wallpaper_switch.lock"
COOLDOWN=0.5                        # seconds between allowed runs
KITTY_CURRENT_THEME="$HOME/.config/kitty/current-theme.conf"
HYPRLOCK_COLORS_CACHE="$HOME/.cache/wal/hyprlock_colors"
PYWALLPAPER_DST="$HOME/.config/hypr/wallpapers/pywallpaper.png"

# ─── HELPERS ────────────────────────────────────────────────────────────────────

# Return current timestamp with nanoseconds (for float math)
now_ts() { date +%s.%N; }

# Build Wofi menu entries (prefix each line with “img:” so we can strip it easily)
menu() {
    find "$WALLPAPER_DIR" -type f \
         \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" \) \
         | sed 's|^|img:|'
}

# Throttle: if last run was under $COOLDOWN seconds ago, exit immediately
throttle_check() {
    if [[ -f "$LOCKFILE" ]]; then
        LAST_TS=$(<"$LOCKFILE")
    else
        LAST_TS=0
    fi
    CUR_TS=$(now_ts)
    DIFF=$(echo "$CUR_TS - $LAST_TS" | bc -l)

    if (( $(echo "$DIFF < $COOLDOWN" | bc -l) )); then
        exit 0
    fi

    echo "$CUR_TS" > "$LOCKFILE"
}

# Set the wallpaper via swww (blocks until transition is finished)
set_wallpaper() {
    local img="$1"
    swww img "$img" \
        --transition-type wipe \
        --transition-angle 210 \
        --transition-fps 60 \
        --transition-duration .5
}

# Count unique colors using ImageMagick’s identify
# If identify fails (e.g. not installed or unreadable file), return 256
count_unique_colors() {
    local img="$1"
    local count
    count=$(identify -format "%k\n" "$img" 2>/dev/null) || count=256
    echo "$count"
}

# Run wal exactly once, picking the correct backend based on “unique_color_count”
run_wal() {
    local img="$1"
    wal -i "$img"
}

# After wal completes, perform “hook‐like” tasks inline:
#   1) Copy colors-kitty.conf → Kitty’s live theme
#   2) Run pywalfox update (if installed)
#   3) Generate hyprlock_colors from ~/.cache/wal/colors
wal_hook_tasks() {
    # 1) Kitty theme
    if [[ -f "$HOME/.cache/wal/colors-kitty.conf" ]]; then
        cp "$HOME/.cache/wal/colors-kitty.conf" "$KITTY_CURRENT_THEME"
    fi

    # 2) Firefox theme (pywalfox)
    if command -v pywalfox &>/dev/null; then
        pywalfox update
    fi

    # 3) hyprlock_colors (RGB exports from wal’s hex list)
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

set_openrgb() {

    # Grab the raw line
    RAW=$(grep -m1 '^color11=' ~/.cache/wal/colors.sh)

    # Strip everything up to '#', then strip trailing quote: yields CF1B1B
    COLOR=${RAW#*\#}
    COLOR=${COLOR%\'}

    # Apply to all devices

    openrgb --color "$COLOR"

    echo "Applied color: $COLOR"
}

set_openlinkhub() {

    # Grab the raw line
    RAW=$(grep -m1 '^color11=' ~/.cache/wal/colors.sh)
    # Strip to get just the six hex digits in $COLOR:
    COLOR=${RAW#*\#}
    COLOR=${COLOR%\'*}
    echo "DEBUG: COLOR=\"$COLOR\""  >&2

    # Convert hex → decimal using the same variable name:
    R=$((16#${COLOR:0:2}))
    G=$((16#${COLOR:2:2}))
    B=$((16#${COLOR:4:2}))

    # Verify:
    echo "Parsed → R=$R, G=$G, B=$B"  >&2
    
    # change color in config with sed
    sed -i -E '/"static"/,/"minTemp"/{ 
    /"start"/,/\}/{ 
        s/("red":[[:space:]]*)[0-9]+/\1'"$R"'/; 
        s/("green":[[:space:]]*)[0-9]+/\1'"$G"'/; 
        s/("blue":[[:space:]]*)[0-9]+/\1'"$B"'/ 
    } 
    /"end"/,/\}/{ 
        s/("red":[[:space:]]*)[0-9]+/\1'"$R"'/; 
        s/("green":[[:space:]]*)[0-9]+/\1'"$G"'/; 
        s/("blue":[[:space:]]*)[0-9]+/\1'"$B"'/ 
    } 
    }' /var/lib/openlinkhub/database/rgb/71CB611182670C51BA1E355AA2FCE4B5.json

    # restart openlinkhub service
    systemctl restart openlinkhub.service
}

# Reload SwayNC CSS (fire-and-forget)
reload_swaync() {
    if command -v swaync-client &>/dev/null; then
        swaync-client --reload-css
    fi
}

# Copy the chosen wallpaper into a “current” location for Hyprlock (fire-and-forget)
copy_current_wallpaper() {
    local img="$1"
    cp "$img" "$PYWALLPAPER_DST"
}

# ─── MAIN ───────────────────────────────────────────────────────────────────────

main() {
    throttle_check

    # 1) Launch Wofi to pick “img:/path/to/image.jpg”. Strip the “img:” prefix.
    choice=$(menu | wofi -c ~/.config/wofi/config1 \
                       -s ~/.config/wofi/style1.css \
                       --show dmenu --prompt "Select Wallpaper:" -n)

    if [[ -z "$choice" ]]; then
        echo "No wallpaper selected."
        exit 1
    fi
    selected=${choice#img:}

    # 2) Immediately set the wallpaper (blocks until wipe transition completes)
    set_wallpaper "$selected"

    # 3) Reload SwayNC and copy current‐wallpaper in the background
    
    copy_current_wallpaper "$selected" &

    # 4) Run wal exactly once, choosing backend <255→colorthief, else→walroeg, 
    #    then run hook tasks inline.
    run_wal "$selected" && wal_hook_tasks
    reload_swaync
    set_openrgb
    set_openlinkhub
}

main
