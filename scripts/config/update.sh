#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$HOME/git/dotfiles/.config"
TARGET_DIR="$HOME/.config"

# ── Precious files ────────────────────────────────────────────────────────────
# These are NEVER overwritten by rsync; copied only if missing at the end.
PRECIOUS=(
    "hypr/wallpapers/pywallpaper.png"
    "hypr/wallpapers/thumbs.db"
    "kitty/current-theme.conf"
    "quickshell/services/Colors.qml"
    "niri/config/layout.kdl"
)

# ── Profile excludes (on top of precious + custom/) ───────────────────────────
declare -A PROFILE_EXCLUDES=(
    [full]=""
    [full-lite]="hypr/hyprland/monitors.lua hypr/hyprlock/hyprlock.sh niri/config/outputs.kdl"
    [standard]="hypr/"
)

# ─────────────────────────────────────────────────────────────────────────────

echo "Pulling dotfiles…"

cd $HOME/git/dotfiles && git pull --quiet
echo "Done."

profile=$(gum choose "full-lite" "standard" "full")
echo "Profile: $profile"

# Build rsync exclude args
excludes=(--exclude="custom/")
for p in "${PRECIOUS[@]}";          do excludes+=(--exclude="$p"); done
for p in ${PROFILE_EXCLUDES[$profile]}; do excludes+=(--exclude="$p"); done

# ── Main sync ─────────────────────────────────────────────────────────────────
echo "Syncing… (precious files + custom/ are protected)"
rsync -av "${excludes[@]}" "$SOURCE_DIR/" "$TARGET_DIR/"

# ── custom/: copy only missing files, never overwrite ─────────────────────────
if [[ -d "$SOURCE_DIR/custom" ]]; then
    echo "Checking custom/ for missing files…"
    while IFS= read -r -d '' src; do
        rel="${src#"$SOURCE_DIR/"}"
        dst="$TARGET_DIR/$rel"
        if [[ ! -f "$dst" ]]; then
            mkdir -p "$(dirname "$dst")"
            cp "$src" "$dst"
            echo "  + $rel"
        else
            echo "  ~ kept: $rel"
        fi
    done < <(find "$SOURCE_DIR/custom" -type f -print0)
fi

# ── Precious files: copy only if missing ──────────────────────────────────────
echo "Checking precious files…"
for rel in "${PRECIOUS[@]}"; do
    src="$SOURCE_DIR/$rel"
    dst="$TARGET_DIR/$rel"
    [[ -f "$src" ]] || continue          # not in source → skip
    if [[ ! -f "$dst" ]]; then
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        echo "  + $rel"
    else
        echo "  ~ kept: $rel"
    fi
done

# ── Reload ────────────────────────────────────────────────────────────────────
echo "Reloading…"
hyprctl reload || true
pkill qs      && hyprctl dispatch "hl.dsp.exec_cmd('QS_NO_RELOAD_POPUP=1 qs')" || true

echo "Done ✅"