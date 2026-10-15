#!/bin/bash

source "$(dirname "$0")/../lib.sh"

packages=(
    wine
    winegui
    steam
    thunderbird
    nordvpn-bin
    vesktop-bin
    vmware-workstation
    vscodium
    firefox
    lutris
    lazydocker
    paleta
    pitivi
    openlinkhub
    archiso
    tailscale
    nmap
    openssh
    wayvnc
    obsidian
    docker
    docker-compose
    qimgv
    tigervnc
)

ensure_yay || exit 1

# everything is preselected, deselect what you don't want
mapfile -t selected < <(printf '%s\n' "${packages[@]}" | gum choose --no-limit --selected="*" \
    --header "Select apps to install (space to toggle, enter to confirm)")

if (( ${#selected[@]} == 0 )); then
    info "Nothing selected, skipping."
    exit 0
fi

yay_install "${selected[@]}" || exit 1

# vesktop theme
if [[ " ${selected[*]} " == *" vesktop-bin "* ]]; then
    mkdir -p ~/.config/vesktop/themes
    curl -fsSL https://raw.githubusercontent.com/ClearVision/ClearVision-v6/master/ClearVision_v6.theme.css \
        -o ~/.config/vesktop/themes/ClearVision_v6.theme.css && ok "Vesktop ClearVision theme"
fi
