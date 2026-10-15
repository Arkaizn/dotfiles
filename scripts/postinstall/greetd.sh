#!/bin/bash

source "$(dirname "$0")/../lib.sh"

session=$(gum choose --header "Which session should greetd autologin into?" "Hyprland" "Niri") || exit 1
case "$session" in
    Hyprland) cmd="start-hyprland" ;;
    Niri)     cmd="niri-session" ;;
esac

yay_install greetd || exit 1

sudo tee /etc/greetd/config.toml > /dev/null <<CONF
[terminal]
vt = 1

[initial_session]
command = "$cmd"
user = "$USER"

[default_session]
command = "$cmd"
user = "$USER"
CONF

sudo systemctl enable greetd.service
sudo systemctl disable getty@tty1.service
ok "greetd autologin configured ($session)"
