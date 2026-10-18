#!/usr/bin/env bash
# Does ~/.config differ from the repo? Same rules as push.sh (default profile),
# run as a dry run: lists what a push would change, exit 1 if anything.
set -euo pipefail

SOURCE_DIR="$HOME/.config"
TARGET_DIR="$HOME/git/dotfiles/.config"

# per-device files and junk: see sync-excludes.sh
# shellcheck source=sync-excludes.sh disable=SC1091  # path is only known at runtime
source "$(dirname "$(readlink -f "$0")")/sync-excludes.sh"

echo "Checking differences…"

args=(-a --delete --dry-run --itemize-changes --out-format='%i %n')
for e in "${DEVICE_FILES[@]}"; do args+=(--exclude="/$e"); done
for e in "${NEVER_PUSH[@]}"; do args+=(--exclude="$e"); done
args+=(--exclude="/hypr/wallpapers/pywallpaper.png" --exclude="/hypr/wallpapers/thumbs.db")

# only the top-level folders the repo has (like push.sh)
while IFS= read -r name; do
    args+=(--include="$name/" --include="$name/**")
done < <(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
args+=(--exclude="*")

# drop folder-only entries (".d..t…" = just a timestamp)
out=$(rsync "${args[@]}" "$SOURCE_DIR/" "$TARGET_DIR/" | grep -v '^\.d' || true)

if [ -z "$out" ]; then
    echo "✅ Up to date"
    exit 0
else
    echo "$out"
    echo "❌ Differences found"
    exit 1
fi
