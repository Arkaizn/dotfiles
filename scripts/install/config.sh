#!/bin/bash

source "$(dirname "$0")/../lib.sh"

# copy configs (including dotfiles like .zshrc) to ~/.config
mkdir -p ~/.config
cp -rf "$DOTFILES_DIR/.config/." ~/.config/
cp -f "$DOTFILES_DIR/.config/.zshrc" ~/.zshrc

# link launcher entries into ~/.local/share/applications
"$DOTFILES_DIR/scripts/config/desktop-entries.sh"
