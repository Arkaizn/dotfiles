#!/bin/bash

# Check if OpenRGB is running
if ! pgrep -x "openrgb" > /dev/null
then
    sudo openrgb --startminimized --profile /root/.config/OpenRGB/purple.orp
else
    sudo systemctl stop openrgb.service
fi
