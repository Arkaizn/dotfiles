#!/bin/bash
# guide: https://github.com/korvahannu/arch-nvidia-drivers-installation-guide/tree/main

source "$(dirname "$0")/../lib.sh"

# pass a driver name to override (default nvidia-dkms, e.g. for a 4070)
DRIVER="${1:-nvidia-dkms}"
HOOK_URL="https://raw.githubusercontent.com/korvahannu/arch-nvidia-drivers-installation-guide/main/nvidia.hook"
DEST_DIR="/etc/pacman.d/hooks"

run "Installing build dependencies" sudo pacman -S --needed --noconfirm base-devel linux-headers git || exit 1
yay_install "$DRIVER" nvidia-utils lib32-nvidia-utils || exit 1

hook=$(mktemp)
curl -fsSL "$HOOK_URL" -o "$hook" || { err "Hook download failed"; exit 1; }
sed -i "s/^Target=nvidia$/Target=${DRIVER}/" "$hook"

sudo mkdir -p "$DEST_DIR"
sudo install -m 644 "$hook" "$DEST_DIR/nvidia.hook"
rm -f "$hook"
ok "Hook live at $DEST_DIR/nvidia.hook targeting $DRIVER"
