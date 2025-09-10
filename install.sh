#!/bin/bash

# install gum
if ! command -v gum &>/dev/null; then
    echo "Installing gum..."
    sudo pacman -Sy --noconfirm gum >/dev/null 2>&1
fi

# Color definitions
PURPLE="\033[0;35m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
NC="\033[0m"

# Track completed steps
done_steps=()

# Function: show menu with gum
show_menu() {
    MENUCHOICE=$(gum choose \
        "Run all remaining steps" \
        "Update system" \
        "Install essential packages" \
        "Install and configure Zsh" \
        "Apply configuration files" \
        "Set theme and icons" \
        "Exit")

    case "$MENUCHOICE" in
        "Run all remaining steps") run_remaining_steps ;;
        "Update system")
            [[ ! " ${done_steps[@]} " =~ " update_system " ]] \
                && update_system \
                || gum confirm "Already completed. Run again?" && update_system
            ;;
        "Install essential packages")
            [[ ! " ${done_steps[@]} " =~ " install_essential " ]] \
                && install_essential \
                || gum confirm "Already completed. Run again?" && install_essential
            ;;
        "Install and configure Zsh") install_zsh ;;
        "Apply configuration files") apply_configs ;;
        "Set theme and icons") set_theme ;;
        "Exit") exit 0 ;;
    esac
}

# Function to prompt the user with a yes/no dialog
ask_user() {
    gum confirm "$1"
    return $?
}

mark_done() {
    done_steps+=("$1")
}

# System update
update_system() {
    gum style --foreground 212 "🔄 Updating system..."
    sudo pacman -Syu --noconfirm
    mark_done "update_system"
}

# Install essential packages
install_packages() {
    gum style --foreground 212 "📦 Installing essential packages..."
    bash ./scripts/packages.sh
    mark_done "install_packages"
}

# Install Zsh
install_zsh() {
    if ask_user "Do you want to install and configure Zsh?"; then
        gum style --foreground 212 "💻 Installing and configuring Zsh..."
        bash ./scripts/zshinstall.sh
        mark_done "install_zsh"
    else
        gum style --foreground 244 "⏭️  Skipping Zsh installation."
    fi
}

# Apply configuration files
apply_config() {
    gum style --foreground 212 "⚙️ Applying configuration files..."
    bash ./scripts/config.sh
    mark_done "apply_config"
}

# Set theme and icons
set_theme_and_icons() {
    gum style --foreground 212 "🎨 Setting theme and icons..."
    bash ./scripts/theme.sh
    bash ./scripts/icons.sh
    mark_done "set_theme_and_icons"
}

# Run all remaining steps
run_remaining_steps() {
    [[ ! " ${done_steps[@]} " =~ " update_system " ]] && update_system
    [[ ! " ${done_steps[@]} " =~ " install_packages " ]] && install_packages
    [[ ! " ${done_steps[@]} " =~ " install_zsh " ]] && install_zsh
    [[ ! " ${done_steps[@]} " =~ " apply_config " ]] && apply_config
    [[ ! " ${done_steps[@]} " =~ " set_theme_and_icons " ]] && set_theme_and_icons
    gum style --foreground 212 "✅ All steps completed!"
}

cleanup() {
    # nothing to clean up anymore, but leaving it here in case
    true
}


# Menu logic
check_dialog_installed
while true; do
    show_menu
done
