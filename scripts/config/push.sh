#!/usr/bin/env bash
set -euo pipefail
SOURCE_DIR="$HOME/.config"                         # where your live configs are
TARGET_DIR="$HOME/git/dotfiles/.config"             # where they get pushed to (repo)

# Files/dirs to leave alone when pushing (host-specific or repo-managed)
# Per-device files and junk (backups, caches, secrets): see sync-excludes.sh
# shellcheck source=sync-excludes.sh disable=SC1091  # path is only known at runtime
source "$(dirname "$(readlink -f "$0")")/sync-excludes.sh"

# profile: first argument (default | full), or ask (e.g. the quickshell settings app passes it)
profile=${1:-}
case "$profile" in
    default|full) ;;
    "") profile=$(gum choose "default" "full") ;;
    *) echo "usage: $0 [default|full]" >&2; exit 2 ;;
esac
echo "Profile: $profile"

rsync_args=(-av --delete)

# only protect files in "default" mode
if [[ "$profile" == "default" ]]; then
    # anchored ("/custom/" = only ~/.config/custom, not any folder called custom)
    for e in "${DEVICE_FILES[@]}"; do
        rsync_args+=(--exclude="/$e")
    done
fi
# junk / secrets / retired files: never, in either mode
for e in "${NEVER_PUSH[@]}"; do
    rsync_args+=(--exclude="$e")
done

# only sync top-level folders that already exist in TARGET_DIR
while IFS= read -r name; do
    rsync_args+=(--include="$name/" --include="$name/**")
done < <(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
rsync_args+=(--exclude="*")

gum spin --title "Pushing Config …" -- rsync "${rsync_args[@]}" "$SOURCE_DIR/" "$TARGET_DIR/"

gum spin --title "Pushing .zshrc" -- rsync "$HOME/.zshrc" "$HOME/git/dotfiles/.config/"

echo "Push done ✅"