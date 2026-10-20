#!/usr/bin/env bash
# Switch the desktop between light and dark (Settings → Shell → Theme).
#   color-mode.sh light|dark [--wal] [--niri] [--portal] [--gtk THEME]
#                            [--icons THEME] [--kvantum THEME] [--qtcolors FILE]
# --wal       pywal colors from the current wallpaper (wal -l for light)
# --niri      niri's border colors follow (niri-colors.sh)
# --portal    the "prefer light / dark" setting apps read (libadwaita, browsers, Electron)
# --gtk       GTK theme (gsettings, gtk-3.0 / gtk-4.0 settings.ini, gtk-4.0 css links)
# --icons     icon theme (GTK and qt6ct)
# --kvantum   Kvantum theme + qt6ct style (kvantum / kvantum-dark)
# --qtcolors  qt6ct color scheme file
# Every config file it changes is copied to ~/.local/state/quickshell/backups/color-mode/
# the first time.
set -uo pipefail

mode=${1:-}
case "$mode" in light|dark) ;; *) echo "usage: $0 light|dark [options]" >&2; exit 2 ;; esac
shift

state="$HOME/.local/state/quickshell"
backups="$state/backups/color-mode"
mkdir -p "$backups"
echo "$mode" > "$state/color-mode"

dark=1; [ "$mode" = light ] && dark=0
cfg="${XDG_CONFIG_HOME:-$HOME/.config}"

backup() {   # once per file
    [ -e "$1" ] || [ -L "$1" ] || return 0
    local name b
    name=${1#"$HOME"/}
    b="$backups/${name//\//_}"
    [ -e "$b" ] || cp -a -- "$1" "$b"
}

# set key=value in an ini-style file (adds the line if missing)
ini_set() {
    local file=$1 key=$2 value=$3
    [ -f "$file" ] || return 0
    backup "$file"
    if grep -q "^$key=" "$file"; then
        sed -i "s|^$key=.*|$key=$value|" "$file"
    else
        printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
}

theme_dir() {   # first install location of a GTK theme
    local d
    for d in "$HOME/.themes" "$HOME/.local/share/themes" /usr/share/themes; do
        [ -d "$d/$1" ] && { echo "$d/$1"; return 0; }
    done
    return 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --wal)
            wp=$(jq -r '.wallpaper // empty' "$HOME/.cache/wal/colors.json" 2>/dev/null)
            [ -n "$wp" ] && [ -f "$wp" ] || wp="$HOME/.local/share/backgrounds/pywallpaper.png"
            # checked: a failed wal used to go unnoticed (apps switched, the shell stayed as it was)
            if ! command -v wal >/dev/null; then
                echo "ERROR shell colors: wal isn't installed" >&2; failed=1
            elif ! out=$(if [ "$mode" = light ]; then wal -q -n -i "$wp" -l; else wal -q -n -i "$wp"; fi 2>&1); then
                echo "ERROR shell colors: wal failed on $wp: $(printf '%s\n' "$out" | grep -v -e 'convert command is deprecated' -e '^$' | tail -n 2 | tr '\n' ' ')" >&2; failed=1
            else
                # the new background must match the mode (light = bright)
                bg=$(jq -r '.special.background // empty' "$HOME/.cache/wal/colors.json" 2>/dev/null)
                if [[ $bg =~ ^#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$ ]]; then
                    l=$(( (2126 * 16#${BASH_REMATCH[1]} + 7152 * 16#${BASH_REMATCH[2]} + 722 * 16#${BASH_REMATCH[3]}) / 10000 ))
                    is=dark; [ "$l" -gt 127 ] && is=light
                    [ "$is" = "$mode" ] || { echo "ERROR shell colors: wal ran, but ~/.cache/wal/colors.json is still $is (background $bg)" >&2; failed=1; }
                fi
            fi
            ;;
        --niri)
            [ -x "$cfg/niri/niri-colors.sh" ] && { backup "$cfg/niri/config/layout.kdl"; bash "$cfg/niri/niri-colors.sh"; }
            ;;
        --portal)
            gsettings set org.gnome.desktop.interface color-scheme "prefer-$mode"
            ;;
        --gtk)
            t=$2; shift
            gsettings set org.gnome.desktop.interface gtk-theme "$t"
            for f in "$cfg/gtk-3.0/settings.ini" "$cfg/gtk-4.0/settings.ini"; do
                ini_set "$f" gtk-theme-name "$t"
                ini_set "$f" gtk-application-prefer-dark-theme "$dark"
            done
            # libadwaita (GTK 4) apps read ~/.config/gtk-4.0/gtk.css: point it at the theme
            if dir=$(theme_dir "$t") && [ -d "$dir/gtk-4.0" ]; then
                for n in gtk.css gtk-dark.css assets; do
                    target="$cfg/gtk-4.0/$n"
                    [ -e "$dir/gtk-4.0/$n" ] || continue
                    backup "$target"   # a link is copied as a link
                    ln -sfn "$dir/gtk-4.0/$n" "$target"
                done
            fi
            ;;
        --icons)
            t=$2; shift
            gsettings set org.gnome.desktop.interface icon-theme "$t"
            for f in "$cfg/gtk-3.0/settings.ini" "$cfg/gtk-4.0/settings.ini"; do ini_set "$f" gtk-icon-theme-name "$t"; done
            ini_set "$cfg/qt6ct/qt6ct.conf" icon_theme "$t"
            ini_set "$cfg/qt5ct/qt5ct.conf" icon_theme "$t"
            ;;
        --kvantum)
            t=$2; shift
            backup "$cfg/Kvantum/kvantum.kvconfig"
            if command -v kvantummanager >/dev/null; then kvantummanager --set "$t" >/dev/null 2>&1; else ini_set "$cfg/Kvantum/kvantum.kvconfig" theme "$t"; fi
            style=kvantum; [ "$mode" = dark ] && style=kvantum-dark
            ini_set "$cfg/qt6ct/qt6ct.conf" style "$style"
            ini_set "$cfg/qt5ct/qt5ct.conf" style "$style"
            ;;
        --qtcolors)
            ini_set "$cfg/qt6ct/qt6ct.conf" color_scheme_path "$2"; shift
            ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
echo "now $mode"
[ "${failed:-0}" = 1 ] && exit 3
exit 0
