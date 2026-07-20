#!/bin/bash

SILENTS=$1

magenta=170
blue=26
red=196
green=34

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

    # Wayland Hyprland/ Niri Desktop (Core)
    quickshell
    kitty
    wlogout
    hyprlock
    hyprpicker
    qt6-5compat
    nautilus

    # Niri
    niri 
    xwayland-satellite 
    xdg-desktop-portal-gnome
    swayidle
    qml-niri

    # Hyprland
    hyprland
    xdg-desktop-portal-hyprland
    hypridle
    hyprcursor
    hyprshot

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
)


necessary_vm_packages=(
    open-vm-tools
    mesa
    libglvnd
)

# Install yay if missing
install_yay() {
    gum style --foreground "$magenta" "Installing yay"
    
    if ! command -v yay &> /dev/null; then
        gum style --foreground "$blue" "yay not found. Installing dependencies and building..."
        
        if ! sudo pacman -S --needed git base-devel; then
            gum style --foreground "$red" "Failed to install dependencies. Aborting."
            return 1
        fi
        
        if ! git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si && cd .. && rm -rf yay; then
            gum style --foreground "$red" "Failed to build/install yay. Please install manually."
            choice=$(gum choose "Abort" "Skip yay")
            [[ "$choice" == "Skip yay" ]] || exit 1
        else
            gum style --foreground "$green" "yay installed successfully."
        fi
    else
        gum style --foreground "$green" "yay already installed."
    fi
}


install_packages() {
    gum style --foreground "$magenta" "Installing necessary packages"
    aborted=false
    for package in "${necessary_packages[@]}"; do
        if [[ $aborted == true ]]; then
            break
        fi
        gum style --foreground "$blue" "Installing $package"
        if [[ "$SILENTS" == "--silent" ]]; then
            if ! gum spin --spinner dot --title "Installing $package" -- yay -S --noconfirm --noanswerclean --noansweredit "$package"; then
                gum style --foreground "$red" "$package failed to install."
                choice=$(gum choose "Skip and continue" "Abort all installs")
                if [[ "$choice" == "Abort all installs" ]]; then
                    gum style --foreground "$red" "Aborting installation."
                    exit 1
                fi
            else
                gum style --foreground "$green" "$package installed successfully."
            fi
        else
            if ! yay -S --noconfirm --noanswerclean --noansweredit "$package"; then
                gum style --foreground "$red" "$package failed to install."
                choice=$(gum choose "Skip and continue" "Abort all installs")
                if [[ "$choice" == "Abort all installs" ]]; then
                    gum style --foreground "$red" "Aborting installation."
                    exit 1
                fi
            else
                gum style --foreground "$green" "$package installed successfully."
            fi
        fi
    done
}

# Ask if vmware
install_vmware_packages() {
    gum style --foreground "$magenta" "Installing necessary packages for VMware..."
    aborted=false
    
    install_vm_pkg() {
        vm_package="$1"
        gum style --foreground "$blue" "Installing $vm_package"
        
        if ! sudo yay -S --noconfirm --noanswerclean --noansweredit "$vm_package"; then
            gum style --foreground "$red" "$vm_package failed to install."
            choice=$(gum choose "Skip and continue" "Abort VM installs")
            [[ "$choice" == "Abort VM installs" ]] && exit 1
        else
            gum style --foreground "$green" "$vm_package installed successfully."
        fi
    }
    
    for vm_package in "${necessary_vm_packages[@]}"; do
        [[ $aborted == true ]] && break
        install_vm_pkg "$vm_package"
    done
    
    if [[ $aborted != true ]]; then
        sudo systemctl enable --now vmtoolsd.service
        gum style --foreground "$green" "VMware tools service enabled."
    fi
}

install_zsh() {
    gum style --foreground "$blue" "Configuring ZSH"
    if [[ "$SILENTS" == "--silent" ]]; then
    gum spin --spinner dot --title "Configuring ZSH" -- bash ./scripts/config.sh
    gum style --foreground "$green" "ZSH successfully configured"
    else
    bash ./scripts/config.sh
    gum style --foreground "$green" "ZSH successfully configured"
    fi
}


install_yay

if gum confirm "Do you want to install all necessary packages"; then
    install_packages
else
    gum style --foreground "$blue" "Skipping package installation."
fi

if gum confirm "Do you want to install all necessary packages"; then
    install_zsh
else
    gum style --foreground "$blue" "Skipping package installation."
fi

if gum confirm "Are you in a Vmware Virtual Machine?"; then
    install_vmware_packages
else
    gum style --foreground "$blue" "Skipping VMware packages."
fi