#!/usr/bin/env bash
# Puts the login screen together: greeter/*.qml at the top, the shared files
# from manifest.txt below, qmldir files reduced to what's there.
#   greeter/build.sh <outdir>     (outdir is replaced)
# Used by greeter/install.sh and the nested tests (qsr greeter-build), so the
# tested tree is the installed one. Prints the tree's version (content hash).
set -euo pipefail
src=$(cd "$(dirname "$0")/.." && pwd)
out=${1:?usage: build.sh <outdir>}
[ "$out" != / ] || exit 1

rm -rf "$out"; mkdir -p "$out"
cp "$src"/greeter/*.qml "$out/"
grep -vE '^\s*(#|$)' "$src/greeter/manifest.txt" | while read -r f; do
    [ -f "$src/$f" ] || { echo "build.sh: missing $f" >&2; exit 1; }
    mkdir -p "$out/$(dirname "$f")"
    cp "$src/$f" "$out/$f"
done

# qmldir: keep the lines whose file was copied (and the module line)
for d in services components services/lib; do
    [ -f "$src/$d/qmldir" ] || continue
    awk -v dir="$out/$d" '
        /^module / { print; next }
        { f = $NF; if ((getline _ < (dir "/" f)) >= 0) print; close(dir "/" f) }' "$src/$d/qmldir" > "$out/$d/qmldir"
done

ver=$(cd "$out" && find . -type f ! -name VERSION -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-12)
echo "$ver" > "$out/VERSION"
echo "$ver"
