#!/bin/bash

SILENT=$1
magenta=170
blue=26
red=196
green=34

mkdir -p ~/.icons/ > /dev/null 2>&1
mkdir -p ~/.themes > /dev/null 2>&1

install_cursor() {
    curl -L -o Bibata-Modern-Ice.tar.xz https://github.com/ful1e5/Bibata_Cursor/releases/download/v2.0.7/Bibata-Modern-Ice.tar.xz
    7z x Bibata-Modern-Ice.tar.xz
    7z x Bibata-Modern-Ice.tar
    mkdir -p ~/.icons/
    cp -r Bibata-Modern-Ice ~/.icons/Bibata-Modern-Ice 
    rm -fr Bibata-Modern-Ice.tar.xz Bibata-Modern-Ice.tar Bibata-Modern-Ice
    gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Ice'
}

install_icons() {
    curl -L -o Fluent-icon-theme.tar.gz https://github.com/vinceliuice/Fluent-icon-theme/archive/refs/tags/2025-08-21.tar.gz
    7z x Fluent-icon-theme.tar.gz
    tar -xvf Fluent-icon-theme.tar
    mkdir -p ~/.icons/
    bash Fluent-icon-theme-2025-08-21/install.sh
    rm -fr Fluent-icon-theme.tar.gz Fluent-icon-theme.tar Fluent-icon-theme-2025-08-21
    gsettings set org.gnome.desktop.interface icon-theme 'Fluent-dark'
}

install_widgets_gtk() {
    curl -L -o 2025-07-31.tar.gz https://github.com/vinceliuice/Colloid-gtk-theme/archive/refs/tags/2025-07-31.tar.gz
    7z x 2025-07-31.tar.gz
    7z x 2025-07-31.tar
    mkdir -p ~/.icons/
    bash Colloid-gtk-theme-2025-07-31/install.sh
    rm -fr 2025-07-31.tar.gz 2025-07-31.tar Colloid-gtk-theme-2025-07-31
    gsettings set org.gnome.desktop.interface gtk-theme 'Colloid-Dark'
    pkill nauilus
}

install_widgets_qt() {
    curl -L -o Fluent-kde.tar.gz https://github.com/vinceliuice/Fluent-kde/archive/refs/tags/2021-11-04.tar.gz
    7z x Fluent-kde.tar.gz
    7z x Fluent-kde.tar
    mkdir -p ~/.icons/
    bash Fluent-kde-2021-11-04/install.sh
    rm -fr Fluent-kde.tar.gz Fluent-kde.tar Fluent-kde-2021-11-04
    kvantummanager --set Fluent-roundDark
}


if [[ $SILENT == "--silent" ]]; then
    gum spin --spinner dot --title "Installing Cursor" -- bash -c "$(declare -f install_cursor); install_cursor"
    gum style --foreground $green "Cursor successfully installed"
else
    install_cursor
fi

if [[ $SILENT == "--silent" ]]; then
    gum spin --spinner dot --title "Installing Icons" -- bash -c "$(declare -f install_icons); install_icons"
    gum style --foreground $green "icons successfully installed"
else
    install_icons
fi

if [[ $SILENT == "--silent" ]]; then
    gum spin --spinner dot --title "Installing GTK Theme" -- bash -c "$(declare -f install_widgets_gtk); install_widgets_gtk"
    gum style --foreground $green "Widget theme successfully installed"
else
    install_widgets_gtk
fi

if [[ $SILENT == "--silent" ]]; then
    gum spin --spinner dot --title "Installing QT/KDE Theme" -- bash -c "$(declare -f install_widgets_qt); install_widgets_qt"
    gum style --foreground $green "Widget theme successfully installed"
else
    install_widgets_qt
fi