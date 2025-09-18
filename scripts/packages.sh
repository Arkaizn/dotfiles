#!/bin/bash
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
NC="\033[0m" # No Color

#---------------------------------------------------------------------Define essential packages
essential_packages=(
    nano
    curl
    wget
    fastfetch
    hyprland
    kitty
    hyprlock
    hyprcursor
    hyprshot
    hyprpicker
    xdg-desktop-portal-hyprland
    pacman-contrib
    pamixer
    ntfs-3g
    p7zip
    wofi
    thunar
    waybar
    wlogout
    swaync
    cliphist
    pywal-git
    python-pywalfox
    swww
    zen-browser-bin
    nerd-fonts
    cmake
    meson
    cpio
    pkg-config
    openssh
    iwgtk
    iwd
    pavucontrol
    blueman
    wayvnc
    python-colorthief
    gnome-calculator
    qimgv
    gdu
    nwg-look
    hypridle
    lm_sensors
    rsync
    bc
    gum
)

essential_vm_packages=(
    open-vm-tools
    mesa
    libglvnd
)

# install yay
# Check if yay is installed
if command -v yay &>/dev/null; then
    echo "yay is already installed. Skipping installation."
else
    echo "yay is not installed. Proceeding with installation."

    # Install necessary dependencies
    sudo pacman -S --needed base-devel

    # Clone, build, and install yay in a subshell
    (
        git clone https://aur.archlinux.org/yay.git
        cd yay || exit 1
        makepkg -si
    )
    rm -rf yay
fi

# ------------------------------------------------------------------install packages
# Show packages that will be installed
echo -e "${YELLOW}The following packages will be installed:${NC}"
for package in "${essential_packages[@]}"; do
    echo -e "${GREEN}- $package${NC}"
done

# Confirm package installation
echo -e "${YELLOW}Proceed with the installation? (y/n)${NC}"
read -r -p "Answer: " proceed
case "$proceed" in
    ""|[yY][eE][sS]|[yY])
        echo -e "${YELLOW}Installing essential packages...${NC}"
        for package in "${essential_packages[@]}"; do
            echo -e "${YELLOW}Installing $package...${NC}"
            if yay -S --noconfirm --noanswerclean --noansweredit "$package"; then
                echo -e "${GREEN}$package installed successfully.${NC}"
            else
                echo -e "${RED}Failed to install $package. Skipping...${NC}"
                echo -e "${RED}Press a button to proceed.${NC}"
                read

            fi
        done
        ;;
    *)
        echo -e "${YELLOW}Installation cancelled. Skipping...${NC}"
        ;;
esac

# Ask if vmware
echo -e "${YELLOW}Are you in a Vmware Virtual Machine? (y/n)${NC}"
read -r -p "Answer: " proceed
case "$proceed" in
    ""|[yY][eE][sS]|[yY])
        echo -e "${YELLOW}Installing essential packages for vmware...${NC}"
        for vm_package in "${essential_vm_packages[@]}"; do
            echo -e "${YELLOW}Installing $vm_package...${NC}"
            if sudo yay -S --noconfirm --noanswerclean --noansweredit "$vm_package"; then
                echo -e "${GREEN}$vm_package installed successfully.${NC}"
            else
                echo -e "${RED}Failed to install $vm_package. Skipping...${NC}"
                read
            fi
        done
        sudo systemctl enable --now vmtoolsd.service # enable service
        ;;
    *)
        echo -e "${YELLOW}Installation cancelled. Skipping...${NC}"
        ;;
esac