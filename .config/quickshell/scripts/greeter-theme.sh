#!/usr/bin/env bash
# Copies what the login screen (greeter/) needs into its theme folder, which
# the `greeter` user can read (services/GreeterSync.qml runs this when the
# colors, wallpaper or the settings it shows change):
#   greeter-theme.sh DEST WALLPAPER FACE|- COLORS WxH  < bundle.json
# bundle.json: { settings: {…}, meta: {…}, outputs: "<text>", input: "<text>" }
# Writes settings.json, meta.json, outputs.txt, input.txt, colors.json,
# wallpaper.jpg (scaled to WxH, the largest monitor), face.png (or removes it).
# Each file only when it changed, through a temp file + mv (the greeter never
# reads half a file), mode 640 (DEST is setgid group greeter: see install.sh).
set -euo pipefail
dest=$1 wall=$2 face=$3 colors=$4 size=$5
[ -d "$dest" ] && [ -w "$dest" ] || { echo "not installed: $dest isn't writable" >&2; exit 3; }
[[ $size =~ ^[0-9]{3,5}x[0-9]{3,5}$ ]] || size=3840x2160
umask 027
in=$(cat)

# put NAME: stdin → DEST/NAME if different
put() {
    local tmp; tmp=$(mktemp "$dest/.$1.XXXXXX")
    cat > "$tmp"
    if [ -f "$dest/$1" ] && cmp -s "$tmp" "$dest/$1"; then rm -f "$tmp"; return; fi
    chmod 640 "$tmp"; mv -f "$tmp" "$dest/$1"; echo "updated $1"
}

jq '.settings' <<<"$in" | put settings.json
jq '.meta' <<<"$in" | put meta.json
jq -r '.outputs' <<<"$in" | put outputs.txt
jq -r '.input' <<<"$in" | put input.txt
[ -f "$colors" ] && put colors.json < "$colors"

# images: only redone when the source or the size changed (signature file)
image() {   # NAME SOURCE MAGICK-ARGS…
    local name=$1 src=$2; shift 2
    local sig; sig="$(stat -c '%s %Y' "$src") $*"
    [ -f "$dest/$name" ] && [ "$(cat "$dest/.$name.sig" 2>/dev/null)" = "$sig" ] && return
    local tmp; tmp=$(mktemp "$dest/.$name.XXXXXX")
    magick "$src" "$@" "${name##*.}:$tmp"
    chmod 640 "$tmp"; mv -f "$tmp" "$dest/$name"
    printf '%s' "$sig" | put ".$name.sig" >/dev/null
    echo "updated $name"
}
[ -f "$wall" ] && image wallpaper.jpg "$wall" -resize "${size}^" -quality 90
if [ "$face" != - ] && [ -f "$face" ]; then
    image face.png "$face" -resize 192x192^ -gravity center -extent 192x192
else
    rm -f "$dest/face.png" "$dest/.face.png.sig"
fi
echo ok
