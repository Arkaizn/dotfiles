#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$HOME/git/dotfiles/.config"           # where dotfiles live in the repo
TARGET_DIR="$HOME/.config"                        # where they get synced to

# Files "default" protects from overwrite; "full" ignores this list
DEFAULT_EXCLUDES=(
    "custom/"
    "kitty/current-theme.conf"
    "quickshell/services/Colors.qml"
    "niri/config/layout.kdl"
    "hypr/hyprland/monitors.lua"
    "hypr/hyprlock/hyprlock.sh"
    "niri/config/output.kdl"
)

profile=$(gum choose "default" "full")            # ask user which sync mode to use
echo "Profile: $profile"

if [[ "$profile" == "default" ]]; then
    # copy everything except the protected files, overwriting existing configs
    gum spin --title "Syncing…" -- \
        rsync -av --exclude-from=<(printf '%s\n' "${DEFAULT_EXCLUDES[@]}") "$SOURCE_DIR/" "$TARGET_DIR/"

    # for protected files only, copy from source but never overwrite what's already there
    gum spin --title "Filling in protected files (existing files kept)…" -- \
        bash -c '
            src="$1"; dst="$2"; shift 2                                            # split args into named vars, leave excludes in "$@"
            printf "%s\n" "$@" | rsync -avr --ignore-existing --ignore-missing-args --files-from=- "$src/" "$dst/"
        ' _ "$SOURCE_DIR" "$TARGET_DIR" "${DEFAULT_EXCLUDES[@]}"
else
    # full profile: overwrite everything, no exceptions
    gum spin --title "Syncing…" -- rsync -av "$SOURCE_DIR/" "$TARGET_DIR/"
fi

gum spin --title "Syncing .zshrc" -- rsync ~/git/dotfiles/.config/.zshrc ~/

# reload compositor config and restart quickshell, depending on which session is running
if [[ -n "${NIRI_SOCKET:-}" ]]; then
    gum spin --title "Reloading (niri)…" -- bash -c 'pkill qs && niri msg action spawn -- sh -c "QS_NO_RELOAD_POPUP=1 QT_QPA_PLATFORMTHEME=qt6ct qs"'
elif [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    gum spin --title "Reloading (Hyprland)…" -- bash -c 'hyprctl reload || true; pkill qs && hyprctl dispatch "hl.dsp.exec_cmd(\"QS_NO_RELOAD_POPUP=1 QT_QPA_PLATFORMTHEME=qt6ct qs\")"'
else
    gum style --foreground 1 "Could not detect niri or Hyprland session — skipping reload."
fi

# temp (delete after a while / 1 Month?)

## 20/07/26
pacman -Qi niri &>/dev/null || sudo pacman -S niri --noconfirm
pacman -Qi xwayland-satellite &>/dev/null || sudo pacman -S xwayland-satellite --noconfirm
pacman -Qi xdg-desktop-portal-gnome &>/dev/null || sudo pacman -S xdg-desktop-portal-gnome --noconfirm
pacman -Qi swaybg &>/dev/null || sudo pacman -S swaybg --noconfirm
pacman -Qi swayidle &>/dev/null || sudo pacman -S swayidle --noconfirm
pacman -Qi qml-niri &>/dev/null || yay -S qml-niri --noconfirm

pacman -Qi wofi &>/dev/null && yay -Rns wofi --noconfirm
pacman -Qi swaylock &>/dev/null && yay -Rns swaylock --noconfirm
[ -d ~/.config/wofi ] && rm -fr ~/.config/wofi

## 

echo "Done ✅"