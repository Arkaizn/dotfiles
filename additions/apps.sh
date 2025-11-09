#!/bin/bash

# packages list
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
for package in "${packages[@]}"; do
    echo -e "${GREEN}- $package${NC}"
done

# Confirm package installation
echo -e "${YELLOW}Proceed with the installation? (y/n)${NC}"
read -r -p "Answer: " proceed
case "$proceed" in
    ""|[yY][eE][sS]|[yY])
        echo -e "${YELLOW}Installing essential packages...${NC}"
        for package in "${packages[@]}"; do
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

# setting vesktop theme
(
    git clone https://github.com/ClearVision/ClearVision-v6.git
    cd ClearVision-v6
    cp ./ClearVision_v6.theme.css ~/.config/vesktop/themes
    cd ..
    rm -fr ClearVision-v6
)

