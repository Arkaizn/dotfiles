#!/usr/bin/env bash

# Color definitions
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
RED="\033[0;31m"
NC="\033[0m" # No Color

# Track completed steps
declare -a done_steps=()

is_done() {
    [[ " ${done_steps[*]} " =~ " $1 " ]]
}

mark_done() {
    done_steps+=("$1")
}

install_openrgb() {
    echo -e "${YELLOW}Installing OpenRGB…${NC}"
    bash ./additions/openrgb/openrgb.sh && mark_done openrgb
}

install_apps() {
    echo -e "${YELLOW}Installing recommended apps…${NC}"
    bash ./additions/apps.sh && mark_done apps
}

install_zsh() {
    echo -e "${YELLOW}Installing & configuring Zsh…${NC}"
    bash ./scripts/zshinstall.sh && mark_done zsh
}

install_nvidia() {
    echo -e "${YELLOW}Installing Nvidia drivers…${NC}"
    bash ./additions/nvidia-dkms.sh && mark_done nvidia
}

setup_greetd() {
    echo -e "${YELLOW}Setting up greetd autologin…${NC}"
    sudo systemctl enable greetd.service
    sudo systemctl disable getty@tty1.service

    sudo tee /etc/greetd/config.toml > /dev/null <<EOF
[terminal]
vt = 1

[initial_session]
command = "Hyprland"
user = "arkaizn"

[default_session]
command = "Hyprland"
user = "arkaizn"
EOF

    echo -e "${GREEN}greetd autologin configured.${NC}"
    mark_done greetd
}

do_everything() {
    install_openrgb    || true
    install_apps       || true
    install_zsh        || true
    install_nvidia     || true
    setup_greetd       || true
}

show_menu() {
    local menu=(
        "1) Do everything"
        "2) Install OpenRGB"
        "3) Install other apps"
        "4) Install & configure Zsh"
        "5) Install Nvidia drivers"
        "6) Setup greetd autologin"
        "7) Exit"
    )

    # append a checkmark to done items
    for i in "${!menu[@]}"; do
        case "${menu[$i]}" in
            *OpenRGB*)
                if is_done openrgb; then
                    menu[$i]="${menu[$i]} ✓"
                fi
                ;;
            *apps*)
                if is_done apps; then
                    menu[$i]="${menu[$i]} ✓"
                fi
                ;;
            *Zsh*)
                if is_done zsh; then
                    menu[$i]="${menu[$i]} ✓"
                fi
                ;;
            *Nvidia*)
                if is_done nvidia; then
                    menu[$i]="${menu[$i]} ✓"
                fi
                ;;
            *greetd*)
                if is_done greetd; then
                    menu[$i]="${menu[$i]} ✓"
                fi
                ;;
        esac
    done

        choice=$(printf '%s\n' "${menu[@]}" \
       | wofi --drun -n--dmenu \
              --width 600 \
              --height 80% \
              --lines 10 \
              --prompt "Extras:" \
       2>/dev/null \
       | cut -d')' -f1 | tr -d ' ')

    # Exit on ESC or empty
    if [[ -z "$choice" ]]; then
        exit 0
    fi

    case "$choice" in
        1) do_everything    ;; 
        2) is_done openrgb  || install_openrgb ;; 
        3) is_done apps     || install_apps    ;; 
        4) is_done zsh      || install_zsh     ;; 
        5) is_done nvidia   || install_nvidia  ;; 
        6) is_done greetd   || setup_greetd    ;; 
        7) echo -e "${GREEN}Done.${NC}"; exit 0 ;; 
        *) echo -e "${RED}Invalid choice.${NC}" ;; 
    esac
}

# main loop
while true; do
    show_menu
done
