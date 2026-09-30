"""Draws the Trainer Locator window the way WoW: Forever draws it, so the look can be checked without
the game: the addon runs in the mock, and every frame, texture and line of text it makes is drawn
with the game's own art and font (fetched from wago.tools by art.py, cached in tools/test/.art).
Text is measured with that font too, so wrapping and row heights come out as in the game.

    python3 -m venv /tmp/wowlua && /tmp/wowlua/bin/pip install lupa pillow
    /tmp/wowlua/bin/python tools/test/preview.py [scenario] [out.png]

Scenarios: list (a mage in Stormwind, the default), rowtip (a row's tooltip, with the map pin on
the nearest), profession (tailoring, for a 148/150 tailor), weapon, search ("ironforge" in all
trainers), other (the other faction's paladins shown) and horde (a shaman in Orgrimmar).
"""
import os
import re
import sys

import lupa.lua51 as lua51
from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageOps

import art

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCENARIO = sys.argv[1] if len(sys.argv) > 1 else "list"
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(TOOLS, f"preview-{SCENARIO}.png")
S = 2  # pixels per UI unit

NORMAL, WHITE, GREY = (1, 0.82, 0), (1, 1, 1), (0.5, 0.5, 0.5)
FONTS = {  # name: (height, default color); all of them have the 1, -1 black shadow
    "GameFontNormal": (12, NORMAL), "GameFontNormalLeft": (12, NORMAL), "GameFontNormalSmall": (10, NORMAL),
    "GameFontNormalMed3": (14, NORMAL), "GameFontNormalLarge": (16, NORMAL), "GameFontHighlight": (12, WHITE),
    "GameFontHighlightSmall": (10, WHITE), "GameFontDisable": (12, GREY), "GameFontDisableSmall": (10, GREY),
    "GameTooltipHeaderText": (14, WHITE), "GameTooltipText": (12, WHITE),
}
# Icons wago.tools can't name yet (Forever's new side tab icons), and stand-ins drawn instead
STAND_INS = {
    "interface\\icons\\inv_sidetab_reputation2_c60": "Interface\\Icons\\Achievement_Reputation_01",
    "interface/icons/inv_sidetab_reputation2_c60": "Interface\\Icons\\Achievement_Reputation_01",
    "interface/icons/inv_sidetab_currency_c60": "Interface\\Icons\\INV_Misc_Coin_02",
    "interface/icons/inv_sidetab_stats_c60": "Interface\\Icons\\INV_Misc_Book_09",
    "interface/icons/inv_sidetab_honor_alliance_c60": "Interface\\Icons\\INV_BannerPVP_02",
}

_fonts = {}


def font(size):
    if size not in _fonts:
        _fonts[size] = ImageFont.truetype(art.font(), int(round(size * S)))
    return _fonts[size]


# ------------------------------------------------------------------ text: codes, wrapping, measuring
TOKEN = re.compile(r"\|c([0-9a-fA-F]{8})|\|r|\|A:([^:|]+):(\d+):(\d+)(?::[-\d]+:[-\d]+)?\|a|\|\||\n|[^|\n]+|\|")


def runs(text, base):
    """(kind, value, color) pieces: kind is 'text', 'atlas' (value = (name, h, w)) or 'newline'."""
    out, color = [], base
    for m in TOKEN.finditer(text):
        tok = m.group(0)
        if m.group(1):
            h = m.group(1)
            color = (int(h[2:4], 16) / 255, int(h[4:6], 16) / 255, int(h[6:8], 16) / 255)
        elif tok == "|r":
            color = base
        elif m.group(2):
            out.append(("atlas", (m.group(2), int(m.group(3)), int(m.group(4) or m.group(3))), color))
        elif tok == "\n":
            out.append(("newline", None, color))
        elif tok == "||":
            out.append(("text", "|", color))
        else:
            out.append(("text", tok, color))
    return out


