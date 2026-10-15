#!/bin/bash

source "$(dirname "$0")/../lib.sh"

ZSH_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}

yay_install zsh || exit 1

# change default shell to zsh
[[ "$SHELL" == *zsh ]] || sudo chsh -s "$(command -v zsh)" "$USER"

# oh my zsh
if [[ ! -d ~/.oh-my-zsh ]]; then
    run "Installing Oh My Zsh" env RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# plugins
for repo in zsh-users/zsh-autosuggestions zsh-users/zsh-syntax-highlighting; do
    dir="$ZSH_CUSTOM/plugins/${repo#*/}"
    [[ -d "$dir" ]] || run "Cloning ${repo#*/}" git clone -q "https://github.com/$repo" "$dir"
done
