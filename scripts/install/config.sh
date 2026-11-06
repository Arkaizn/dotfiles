#!/bin/bash

source "$(dirname "$0")/../lib.sh"

# copy configs (including dotfiles like .zshrc) to ~/.config
mkdir -p ~/.config
cp -rf "$DOTFILES_DIR/.config/." ~/.config/
cp -f "$DOTFILES_DIR/.config/.zshrc" ~/.zshrc

# link launcher entries into ~/.local/share/applications
"$DOTFILES_DIR/scripts/config/desktop-entries.sh"

# Files (the Quickshell file manager) opens folders; the marker tells update.sh it's done
# (changeable later in Settings → Default apps)
xdg-mime default quickshell-files.desktop inode/directory \
    && mkdir -p ~/.local/state/quickshell && touch ~/.local/state/quickshell/files-default-set
