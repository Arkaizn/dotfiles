#!/bin/bash

magenta=170
blue=26
red=196
green=34

elevate_terminal() {
    sudo ls >/dev/null 2>&1
}

# install dependency gum 
install_gum() {
    if ! command -v gum &>/dev/null; then
        gum style --foreground 170 "Installing gum..."
        sudo pacman -Sy --noconfirm gum >/dev/null 2>&1
        gum spin --spinner dot --title "Installing gum..." -- sudo pacman -Sy --noconfirm gum
    fi
}

# Function: show menu with gum
menu() {
    MENUCHOICE=$(gum choose \
        "Run all steps" \
        "Update system" \
        "Install essential packages" \
        "Apply configuration files" \
        "Set theme and icons" \
        "Exit")

    case "$MENUCHOICE" in
        "Run all steps") run_all_steps ;;
        "Update system") update_system ;;
        "Install essential packages") install_packages ;;
        "Apply configuration files") apply_configs ;;
        "Set theme and icons") set_theme ;;
        "Exit") exit 0 ;;
    esac
}


output() {
    if gum confirm "Do you want to have full output during config installation?"; then
    output=yes
    else
    output=no
    fi
}

# System update
update_system() {
    gum style --foreground $magenta "🔄 Updating system..."
    if [[$ouput == yes]] ;then
    sudo pacman -Syu --noconfirm
    else
    gum spin --spinner dot --title "Updating System" -- sudo pacman -Syu --noconfirm
    fi
}

# Install necessary packages
install_packages() {
    gum style --foreground $magenta "📦 Installing essential packages..."
    if [[$ouput == yes]] ;then
    bash ./scripts/packages.sh
    else
    bash ./scripts/packages.sh --silent
    fi
}

# Apply configuration files
apply_config() {
    gum style --foreground $magenta "⚙️ Applying configuration files..."
    if [[ "$SILENTS" == "--silent" ]]; then
    gum spin --spinner dot --title "Copying Config" -- bash ./scripts/config.sh
    else
    bash ./scripts/config.sh
    fi
}

# Set theme and icons
set_theme_and_icons() {
    gum style --foreground $magenta "🎨 Setting themes and icons..."
    if [[$ouput == yes]] ;then
    bash ./scripts/themes.sh
    else
    bash ./scripts/themes.sh --silent
    fi
}

# Run all remaining steps
run_all_steps() {
    update_system && 
    install_packages && 
    apply_config && 
    set_theme_and_icons &&
    gum style --foreground $green "✅ All steps completed!"
}

elevate_terminal

# install gum if needed
install_gum

# Menu 
output

while true; do
    menu
done
