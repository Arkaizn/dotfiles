#!/usr/bin/env bash
# Link launcher entries shipped with the dotfiles into ~/.local/share/applications,
# the folder every launcher reads. Any config folder can ship entries by putting
# them in ~/.config/<app>/applications/*.desktop.
# Symlinks point at ~/.config, so edits (and update.sh syncs) apply right away.
# Only creates links that are missing or wrong, so it's safe to run every update.
set -euo pipefail
shopt -s nullglob

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
DEST_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "$DEST_DIR"

linked=0
for src in "$CONFIG_DIR"/*/applications/*.desktop; do
    link="$DEST_DIR/$(basename "$src")"

    # already linked to the right file: nothing to do
    [[ -L "$link" && "$(readlink "$link")" == "$src" ]] && continue

    # a real file with the same name was put there by something else: leave it
    if [[ -e "$link" && ! -L "$link" ]]; then
        echo "skipped $(basename "$src") (a real file already exists at $link)"
        continue
    fi

    ln -sfn "$src" "$link"
    echo "linked $(basename "$src")"
    linked=$((linked + 1))
done

# drop dangling links into ~/.config (entry was removed from the dotfiles)
for link in "$DEST_DIR"/*.desktop; do
    if [[ -L "$link" && ! -e "$link" && "$(readlink "$link")" == "$CONFIG_DIR"/* ]]; then
        rm "$link"
        echo "removed stale $(basename "$link")"
    fi
done

echo "Desktop entries: $linked new link(s)"
