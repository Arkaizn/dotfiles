#!/bin/bash
# System upgrade for services/Updates.qml (runs in a terminal).
#   1. repositories: sudo pacman -Syu (if that fails, nothing else runs)
#   2. AUR: every outdated package on its own, so one that fails to build
#      doesn't take the others down with it
#   3. the failed ones: try again by hand (interactive yay), or put them on
#      hold: skipped until a newer version than the failed one comes out.
# On-hold list: $XDG_STATE_HOME/quickshell/aur-held, lines "name version"
# (the settings app shows them and can release them).

held=${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/aur-held
mkdir -p "${held%/*}"
touch "$held"

c_title=$'\e[1;35m'; c_ok=$'\e[32m'; c_warn=$'\e[33m'; c_err=$'\e[31m'; c_off=$'\e[0m'
unhold() { awk -v n="$1" '$1 != n' "$held" > "$held.tmp" && mv "$held.tmp" "$held"; }
close() { echo; read -r -p "Press Enter to close." _; exit "${1:-0}"; }

echo "${c_title}==> Repositories${c_off}"
if ! sudo pacman -Syu --noconfirm; then
    echo "${c_err}pacman failed, the AUR packages were not touched.${c_off}"
    close 1
fi

command -v yay >/dev/null || close 0

mapfile -t outdated < <(yay -Qua 2>/dev/null)      # "name old -> new"
[ ${#outdated[@]} -eq 0 ] && { echo "${c_ok}No AUR updates.${c_off}"; close 0; }

failed=()
for line in "${outdated[@]}"; do
    read -r name old _ new <<<"$line"
    if awk -v n="$name" -v v="$new" '$1 == n && $2 == v { f = 1 } END { exit !f }' "$held"; then
        echo "${c_warn}==> $name $new is on hold (it failed before), skipped${c_off}"
        continue
    fi
    echo "${c_title}==> AUR: $name  $old -> $new${c_off}"
    if yay -S --noconfirm --answerclean None --answerdiff None -- "$name"; then
        unhold "$name"
    else
        failed+=("$name $new")
    fi
done

if [ ${#failed[@]} -eq 0 ]; then
    echo; echo "${c_ok}All AUR packages are up to date.${c_off}"
    close 0
fi

echo; echo "${c_err}These AUR packages failed to update:${c_off}"
printf '  %s\n' "${failed[@]}"
echo "Retry one by hand to see what's wrong (missing PGP key, build error, …),"
echo "or put it on hold: it's skipped until a newer version comes out."
for f in "${failed[@]}"; do
    name=${f%% *}; version=${f#* }
    echo
    read -r -p "Try ${name} again by hand now? [y/N] " a
    if [[ $a == [yY]* ]] && yay -S -- "$name"; then
        unhold "$name"
        echo "${c_ok}$name updated.${c_off}"
        continue
    fi
    unhold "$name"
    echo "$name $version" >> "$held"
    echo "${c_warn}$name is on hold until a version newer than $version comes out.${c_off}"
done
close 0
