"""Draws a world map the way WoW: Forever shows it (its own map art, from wago.tools) with the pins
Trainer Locator puts on it, so the spots in Data.lua can be checked against the buildings they
should be in.

    /tmp/wowlua/bin/python tools/test/mapview.py <uiMapID> [selection] [out.png] [--names]

selection is what the window would have picked: class:MAGE (the default), prof:197, weapon, all...
"""
import csv
import os
import sys

import lupa.lua51 as lua51
from PIL import Image, ImageDraw, ImageFont

import art

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB2 = os.path.join(TOOLS, "data", "db2")
NAMES = "--names" in sys.argv   # label each pin, for checking spots by hand; the game shows icons only
sys.argv = [a for a in sys.argv if a != "--names"]
MAP = int(sys.argv[1]) if len(sys.argv) > 1 else 1453
SEL = sys.argv[2] if len(sys.argv) > 2 else "class:MAGE"
OUT = sys.argv[3] if len(sys.argv) > 3 else os.path.join(TOOLS, f"map-{MAP}.png")
PIN = 22


def rows(name):
    with open(os.path.join(DB2, name + ".csv"), newline="") as f:
        return list(csv.DictReader(f))


def map_art(ui_map):
    art_id = next(r["UiMapArtID"] for r in rows("UiMapXMapArt") if int(r["UiMapID"]) == ui_map)
    style = next(r["UiMapArtStyleID"] for r in rows("UiMapArt") if r["ID"] == art_id)
    layer = next(r for r in rows("UiMapArtStyleLayer") if r["UiMapArtStyleID"] == style and r["LayerIndex"] == "0")
    tw, th = int(layer["TileWidth"]), int(layer["TileHeight"])
    lw, lh = int(layer["LayerWidth"]), int(layer["LayerHeight"])
    canvas = Image.new("RGBA", (lw, lh), (0, 0, 0, 255))
    for t in rows("UiMapArtTile"):
        if t["UiMapArtID"] == art_id and t["LayerIndex"] == "0":
            tile = art.by_fdid(int(t["FileDataID"])).resize((tw, th))
            canvas.alpha_composite(tile, (int(t["ColIndex"]) * tw, int(t["RowIndex"]) * th)) if int(t["ColIndex"]) * tw < lw and int(t["RowIndex"]) * th < lh else None
    return canvas


SETUP = r"""
local DIR, MAPID, SEL = ...
assert(loadfile(DIR .. "/test/wowmock.lua"))(DIR)
assert(loadfile(DIR .. "/test/tlmock.lua"))(DIR)
local ns = {}
for line in io.lines(DIR .. "/../TrainerLocator/TrainerLocator.toc") do
	if line:match("%.lua%s*$") then assert(loadfile(DIR .. "/../TrainerLocator/" .. line))("TrainerLocator", ns) end
end
MOCK.side = SEL:find("SHAMAN") and "Horde" or "Alliance"
MOCK.Fire("ADDON_LOADED", "TrainerLocator"); MOCK.Fire("PLAYER_LOGIN")
ns.char.selection = SEL
ns.db.showOther = true
MOCK.ShowMap(MAPID)
local out = {}
for _, p in ipairs(MOCK.Pins()) do
	if p:IsShown() then
		local x, y = p:GetPosition()
		table.insert(out, { x = x, y = y, name = p.row.trainer.name, atlas = p.Icon:GetAtlas(), file = p.Icon._file,
			grey = p.Icon._desaturated })
	end
end
return out
"""


def main():
    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    pins = rt.eval("function(src, d, m, s) return assert(loadstring(src))(d, m, s) end")(SETUP, TOOLS, MAP, SEL)
    pins = [pins[k] for k in sorted(pins.keys())]
    img = map_art(MAP)
    font = ImageFont.truetype(art.font(), 13)
    d = ImageDraw.Draw(img)
    for p in pins:
        if p["atlas"]:
            icon = art.atlas(p["atlas"])[0]
        else:
            icon = art.file(p["file"])
            w, h = icon.size
            icon = icon.crop((int(w * 0.08), int(h * 0.08), int(w * 0.92), int(h * 0.92)))
        icon = icon.resize((PIN, PIN), Image.LANCZOS)
        if p["grey"]:
            g = icon.convert("LA").convert("RGBA")
            g.putalpha(icon.getchannel("A"))
            icon = g
        x, y = int(p["x"] * img.width), int(p["y"] * img.height)
        img.alpha_composite(icon, (x - PIN // 2, y - PIN // 2))
        if NAMES:
            d.text((x + PIN // 2 + 3, y - 7), p["name"], font=font, fill=(255, 255, 255, 255), stroke_width=2, stroke_fill=(0, 0, 0, 255))
    img.convert("RGB").save(OUT)
    print("wrote", OUT, len(pins), "pins")


main()
