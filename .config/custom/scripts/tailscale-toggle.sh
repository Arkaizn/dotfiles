#!/usr/bin/env bash

if tailscale status 2>&1 | grep -q "Tailscale is stopped"; then
    tailscale up
    notify-send "Tailscale Up" "🔌 Tailscale is  now up."
else
    tailscale down
    notify-send "Tailscale Down" "❌ Tailscale is now down."
fi

