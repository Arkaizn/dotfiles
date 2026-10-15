#!/bin/bash
# shared helpers for install.sh / postinstall.sh and their step scripts
# usage: source "$(dirname "$0")/../lib.sh"   (or ./scripts/lib.sh from the repo root)

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

magenta=170
blue=26
red=196
green=34

title() { gum style --foreground "$magenta" --bold "$*"; }
info()  { gum style --foreground "$blue" "$*"; }
ok()    { gum style --foreground "$green" "✓ $*"; }
err()   { gum style --foreground "$red" "✗ $*"; }

# run "<spinner title>" cmd args...
# shows full output when VERBOSE=yes, otherwise a gum spinner
run() {
    local label=$1; shift
    if [[ "${VERBOSE:-no}" == yes ]]; then
        "$@"
    else
        gum spin --spinner dot --title "$label" -- "$@"
    fi
}

# keep the sudo timestamp fresh while the script runs (spinners can't prompt for a password)
keep_sudo_alive() {
    sudo -v || exit 1
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
}

# install yay if missing
ensure_yay() {
    command -v yay &>/dev/null && return 0

    info "yay not found, building it from the AUR..."
    run "Installing base-devel and git" sudo pacman -S --needed --noconfirm git base-devel || return 1

    local tmp
    tmp=$(mktemp -d)
    if git clone https://aur.archlinux.org/yay.git "$tmp/yay" && (cd "$tmp/yay" && makepkg -si --noconfirm); then
        ok "yay installed"
    else
        err "Failed to build yay, please install it manually."
        rm -rf "$tmp"
        return 1
    fi
    rm -rf "$tmp"
}

# yay_install pkg... : installs each package, asks to skip/abort on failure
yay_install() {
    local pkg
    for pkg in "$@"; do
        if run "Installing $pkg" yay -S --needed --noconfirm --noanswerclean --noansweredit "$pkg"; then
            ok "$pkg"
        else
            err "$pkg failed to install"
            [[ $(gum choose "Skip and continue" "Abort") == "Abort" ]] && return 1
        fi
    done
}
