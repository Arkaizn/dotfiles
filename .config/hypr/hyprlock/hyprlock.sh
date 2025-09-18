#!/usr/bin/env bash

# Source the color environment variables so Hyprlock can use them
source ~/.cache/wal/hyprlock_colors

# set monitor
export monitor1="DP-2"


# Run Hyprlock with the environment variables set
hyprlock &

wait $!
