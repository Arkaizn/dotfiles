#!/bin/bash
# Remove packages for the settings app's Packages page (runs in a terminal):
#   remove-packages.sh <package>...
# Packages that other installed packages still need are skipped (pacman would
# refuse the whole removal otherwise): a dry run (-Rs --print) names them,
# they're dropped, and that repeats until the rest can go. Then
# sudo pacman -Rns shows everything that goes and asks before removing.

c_warn=$'\e[33m'; c_ok=$'\e[32m'; c_off=$'\e[0m'
pk=("$@")
skipped=()

for _ in $(seq 1 20); do
    [ ${#pk[@]} -eq 0 ] && break
    err=$(LC_ALL=C pacman -Rs --print -- "${pk[@]}" 2>&1 >/dev/null) && break
    # ":: removing X breaks dependency 'X' required by Y"
    mapfile -t bad < <(printf '%s\n' "$err" | sed -n "s/^:: removing \([^ ]*\) breaks dependency .* required by \(.*\)$/\1 (needed by \2)/p" | sort -u)
    [ ${#bad[@]} -eq 0 ] && break
    for b in "${bad[@]}"; do
        name=${b%% *}
        skipped+=("$b")
        for i in "${!pk[@]}"; do [ "${pk[$i]}" = "$name" ] && unset 'pk[i]'; done
    done
    pk=("${pk[@]}")
done

if [ ${#skipped[@]} -gt 0 ]; then
    echo "${c_warn}Skipped, still needed by other packages:${c_off}"
    printf '%s\n' "${skipped[@]}" | sort -u | sed 's/^/  /'
    echo
fi

if [ ${#pk[@]} -eq 0 ]; then
    echo "Nothing left to remove."
else
    sudo pacman -Rns -- "${pk[@]}" && echo "${c_ok}Removed.${c_off}"
fi
echo
read -r -p "Done. Press Enter to close (then Reload in the settings app)." _
