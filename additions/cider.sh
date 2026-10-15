#!/usr/bin/env bash
set -euo pipefail

# 1) Define paths
APPIMAGE="/home/arkaizn/custom/apps/cider-linux-x64.AppImage"
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/cider.desktop"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
ICON_NAME="cider.png"

# 2) Make sure the AppImage is executable
chmod +x "$APPIMAGE"

# 3) Create icon directory
mkdir -p "$ICON_DIR"

# 4) Try to pull out its embedded PNG icon
#    (most AppImages respond to --appimage-extract-icon, otherwise skip)
if "$APPIMAGE" --appimage-extract-icon 2>/dev/null; then
  # this drops cider.png in cwd
  mv cider.png "$ICON_DIR/$ICON_NAME"
elif "$APPIMAGE" --appimage-extract 2>/dev/null; then
  # fallback: extract entire AppImage and grep for a .png
  mv squashfs-root/*/*.png "$ICON_DIR/$ICON_NAME" 2>/dev/null || true
  rm -rf squashfs-root
else
  echo "⚠️  Couldn’t extract an icon from the AppImage; you can manually add one under $ICON_DIR"
fi

# 5) Drop in the .desktop file
mkdir -p "$DESKTOP_DIR"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=Cider
Comment=Cider IDE
Exec=$APPIMAGE %U
Icon=cider
Type=Application
Terminal=false
Categories=Development;IDE;
EOF

# 6) Update the desktop database (optional)
if command -v update-desktop-database &>/dev/null; then
  update-desktop-database "$DESKTOP_DIR"
fi

echo "✅  Installed Cider desktop entry → $DESKTOP_FILE"
