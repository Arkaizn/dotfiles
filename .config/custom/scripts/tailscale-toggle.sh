#!/usr/bin/env bash

if tailscale status 2>&1 | grep -q "Tailscale is stopped"; then
    echo "Tailscale is down → bringing it up..."
    tailscale up
else
    echo "Tailscale is up → bringing it down..."
    tailscale down
fi
