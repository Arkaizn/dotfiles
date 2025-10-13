#!/usr/bin/env bash

# If Tailscale is running, print a placeholder (so Waybar renders the icon)
if tailscale status 2>&1 | grep -vq "Tailscale is stopped"; then
    echo " "  # anything non-empty will show the icon
else
    echo ""   # empty output hides it
fi

