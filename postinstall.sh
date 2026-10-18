#!/usr/bin/env bash

cd "$(dirname "$0")" || exit 1

if ! command -v gum &>/dev/null; then
    echo "Installing gum..."
    sudo pacman -Sy --needed --noconfirm gum || exit 1
fi

source ./scripts/lib.sh

# menu label -> step script (in scripts/postinstall/)
declare -A steps=(
    ["Install apps"]="apps.sh"
    ["Install & configure Zsh"]="zsh.sh"
    ["Install Nvidia drivers"]="nvidia.sh"
    ["Install OpenRGB"]="openrgb/openrgb.sh"
    ["Setup greetd autologin"]="greetd.sh"
    ["Setup YubiKey login"]="yubikey.sh"
)
order=("Install apps" "Install & configure Zsh" "Install Nvidia drivers" "Install OpenRGB" "Setup greetd autologin" "Setup YubiKey login")

# track completed steps
declare -A done_steps=()

run_step() {
    title "▶ $1"
    if bash "./scripts/postinstall/${steps[$1]}"; then
        done_steps[$1]=1
        ok "$1"
    else
        err "$1 failed"
    fi
}

show_menu() {
    local items=("Pick multiple") label
    for label in "${order[@]}"; do
        [[ -n "${done_steps[$label]}" ]] && items+=("$label ✓") || items+=("$label")
    done
    items+=("Exit")

    local choice
    choice=$(gum choose --header "Post-install extras" "${items[@]}") || exit 0
    choice=${choice% ✓}

    case "$choice" in
        "Pick multiple")
            local picked
            picked=$(gum choose --no-limit --header "Select steps (space to toggle, enter to run)" "${order[@]}")
            while IFS= read -r label; do
                [[ -n "$label" ]] && run_step "$label"
            done <<< "$picked"
            ;;
        ""|"Exit") ok "Done."; exit 0 ;;
        *) run_step "$choice" ;;
    esac
}

keep_sudo_alive

while true; do
    show_menu
done