def layout_lines(text, size, width, base=WHITE):
    """Greedy word wrap. Returns lines of [(kind, value, color, x)], and each line's width (UI units)."""
    f = font(size)
    words = []  # each word: list of pieces, and a flag for a space before it
    cur, space = [], False
    for kind, value, color in runs(text, base):
        if kind == "newline":
            if cur:
                words.append((cur, space))
            words.append((None, False))
            cur, space = [], False
        elif kind == "atlas":
            if cur:
                words.append((cur, space))
                space = False
            words.append(([("atlas", value, color)], space))
            cur, space = [], False
        else:
            parts = re.split(r"( +)", value)
            for p in parts:
                if not p:
                    continue
                if p.startswith(" "):
                    if cur:
                        words.append((cur, space))
                        cur = []
                    space = True
                else:
                    cur.append(("text", p, color))
    if cur:
        words.append((cur, space))

    def wlen(pieces):
        total = 0
        for kind, value, _ in pieces:
            total += (value[2] if kind == "atlas" else f.getlength(value) / S)
        return total

    space_w = f.getlength(" ") / S
    lines, widths, line, x = [], [], [], 0
    for pieces, sp in words:
        if pieces is None:
            lines.append(line); widths.append(x); line, x = [], 0
            continue
        w = wlen(pieces)
        gap = space_w if (sp and line) else 0
        if width and line and x + gap + w > width + 0.5:
            lines.append(line); widths.append(x); line, x, gap = [], 0, 0
        x += gap
        for kind, value, color in pieces:
            line.append((kind, value, color, x))
            x += value[2] if kind == "atlas" else f.getlength(value) / S
    lines.append(line); widths.append(x)
    return lines, widths


def measure(fontname, text, wrap_width, spacing):
    size = FONTS.get(fontname, (12, WHITE))[0]
    if not text:
        return 0, 0
    lines, widths = layout_lines(text, size, wrap_width or 0)
    return max(widths), len(lines) * size + (len(lines) - 1) * spacing


# ------------------------------------------------------------------ the scene, from the addon in the mock
SETUP = r"""
local DIR, SCENARIO, MEASURE = ...
assert(loadfile(DIR .. "/test/wowmock.lua"))(DIR)
assert(loadfile(DIR .. "/test/tlmock.lua"))(DIR)
MOCK.Measure = function(font, text, width, spacing) return MEASURE(font, text, width, spacing) end
local ns = {}
for line in io.lines(DIR .. "/../TrainerLocator/TrainerLocator.toc") do
	if line:match("%.lua%s*$") then assert(loadfile(DIR .. "/../TrainerLocator/" .. line))("TrainerLocator", ns) end
end
-- a human in Stormwind's Trade District, unless the scenario says otherwise
MOCK.side, MOCK.classToken, MOCK.level = "Alliance", "MAGE", 60
MOCK.pos = { 1453, 0.60, 0.70 }
if SCENARIO == "profession" then
	MOCK.classToken = "WARRIOR"
	MOCK.professions = { { "Tailoring", 148, 150, 197 } }
elseif SCENARIO == "horde" then
	MOCK.side, MOCK.classToken = "Horde", "SHAMAN"
	MOCK.pos = { 1454, 0.45, 0.60 }
end
MOCK.Fire("ADDON_LOADED", "TrainerLocator"); MOCK.Fire("PLAYER_LOGIN")
if SCENARIO == "other" then ns.db.showOther = true end
MOCK.Slash("/trainers")
if SCENARIO == "profession" then TrainerLocatorFrame.category:MockPick("prof:197") end
if SCENARIO == "weapon" then TrainerLocatorFrame.category:MockPick("weapon") end
if SCENARIO == "search" then TrainerLocatorFrame.category:MockPick("all"); TrainerLocatorFrame.search:MockType("ironforge") end
if SCENARIO == "other" then TrainerLocatorFrame.category:MockPick("class:PALADIN") end
local roots, hovered, owner = { TrainerLocatorFrame }, nil, nil
local rows = {}
for _, f in ipairs(MOCK.frames) do if f.data and f:IsShown() then table.insert(rows, f) end end
table.sort(rows, function(a, b) return a._points[1][5] > b._points[1][5] end)
if SCENARIO == "rowtip" or SCENARIO == "profession" or SCENARIO == "weapon" then
	-- click the nearest, then hover the one below it
	rows[1]:Click("LeftButton")
	hovered = rows[2] or rows[1]
	owner = hovered
	MOCK.Hover(hovered)
end
local L = assert(loadfile(DIR .. "/test/layout.lua"))()
L.HideIdleScrollBars()
local tip
if owner and GameTooltip._shown then tip = { rows = GameTooltip._rows, owner = L.Box(owner), anchor = GameTooltip._anchor } end
return L.Dump(roots, hovered), tip
"""

