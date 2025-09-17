#!/usr/bin/env bash

gsettings set org.gnome.desktop.interface gtk-theme 'Colloid-Light'
gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
mkdir -p ~/.config/gtk-3.0 ~/.config/gtk-4.0
printf '[Settings]\ngtk-theme-name=Colloid-Light\ngtk-application-prefer-dark-theme=0\n' > ~/.config/gtk-3.0/settings.ini
printf '[Settings]\ngtk-theme-name=Colloid-Light\n' > ~/.config/gtk-4.0/settings.ini
nautilus -q