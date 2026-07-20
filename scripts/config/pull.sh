#!/usr/bin/env bash

gum spin --title "Pulling dotfiles…" -- git -C "$HOME/git/dotfiles" pull --quiet

bash $HOME/git/dotfiles/scripts/config/update.sh # run here cause of changes that were made in the update script

