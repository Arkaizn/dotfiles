#!/bin/bash

source "$(dirname "$0")/../../lib.sh"

here="$(dirname "$0")"

yay_install openrgb || exit 1

sudo install -m 644 "$here/openrgb.service" /etc/systemd/system/openrgb.service
sudo install -m 755 "$here/start-openrgb.sh" /root/start-openrgb.sh
sudo mkdir -p /root/.config/OpenRGB
sudo install -m 644 "$here/purple.orp" /root/.config/OpenRGB/purple.orp

sudo systemctl daemon-reload
sudo systemctl enable --now openrgb.service
