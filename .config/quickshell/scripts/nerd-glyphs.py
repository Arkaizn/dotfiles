#!/usr/bin/env python3
# Every icon glyph of a font, for the settings app's icon picker (Shell → Icons):
#   nerd-glyphs.py "<font family>"
# Prints "<hex code point><TAB><name>" (e.g. "f08c7	md-arch") for the private
# use area (where Nerd Fonts put their icons). The names come from the font
# itself. Needs fontTools (python-fonttools).
import subprocess
import sys

from fontTools.ttLib import TTFont

family = sys.argv[1] if len(sys.argv) > 1 else "Symbols Nerd Font"
path = subprocess.run(["fc-match", "-f", "%{file}", family], capture_output=True, text=True).stdout.strip()
if not path:
    sys.exit("no font file for " + family)

cmap = TTFont(path, lazy=True, fontNumber=0).getBestCmap()
out = sys.stdout
for cp in sorted(cmap):
    if cp >= 0xE000:
        out.write(f"{cp:x}\t{cmap[cp]}\n")