# ------------------------------------------------------------------ drawing
LAYOUTS = {
    # NineSliceLayouts.TooltipDefaultLayout (its center is drawn separately, in the tooltip color)
    "TooltipDefaultLayout": {
        "TopLeftCorner": ("Tooltip-NineSlice-CornerTopLeft", 0, 0), "TopRightCorner": ("Tooltip-NineSlice-CornerTopRight", 0, 0),
        "BottomLeftCorner": ("Tooltip-NineSlice-CornerBottomLeft", 0, 0), "BottomRightCorner": ("Tooltip-NineSlice-CornerBottomRight", 0, 0),
        "TopEdge": "_Tooltip-NineSlice-EdgeTop", "BottomEdge": "_Tooltip-NineSlice-EdgeBottom",
        "LeftEdge": "!Tooltip-NineSlice-EdgeLeft", "RightEdge": "!Tooltip-NineSlice-EdgeRight",
    },
    # NineSliceLayouts.PortraitFrameTemplate, with Camelot's NineSliceLayoutOverrides applied
    "PortraitFrameTemplate": {
        "TopLeftCorner": ("UI-Frame-PortraitMetal-CornerTopLeft", -13, 16),
        "TopRightCorner": ("UI-Frame-Metal-CornerTopRight", 4 - 2, 16),
        "BottomLeftCorner": ("UI-Frame-Metal-CornerBottomLeft", -13, -8),
        "BottomRightCorner": ("UI-Frame-Metal-CornerBottomRight", 4 - 2, -8),
        "TopEdge": "_UI-Frame-Metal-EdgeTop", "BottomEdge": "_UI-Frame-Metal-EdgeBottom",
        "LeftEdge": "!UI-Frame-Metal-EdgeLeft", "RightEdge": "!UI-Frame-Metal-EdgeRight",
    },
}


class Canvas:
    def __init__(self, bounds):
        self.ox, self.oy = bounds[0], bounds[1]
        self.w, self.h = int((bounds[2] - bounds[0]) * S), int((bounds[3] - bounds[1]) * S)
        self.img = Image.new("RGBA", (self.w, self.h), (22, 24, 28, 255))

    def px(self, x, y):
        return int(round((x - self.ox) * S)), int(round((y - self.oy) * S))

    def paste(self, tile, box, clip=None, blend=None):
        """Draws an RGBA image into the UI-unit box, cut to clip."""
        x0, y0 = self.px(box[0], box[1])
        x1, y1 = self.px(box[2], box[3])
        if x1 <= x0 or y1 <= y0:
            return
        if tile.size != (x1 - x0, y1 - y0):
            tile = tile.resize((x1 - x0, y1 - y0), Image.LANCZOS)
        layer = Image.new("RGBA", self.img.size, (0, 0, 0, 0))
        layer.paste(tile, (x0, y0))
        if clip:
            cx0, cy0 = self.px(clip[0], clip[1])
            cx1, cy1 = self.px(clip[2], clip[3])
            m = Image.new("L", self.img.size, 0)
            ImageDraw.Draw(m).rectangle([cx0, cy0, cx1 - 1, cy1 - 1], fill=255)
            layer.putalpha(ImageChops.multiply(layer.getchannel("A"), m))
        if blend == "ADD":
            a = layer.getchannel("A")
            rgb = Image.merge("RGB", [ImageChops.multiply(c, a) for c in layer.split()[:3]])
            base = self.img.convert("RGB")
            out = ImageChops.add(base, rgb)
            out.putalpha(self.img.getchannel("A"))
            self.img = out
        else:
            self.img.alpha_composite(layer)


