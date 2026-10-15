#!/bin/bash

source "$(dirname "$0")/../lib.sh"

necessary_packages=(
    # Dependencies / Build Tools
    cmake
    meson
    pkg-config
    cpio

    # Essential Utilities
    nano
    curl
    wget
    rsync
    pacman-contrib
    zsh

    # System Info & Monitoring
    fastfetch
    lm_sensors
    gdu

    # Wayland Desktop (Core)
    quickshell
    kitty
    wlogout
    hyprlock
    hyprpicker
    qt6-5compat
    nautilus

    # Wayland Extras
    nwg-look
    wayvnc
    kvantum
    cava

    # Audio/Bluetooth
    pamixer
    pavucontrol
    bluez
    bluez-utils
    blueman

    # Network/WiFi
    networkmanager
    network-manager-applet
    nm-connection-editor
    networkmanager-openvpn
    openssh
    iwgtk
    iwd
    gvfs-smb

    # Storage/Mounting
    ntfs-3g
    p7zip

    # Clipboard/Wallpaper/Theming
    cliphist
    swww
    swaybg
    pywal-git
    python-pywalfox
    satty
    grim
    slurp
    tesseract
    tesseract-data-eng
    tesseract-data-deu

    # Browser
    zen-browser-bin
    firefox
    
    # Fonts
    ttf-jetbrains-mono-nerd
    ttf-nerd-fonts-symbols-mono
    noto-fonts-cjk 
    noto-fonts-emoji 
    noto-fonts

    # Lazy Vim / Neovim Setup
    vim
    nvim
    fd
    tree-sitter-cli
    fzf
    ripgrep
    lazygit

    # Miscellaneous Apps
    gnome-calculator
    kdbusaddons # dependency of Nextcloud
    nextcloud-client
    polkit
    polkit-gnome
)

niri_packages=(
    niri
    xwayland-satellite
    xdg-desktop-portal-gnome
    swayidle
    qml-niri
)

hyprland_packages=(
    hyprland
    xdg-desktop-portal-hyprland
    hypridle
    hyprcursor
    hyprshot
)

vm_packages=(
    open-vm-tools
    mesa
    libglvnd
)

ensure_yay || exit 1

# pick the compositor(s) to install
compositors=$(gum choose --no-limit --selected="Hyprland,Niri" \
    --header "Which compositor(s) do you want to install? (space to toggle)" \
    "Hyprland" "Niri")

packages=("${necessary_packages[@]}")
[[ "$compositors" == *Hyprland* ]] && packages+=("${hyprland_packages[@]}")
[[ "$compositors" == *Niri* ]] && packages+=("${niri_packages[@]}")

if gum confirm "Install ${#packages[@]} packages?"; then
    yay_install "${packages[@]}" || { err "Aborting installation."; exit 1; }
else
    info "Skipping package installation."
fi

if gum confirm "Are you in a VMware virtual machine?" --default=false; then
    yay_install "${vm_packages[@]}" &&
    sudo systemctl enable --now vmtoolsd.service &&
    ok "VMware tools service enabled"
fi
