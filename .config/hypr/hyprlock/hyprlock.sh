#!/usr/bin/env bash

# Source the color environment variables so Hyprlock can use them
source ~/.cache/wal/hyprlock_colors

# set monitor
export monitor1="eDP-1"


# Run Hyprlock with the environment variables set
hyprlock &

wait $!