def tinted(img, vcolor=None, alpha=1.0, desaturated=False):
    img = img.copy()
    if desaturated:
        a = img.getchannel("A")
        g = ImageOps.grayscale(img.convert("RGB"))
        img = Image.merge("RGBA", (g, g, g, a))
    if vcolor:
        r, g, b = (vcolor + [1, 1, 1])[:3]
        chans = img.split()
        img = Image.merge("RGBA", [chans[0].point(lambda v: v * r), chans[1].point(lambda v: v * g),
                                   chans[2].point(lambda v: v * b), chans[3]])
        if len(vcolor) > 3 and vcolor[3] is not None:
            alpha *= vcolor[3]
    if alpha < 0.999:
        img.putalpha(img.getchannel("A").point(lambda v: v * alpha))
    return img


def cut(img, coords):
    """SetTexCoord on an image: left, right, top, bottom as fractions (flipped when reversed)."""
    if not coords:
        return img
    if len(coords) == 8:  # corner coords: take the upper left and lower right corners
        coords = [coords[0], coords[6], coords[1], coords[7]]
    l, r, t, b = coords
    W, H = img.size
    x0, x1 = sorted((l * W, r * W))
    y0, y1 = sorted((t * H, b * H))
    part = img.crop((int(round(x0)), int(round(y0)), max(int(round(x0)) + 1, int(round(x1))), max(int(round(y0)) + 1, int(round(y1)))))
    if l > r:
        part = ImageOps.mirror(part)
    if t > b:
        part = ImageOps.flip(part)
    return part


def tiled(img, unit_w, unit_h, box, horiz, vert):
    """Repeats the art at its own size along the tiled directions and stretches the others."""
    bw, bh = (box[2] - box[0]) * S, (box[3] - box[1]) * S
    tw = max(1, int(round(unit_w * S))) if horiz else max(1, int(round(bw)))
    th = max(1, int(round(unit_h * S))) if vert else max(1, int(round(bh)))
    piece = img.resize((tw, th), Image.LANCZOS)
    out = Image.new("RGBA", (max(1, int(round(bw))), max(1, int(round(bh)))), (0, 0, 0, 0))
    for y in range(0, out.height, th):
        for x in range(0, out.width, tw):
            out.paste(piece, (x, y))
    return out


def sliced(img, aw, ah, margins, out_w, out_h):
    """Draws a sliced atlas at a size: the margins keep their size, the middle stretches or tiles."""
    L, T, R, B, tile = margins
    sx, sy = img.width / aw, img.height / ah
    dl, dr, dt, db = L * S, R * S, T * S, B * S
    if dl + dr > out_w:
        k = out_w / (dl + dr); dl, dr = dl * k, dr * k
    if dt + db > out_h:
        k = out_h / (dt + db); dt, db = dt * k, db * k
    xs = [0, round(L * sx), img.width - round(R * sx), img.width]
    ys = [0, round(T * sy), img.height - round(B * sy), img.height]
    dx = [0, round(dl), out_w - round(dr), out_w]
    dy = [0, round(dt), out_h - round(db), out_h]
    out = Image.new("RGBA", (out_w, out_h), (0, 0, 0, 0))
    for i in range(3):
        for j in range(3):
            src = (xs[i], ys[j], xs[i + 1], ys[j + 1])
            w, h = dx[i + 1] - dx[i], dy[j + 1] - dy[j]
            if src[2] <= src[0] or src[3] <= src[1] or w <= 0 or h <= 0:
                continue
            piece = img.crop(src)
            if tile and (i == 1 or j == 1):
                nw = max(1, round(piece.width * S / sx)) if i == 1 else w
                nh = max(1, round(piece.height * S / sy)) if j == 1 else h
                piece = piece.resize((nw, nh), Image.LANCZOS)
                cell = Image.new("RGBA", (w, h), (0, 0, 0, 0))
                for y in range(0, h, nh):
                    for x in range(0, w, nw):
                        cell.paste(piece, (x, y))
                piece = cell
            else:
                piece = piece.resize((w, h), Image.LANCZOS)
            out.paste(piece, (dx[i], dy[j]))
    return out


