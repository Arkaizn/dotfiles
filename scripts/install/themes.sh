#!/bin/bash

source "$(dirname "$0")/../lib.sh"

mkdir -p ~/.icons ~/.themes

# download + extract into a temp dir so nothing is left in the repo
install_cursor() {
    cd "$(mktemp -d)" || return 1
    curl -sL https://github.com/ful1e5/Bibata_Cursor/releases/download/v2.0.7/Bibata-Modern-Ice.tar.xz | tar -xJ
    cp -r Bibata-Modern-Ice ~/.icons/
    gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Ice'
}

install_icons() {
    cd "$(mktemp -d)" || return 1
    curl -sL https://github.com/vinceliuice/Fluent-icon-theme/archive/refs/tags/2025-08-21.tar.gz | tar -xz
    bash Fluent-icon-theme-2025-08-21/install.sh
    gsettings set org.gnome.desktop.interface icon-theme 'Fluent-dark'
}

install_widgets_gtk() {
    cd "$(mktemp -d)" || return 1
    curl -sL https://github.com/vinceliuice/Colloid-gtk-theme/archive/refs/tags/2025-07-31.tar.gz | tar -xz
    bash Colloid-gtk-theme-2025-07-31/install.sh
    gsettings set org.gnome.desktop.interface gtk-theme 'Colloid-Dark'
    pkill nautilus
}

install_widgets_qt() {
    cd "$(mktemp -d)" || return 1
    curl -sL https://github.com/vinceliuice/Fluent-kde/archive/refs/tags/2021-11-04.tar.gz | tar -xz
    bash Fluent-kde-2021-11-04/install.sh
    kvantummanager --set Fluent-roundDark
}

# step "<title>" function : runs the function in a subshell (so gum spin can call it)
step() {
    run "Installing $1" bash -c "$(declare -f "$2"); $2" && ok "$1 installed" || err "$1 failed"
}

step "Cursor" install_cursor
step "Icons" install_icons
step "GTK theme" install_widgets_gtk
step "Qt/KDE theme" install_widgets_qt
