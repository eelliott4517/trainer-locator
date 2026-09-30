"""Checks tools/test/atlases.txt against WoW: Forever's own atlas table (from wago.tools, for the
build in art.py): every name has to exist in the client, at the size listed.

    python3 tools/test/verify_atlases.py
"""
import os
import sys

import art

HERE = os.path.dirname(os.path.abspath(__file__))

bad = 0
for line in open(os.path.join(HERE, "atlases.txt")):
    if not line.strip() or line.startswith("#"):
        continue
    name, w, h = line.split()
    info = art.atlas_info(name)
    if not info:
        print("missing ", name)
        bad += 1
    elif (round(info["w"]), round(info["h"])) != (int(w), int(h)):
        print(f"size     {name}: the client has {info['w']:g} x {info['h']:g}, atlases.txt says {w} x {h}")
        bad += 1
print("all atlases check out" if not bad else f"{bad} problems", f"(client build {art.BUILD})")
sys.exit(1 if bad else 0)