def texture_image(item, box):
    """The image a texture item shows, sized for its box (None if it shows nothing)."""
    if item.get("color"):
        c = item["color"]
        return Image.new("RGBA", (1, 1), tuple(int(v * 255) for v in c[:3]) + (int(c[3] * 255),))
    if item.get("atlas"):
        found = art.atlas(item["atlas"])
        if not found:
            return None
        img, aw, ah = found
        name = item["atlas"]
        img = cut(img, item.get("coords"))
        horiz = name.startswith("_") or item.get("htile")
        vert = name.startswith("!") or item.get("vtile")
        if horiz or vert:
            return tiled(img, aw, ah, box, horiz, vert)
        margins = art.slices(name)
        if margins and not item.get("coords"):
            return sliced(img, aw, ah, margins, max(1, round((box[2] - box[0]) * S)), max(1, round((box[3] - box[1]) * S)))
        return img
    if item.get("file"):
        path = item["file"]
        img = art.file(STAND_INS.get(path.lower(), path)) if isinstance(path, str) else None
        if img is None:
            return None
        return cut(img, item.get("coords"))
    return None


def draw_texture(cv, item):
    box = item["box"]
    img = texture_image(item, box)
    if img is None:
        return
    img = tinted(img, item.get("vcolor"), item.get("alpha", 1), item.get("desaturated"))
    x0, y0 = cv.px(box[0], box[1])
    x1, y1 = cv.px(box[2], box[3])
    if x1 <= x0 or y1 <= y0:
        return
    img = img.resize((x1 - x0, y1 - y0), Image.LANCZOS)
    if item.get("circle"):
        m = Image.new("L", img.size, 0)
        ImageDraw.Draw(m).ellipse([img.width * 0.03, 0, img.width * 0.97, img.height * 0.94], fill=255)
        img.putalpha(ImageChops.multiply(img.getchannel("A"), m))
    if item.get("mask") and item.get("maskBox"):
        found = art.atlas(item["mask"])
        if found:
            mb = item["maskBox"]
            mx0, my0 = cv.px(mb[0], mb[1])
            mx1, my1 = cv.px(mb[2], mb[3])
            margins = art.slices(item["mask"])
            if margins:
                mask = sliced(found[0], found[1], found[2], margins, max(1, mx1 - mx0), max(1, my1 - my0)).getchannel("A")
            else:
                mask = found[0].getchannel("A").resize((max(1, mx1 - mx0), max(1, my1 - my0)), Image.LANCZOS)
            full = Image.new("L", cv.img.size, 0)
            full.paste(mask, (mx0, my0))
            part = full.crop((x0, y0, x1, y1))
            img.putalpha(ImageChops.multiply(img.getchannel("A"), part))
    cv.paste(img, box, item.get("clip"), item.get("blend"))


def draw_nineslice(cv, item):
    lay = LAYOUTS.get(item["layout"])
    if not lay:
        return
    L, T, R, B = item["box"]
    boxes = {}
    for key, point in (("TopLeftCorner", "TL"), ("TopRightCorner", "TR"), ("BottomLeftCorner", "BL"), ("BottomRightCorner", "BR")):
        name, x, y = lay[key]
        img, w, h = art.atlas(name)
        ax = L + x if "L" in point else R + x
        ay = T - y if "T" in point else B - y
        x0 = ax if "L" in point else ax - w
        y0 = ay if "T" in point else ay - h
        boxes[key] = (x0, y0, x0 + w, y0 + h)
        cv.paste(img, boxes[key], blend=None)
    tl, tr, bl, br = boxes["TopLeftCorner"], boxes["TopRightCorner"], boxes["BottomLeftCorner"], boxes["BottomRightCorner"]
    for key, box in (("TopEdge", (tl[2], tl[1], tr[0], None)), ("BottomEdge", (bl[2], None, br[0], bl[3])),
                     ("LeftEdge", (tl[0], tl[3], None, bl[1])), ("RightEdge", (None, tr[3], tr[2], br[1]))):
        name = lay[key]
        img, w, h = art.atlas(name)
        x0, y0, x1, y1 = box
        if key == "TopEdge":
            y1 = y0 + h
        elif key == "BottomEdge":
            y0 = y1 - h
        elif key == "LeftEdge":
            x1 = x0 + w
        else:
            x0 = x1 - w
        full = (x0, y0, x1, y1)
        cv.paste(tiled(img, w, h, full, name.startswith("_"), name.startswith("!")), full)


