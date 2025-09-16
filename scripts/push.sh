#!/bin/bash

copy_config() {
    local src="$1"
    local dest="$2"
    local name
    name=$(basename "$src")

    if [ -d "$src" ]; then
        mkdir -p "$dest/$name"
        cp -rf "$src/"* "$dest/$name/"
        echo "✔ copied $name"
    else
        echo "⚠ skipped $name, not found"
    fi
}

dotdir="$HOME/git/dotfiles/.config"

copy_config "$HOME/.config/hypr"     "$dotdir"
copy_config "$HOME/.config/wal"      "$dotdir"
copy_config "$HOME/.config/wofi"     "$dotdir"
copy_config "$HOME/.config/wlogout"  "$dotdir"
copy_config "$HOME/.config/waybar"   "$dotdir"
copy_config "$HOME/.config/kitty"    "$dotdir"
copy_config "$HOME/.config/swaync"   "$dotdir"
copy_config "$HOME/.config/fastfetch" "$dotdir"
copy_config "$HOME/.config/wayvnc"   "$dotdir"
copy_config "$HOME/.config/custom"   "$dotdir"
