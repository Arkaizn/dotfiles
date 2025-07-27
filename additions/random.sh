#!/bin/bash

# intsall xbox controller drivers 
yay -S xpadneo-dkms
yay -S openlinkhub

# tailscale
yay -S tailscale
sudo systemctl enable --now tailscaled.service
sudo tailscale set --operator=$USER 
sudo tailscale login
tailscale set --accept-dns=false 
tailscale status

# nordvpn
sudo groupadd nordvpn
sudo usermod -aG nordvpn $USER
sudo systemctl enable --now nordvpnd.service
nordvpn login
nordvpn login --callback "continue Button URL from Nordvpn"


# disk utiity
sudo pacman -S baobab
sudo pacman -S gnome-disk-utility

# thunar smb share packages
sudo pacman -Syu gvfs gvfs-smb cifs-utils thunar-volman gigolo

# gnome wireless display
yay -S gnome-network-displays 


# install openvpn cli
yay -S openvpn
# connect to connection
openvpn --config ssl.ovpn


# network tools
yay -S bind-tools net-tools nmap arp-scan

yay -S btop

