"""WoW: Forever's own UI art and font, for preview.py. Everything is fetched from wago.tools for the
client build below and cached in tools/test/.art (gitignored), so only the first preview needs the
network.

    atlas(name)  -> (RGBA image, width, height) for an atlas as the game draws it: its Camelot
                    ("-c60") art where there is one, the 2x art where there is one
    slices(name) -> (left, top, right, bottom, tiled) margins the game keeps unstretched, or None
    file(path)   -> RGBA image for a texture path such as Interface\\Icons\\Achievement_Reputation_01
    font()       -> path of Friz Quadrata, the game's font
"""
import csv
import io
import json
import os
import struct
import urllib.parse
import urllib.request

from PIL import Image

BUILD = "1.60.1.70009"
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".art")
TABLES = ("UiTextureAtlas", "UiTextureAtlasMember", "UiTextureAtlasElement", "UiTextureAtlasElementSliceData")


def _get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "rep-planner-preview"})
    with urllib.request.urlopen(req, timeout=90) as r:
        return r.read()


def _cached(name, url):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        data = _get(url)
        with open(path, "wb") as f:
            f.write(data)
    return path


# ------------------------------------------------------------------ textures
def decode_blp(data):
    """BLP2: Pillow reads the palette and DXT kinds; the plain BGRA kind (encoding 3) is read here."""
    assert data[:4] == b"BLP2", "not a BLP2 file"
    encoding = data[8]
    w, h = struct.unpack_from("<II", data, 12)
    offsets = struct.unpack_from("<16I", data, 20)
    sizes = struct.unpack_from("<16I", data, 84)
    if encoding == 3:
        raw = data[offsets[0]:offsets[0] + sizes[0]]
        return Image.frombuffer("RGBA", (w, h), raw, "raw", "BGRA", 0, 1).copy()
    return Image.open(io.BytesIO(data)).convert("RGBA")


_images = {}


def by_fdid(fdid):
    if fdid not in _images:
        png = os.path.join(CACHE, f"{fdid}.png")
        if os.path.exists(png):
            _images[fdid] = Image.open(png).convert("RGBA")
        else:
            blp = _cached(f"{fdid}.blp", f"https://wago.tools/api/casc/{fdid}?version={BUILD}")
            img = decode_blp(open(blp, "rb").read())
            img.save(png)
            os.remove(blp)
            _images[fdid] = img
    return _images[fdid]


_paths = None


def fdid_of(path):
    global _paths
    index = os.path.join(CACHE, "paths.json")
    if _paths is None:
        _paths = json.load(open(index)) if os.path.exists(index) else {}
    key = path.replace("\\", "/").lower()
    if "." not in key.rsplit("/", 1)[-1]:
        key += ".blp"
    if key not in _paths:
        found = json.loads(_get(f"https://wago.tools/api/files?search={urllib.parse.quote(key)}&version={BUILD}") or b"{}")
        _paths[key] = next((int(k) for k, v in (found.items() if isinstance(found, dict) else []) if v.lower() == key), None)
        os.makedirs(CACHE, exist_ok=True)
        json.dump(_paths, open(index, "w"), indent=0)
    return _paths[key]


def file(path):
    fdid = fdid_of(path)
    return by_fdid(fdid) if fdid else None


def font():
    return _cached("FRIZQT__.TTF", f"https://wago.tools/api/casc/{fdid_of('Fonts/FRIZQT__.TTF')}?version={BUILD}")


# ------------------------------------------------------------------ atlases
_tables = None


def _load_tables():
    global _tables
    if _tables is None:
        paths = {t: _cached(t + ".csv", f"https://wago.tools/db2/{t}/csv?build={BUILD}") for t in TABLES}
        atlases = {r["ID"]: r for r in csv.DictReader(open(paths["UiTextureAtlas"]))}
        elements = {r["Name"].lower(): r["ID"] for r in csv.DictReader(open(paths["UiTextureAtlasElement"]))}
        members = {}
        for r in csv.DictReader(open(paths["UiTextureAtlasMember"])):
            members.setdefault(r["UiTextureAtlasElementID"], []).append(r)
        slices = {r["UiTextureAtlasElementID"]: r for r in csv.DictReader(open(paths["UiTextureAtlasElementSliceData"]))}
        _tables = (atlases, elements, members, slices)
    return _tables


def slices(name):
    """Stretched atlases the client draws sliced: the margins stay their size, the rest stretches
    (or tiles, for slice mode 1). Margins are in UI units."""
    _, elements, _, table = _load_tables()
    r = table.get(elements.get(name.lower()))
    if not r:
        return None
    return int(r["Left"]), int(r["Top"]), int(r["Right"]), int(r["Bottom"]), r["SliceMode"] == "1"


def atlas_info(name):
    atlases, elements, members, _ = _load_tables()
    options = members.get(elements.get(name.lower()), [])
    if not options:
        return None
    # the Camelot art when there is one, then the sharper 2x art
    best = max(options, key=lambda m: ("-c60" in m["CommittedName"].lower(), "-2x" in m["CommittedName"].lower()))
    two = "-2x" in best["CommittedName"].lower()
    w, h = int(best["Width"]), int(best["Height"])
    return dict(member=best["CommittedName"], atlas=atlases[best["UiTextureAtlasID"]],
                box=(int(best["CommittedLeft"]), int(best["CommittedTop"]), int(best["CommittedRight"]), int(best["CommittedBottom"])),
                w=int(best["OverrideWidth"]) or (w / 2 if two else w), h=int(best["OverrideHeight"]) or (h / 2 if two else h))


_crops = {}


def atlas(name):
    if name not in _crops:
        info = atlas_info(name)
        if not info:
            _crops[name] = None
        else:
            img = by_fdid(int(info["atlas"]["FileDataID"]))
            sx, sy = img.width / int(info["atlas"]["AtlasWidth"]), img.height / int(info["atlas"]["AtlasHeight"])
            l, t, r, b = info["box"]
            _crops[name] = (img.crop((round(l * sx), round(t * sy), round(r * sx), round(b * sy))), info["w"], info["h"])
    return _crops[name]
