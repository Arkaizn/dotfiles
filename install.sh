#!/bin/bash

cd "$(dirname "$0")" || exit 1

# install dependency gum (needed before anything else)
if ! command -v gum &>/dev/null; then
    echo "Installing gum..."
    sudo pacman -Sy --needed --noconfirm gum || exit 1
fi

source ./scripts/lib.sh

# Function: show menu with gum
menu() {
    MENUCHOICE=$(gum choose --header "Dotfiles installer" \
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
        "Apply configuration files") apply_config ;;
        "Set theme and icons") set_theme_and_icons ;;
        *) exit 0 ;;
    esac
}

output() {
    if gum confirm "Do you want to have full output during installation?" --default=false; then
        export VERBOSE=yes
    else
        export VERBOSE=no
    fi
}

# System update
update_system() {
    title "🔄 Updating system..."
    run "Updating system" sudo pacman -Syu --noconfirm && ok "System updated"
}

# Install necessary packages
install_packages() {
    title "📦 Installing essential packages..."
    bash ./scripts/install/packages.sh
}

# Apply configuration files
apply_config() {
    title "⚙️ Applying configuration files..."
    run "Copying config" bash ./scripts/install/config.sh && ok "Config applied"
}

# Set theme and icons
set_theme_and_icons() {
    title "🎨 Setting themes and icons..."
    bash ./scripts/install/themes.sh
}

# Run all steps
run_all_steps() {
    update_system &&
    install_packages &&
    apply_config &&
    set_theme_and_icons &&
    gum style --foreground "$green" --bold "✅ All steps completed! Run ./postinstall.sh for the extras."
}

keep_sudo_alive
output

while true; do
    menu
done
