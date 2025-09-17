#!/usr/bin/env bash
gsettings set org.gnome.desktop.interface gtk-theme 'Colloid-Dark' \
&& gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' \
&& mkdir -p ~/.config/gtk-3.0 ~/.config/gtk-4.0 \
&& printf '[Settings]\ngtk-theme-name=Colloid-Dark\ngtk-application-prefer-dark-theme=1\n' > ~/.config/gtk-3.0/settings.ini \
&& printf '[Settings]\ngtk-theme-name=Colloid-Dark\n' > ~/.config/gtk-4.0/settings.ini
nautilus -q