def draw_text(cv, item):
    fontname = item.get("font") or "GameFontHighlight"
    size, base = FONTS.get(fontname, (12, WHITE))
    if item.get("color"):
        base = tuple(item["color"][:3])
    box = item["box"]
    width = (box[2] - box[0]) if item.get("wrap") else 0
    lines, widths = layout_lines(item["text"], size, width, base)
    spacing = item.get("spacing") or 0
    total = len(lines) * size + (len(lines) - 1) * spacing
    top = box[1] + max(0, ((box[3] - box[1]) - total) / 2)  # JustifyV MIDDLE, the default
    f = font(size)
    alpha = item.get("alpha", 1)
    layer = Image.new("RGBA", cv.img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for i, (line, lw) in enumerate(zip(lines, widths)):
        y = top + i * (size + spacing)
        justify = item.get("justify") or ("LEFT" if fontname.endswith("Left") else "CENTER")
        x = box[0] if justify == "LEFT" else (box[2] - lw if justify == "RIGHT" else (box[0] + box[2] - lw) / 2)
        base_y = y + size * 0.86
        for kind, value, color, dx in line:
            if kind == "atlas":
                found = art.atlas(value[0])
                if found:
                    ih, iw = value[1], value[2]
                    ab = (x + dx, y + (size - ih) / 2, x + dx + iw, y + (size - ih) / 2 + ih)
                    img = found[0].resize((max(1, int(iw * S)), max(1, int(ih * S))), Image.LANCZOS)
                    ax, ay = cv.px(ab[0], ab[1])
                    layer.alpha_composite(img, (max(0, ax), max(0, ay)))
                continue
            px, py = cv.px(x + dx, base_y)
            rgb = tuple(int(c * 255) for c in color[:3])
            d.text((px + S, py + S), value, font=f, fill=(0, 0, 0, int(255 * alpha)), anchor="ls")
            d.text((px, py), value, font=f, fill=rgb + (int(255 * alpha),), anchor="ls")
    if item.get("clip"):
        c = item["clip"]
        cx0, cy0 = cv.px(c[0], c[1])
        cx1, cy1 = cv.px(c[2], c[3])
        m = Image.new("L", cv.img.size, 0)
        ImageDraw.Draw(m).rectangle([cx0, cy0, cx1 - 1, cy1 - 1], fill=255)
        layer.putalpha(ImageChops.multiply(layer.getchannel("A"), m))
    cv.img.alpha_composite(layer)


TIP_PAD, TIP_GAP = 10, 2


def tooltip_layout(tip):
    """Lines of a GameTooltip: the first in GameTooltipHeaderText (14), the rest GameTooltipText (12)."""
    rows = [tip["rows"][k] for k in sorted(tip["rows"].keys())] if hasattr(tip["rows"], "keys") else tip["rows"]
    natural, wrapping = 0, 0
    for i, r in enumerate(rows):
        size = 14 if i == 0 else 12
        w = measure("GameFontHighlight", r["left"], 0, 0)[0] * size / 12
        if r.get("right"):
            w += 20 + measure("GameFontHighlight", r["right"], 0, 0)[0] * size / 12
        if r.get("wrap"):
            wrapping = max(wrapping, w)
        else:
            natural = max(natural, w)
    width = max(natural, min(wrapping, 270), 80)
    laid, h = [], 0
    for i, r in enumerate(rows):
        size = 14 if i == 0 else 12
        lines, _ = layout_lines(r["left"], size, width if r.get("wrap") else 0, tuple(r["lc"][k] for k in sorted(r["lc"].keys())) if hasattr(r["lc"], "keys") else tuple(r["lc"]))
        laid.append((r, size, lines, h))
        h += len(lines) * size + (len(lines) - 1) * TIP_GAP + TIP_GAP
    return laid, width + 2 * TIP_PAD, h - TIP_GAP + 2 * TIP_PAD


def tooltip_box(tip):
    _, w, h = tooltip_layout(tip)
    o = [tip["owner"][k] for k in sorted(tip["owner"].keys())] if hasattr(tip["owner"], "keys") else tip["owner"]
    if tip.get("anchor") == "ANCHOR_TOP":
        cx = (o[0] + o[2]) / 2
        return (cx - w / 2, o[1] - h, cx + w / 2, o[1])
    return (o[2], o[1] - h, o[2] + w, o[1])   # ANCHOR_RIGHT: its bottom left at the owner's top right


def draw_tooltip(cv, tip):
    laid, w, h = tooltip_layout(tip)
    box = tooltip_box(tip)
    center = Image.new("RGBA", (1, 1), (23, 23, 48, 242))   # TOOLTIP_DEFAULT_BACKGROUND_COLOR
    cv.paste(center, (box[0] + 3, box[1] + 3, box[2] - 3, box[3] - 3))
    draw_nineslice(cv, {"layout": "TooltipDefaultLayout", "box": box})
    for r, size, lines, y in laid:
        top = box[1] + TIP_PAD + y
        item = {"box": (box[0] + TIP_PAD, top, box[2] - TIP_PAD, top + len(lines) * size), "text": r["left"],
                "font": "GameTooltipHeaderText" if size == 14 else "GameTooltipText", "justify": "LEFT",
                "wrap": bool(r.get("wrap")), "spacing": TIP_GAP, "color": r["lc"]}
        draw_text(cv, item)
        if r.get("right"):
            draw_text(cv, {"box": (box[0] + TIP_PAD, top, box[2] - TIP_PAD, top + size), "text": r["right"],
                           "font": "GameTooltipText", "justify": "RIGHT", "color": r["rc"]})


def draw_thumb(cv, item):
    x0, y0, x1, y1 = item["box"]
    top, _, h1 = art.atlas("minimal-scrollbar-small-thumb-top")
    mid = art.atlas("minimal-scrollbar-small-thumb-middle")[0]
    bottom, _, h2 = art.atlas("minimal-scrollbar-small-thumb-bottom")
    cv.paste(top, (x0, y0, x1, y0 + h1))
    cv.paste(mid, (x0, y0 + h1, x1, y1 - h2))
    cv.paste(bottom, (x0, y1 - h2, x1, y1))


def main():
    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    items, tip = rt.eval("function(src, d, s, m) return assert(loadstring(src))(d, s, m) end")(SETUP, TOOLS, SCENARIO, measure)

    def plain(v):
        if lua51.lua_type(v) == "table":
            keys = list(v.keys())
            if keys and all(isinstance(k, int) for k in keys):
                return [plain(v[k]) for k in sorted(keys)]
            return {k: plain(v[k]) for k in keys}
        return v

    items = [plain(items[k]) for k in sorted(items.keys())]
    tip = plain(tip) if tip is not None else None
    def shown(it):
        b, c = it["box"], it.get("clip")
        if not c:
            return b
        b = (max(b[0], c[0]), max(b[1], c[1]), min(b[2], c[2]), min(b[3], c[3]))
        return b if b[2] > b[0] and b[3] > b[1] else None
    boxes = [shown(it) for it in items if it["kind"] in ("texture", "nineslice", "text")]
    boxes = [b for b in boxes if b]
    if tip:
        boxes.append(tooltip_box(tip))
    bounds = (min(b[0] for b in boxes) - 24, min(b[1] for b in boxes) - 24, max(b[2] for b in boxes) + 24, max(b[3] for b in boxes) + 24)
    cv = Canvas(bounds)
    items.sort(key=lambda it: (it["strata"], it["level"], it["layer"], it["order"]))
    for it in items:
        kind = it["kind"]
        if kind == "texture":
            draw_texture(cv, it)
        elif kind == "nineslice":
            draw_nineslice(cv, it)
        elif kind == "text":
            draw_text(cv, it)
        elif kind == "thumb":
            draw_thumb(cv, it)
    if tip:
        draw_tooltip(cv, tip)
    cv.img.convert("RGB").save(OUT)
    print("wrote", OUT, cv.img.size)


main()
