#!/usr/bin/env bash
# Link the launcher entries in ../applications into ~/.local/share/applications,
# so launchers (ours included) list them. They're symlinks, so editing the
# files here updates them right away. Safe to run again (e.g. after cloning).
set -euo pipefail

src="$(cd "$(dirname "$0")/../applications" && pwd)"
dest="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "$dest"

for f in "$src"/*.desktop; do
    ln -sfn "$f" "$dest/$(basename "$f")"
    echo "linked $(basename "$f")"
done
