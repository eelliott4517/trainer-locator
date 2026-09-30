"""Builds TrainerLocator/Data.lua from the Wowhead scrape and Forever's own map table.

    python3 tools/build_data.py

Reads:
  data/wowhead/scrape.json   every NPC Wowhead's WoW: Forever database flags as a trainer (the
                             npcs?filter=28;1;0 list), with its map spots (g_mapperData) and its
                             Teaches tabs; made by scrape_wowhead.js
  data/db2/UiMap.csv         Forever 1.60.1's map tables from wago.tools (zone names, continents,
  data/db2/UiMapAssignment.csv   and the world rectangle each map shows)
  data/cmangos_trainers.json vanilla trainers' spawns, to pick Wowhead's right spots (extract_cmangos.py)

Each trainer gets one entry per thing it teaches: a class's spells, a profession (with the ranks it
trains), weapon skills, riding, pet skills, mage portals, or anything else. Vendors Wowhead lists
as trainers that only carry its placeholder hunter-pet list are left out.
"""
import csv
import json
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "TrainerLocator", "Data.lua")

CLASS_BITS = {1: "WARRIOR", 2: "PALADIN", 4: "HUNTER", 8: "ROGUE", 16: "PRIEST", 64: "SHAMAN",
              128: "MAGE", 256: "WARLOCK", 1024: "DRUID"}
PROF_NAMES = {171: "Alchemy", 164: "Blacksmithing", 333: "Enchanting", 202: "Engineering", 182: "Herbalism",
              165: "Leatherworking", 186: "Mining", 393: "Skinning", 197: "Tailoring", 185: "Cooking", 129: "First Aid",
              356: "Fishing"}
PROFESSIONS = set(PROF_NAMES)
# Forever's reworked profession skill lines, folded into the originals the menu lists
REWORKED = {2937: 171, 2938: 164, 2939: 185, 2940: 333, 2941: 202, 2942: 129, 2943: 356, 2944: 182,
            2945: 165, 2946: 186, 2947: 393, 2948: 197}
RIDING = {148, 149, 150, 152, 533, 553, 554, 713, 762, 3011}
RANKS = ["Apprentice", "Journeyman", "Expert", "Artisan", "Master"]
WEAPONS = ["One-Handed Axes", "Two-Handed Axes", "One-Handed Maces", "Two-Handed Maces", "One-Handed Swords",
           "Two-Handed Swords", "Polearms", "Staves", "Daggers", "Fist Weapons", "Bows", "Crossbows", "Guns",
           "Thrown", "Wands"]
MAX_SPAWNS = 6
NEAR = 4.0      # map percent: sightings this close are one spot
MATCH = 2.5     # map percent: a spot this close to the cMaNGOS spawn is it

# spell row fields, as scrape_wowhead.js keeps them
ID, NAME, LEVEL, SKILL, LEARNEDAT, COST, CHRCLASS, REQCLASS, CAT, RANK = range(10)


def load_maps():
    maps = {}
    with open(os.path.join(HERE, "data", "db2", "UiMap.csv"), newline="") as f:
        for r in csv.DictReader(f):
            if r["System"] != "0":
                continue
            maps[int(r["ID"])] = (r["Name_lang"], int(r["ParentUiMapID"]), int(r["Type"]))
    return maps


def clusters_of(mapper):
    """(uiMapID, x, y) spots. Wowhead lists every place an NPC was seen, so one that walks about or
    stands between two spots shows up several times a step apart; sightings within NEAR of one
    already kept are the same NPC."""
    out = []
    for entries in (mapper or {}).values():
        for e in entries:
            m = e.get("uiMapId")
            for x, y in e.get("coords") or []:
                if m and not any(k[0] == m and close(k, (m, x, y)) for k in out):
                    out.append((m, float(x), float(y)))
    return out


def close(a, b, tol=None):
    return a[0] == b[0] and (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2 < (tol or NEAR) ** 2


def load_bounds():
    """[uiMapID] = (instance, minX, minY, maxX, maxY): the world rectangle each Forever map shows"""
    bounds = {}
    with open(os.path.join(HERE, "data", "db2", "UiMapAssignment.csv"), newline="") as f:
        for r in csv.DictReader(f):
            if (r["UiMin_0"], r["UiMin_1"], r["UiMax_0"], r["UiMax_1"]) == ("0", "0", "1", "1"):
                bounds.setdefault(int(r["UiMapID"]), (int(r["MapID"]), float(r["Region_0"]), float(r["Region_1"]),
                                                      float(r["Region_3"]), float(r["Region_4"])))
    return bounds


def project(bounds, m, spawn):
    """A cMaNGOS world spawn as x, y on Forever's map m, or None when it isn't on that map's continent"""
    b = bounds.get(m)
    if not b or b[0] != spawn[0]:
        return None
    _, x0, y0, x1, y1 = b
    return (m, 100 * (y1 - spawn[2]) / (y1 - y0), 100 * (x1 - spawn[1]) / (x1 - x0))


class Placer:
    """Picks each trainer's real spots from Wowhead's.

    For some maps Wowhead lists every NPC twice: where it stands, and that spot projected onto
    another client's map of the same place (a different size, so the copy sits a scale and shift
    away). Vanilla NPCs settle it: their cMaNGOS spawn, put on Forever's map with Forever's own
    bounds, lands on the real spot. The copies they leave behind give each map's scale and shift,
    which then clears the copies off Forever's new NPCs, who have no cMaNGOS spawn."""

    def __init__(self, bounds, cmangos):
        self.bounds, self.cmangos = bounds, cmangos
        self.pairs = {}         # [uiMapID] = [(real spot, copy)]
        self.stats = Counter()

    def vanilla(self, npc_id, clusters):
        spawns = self.cmangos.get(str(npc_id))
        if not spawns:
            return None
        truth = [p for c in clusters for s in spawns for p in [project(self.bounds, c[0], s)] if p]
        real = [c for c in clusters if any(close(c, t, MATCH) for t in truth)]
        if not real:
            self.stats["vanilla, moved in Forever"] += 1
            return clusters
        for c in clusters:
            if c not in real:
                k = min((r for r in real if r[0] == c[0]), key=lambda r: (r[1] - c[1]) ** 2 + (r[2] - c[2]) ** 2, default=None)
                if k:
                    self.pairs.setdefault(c[0], []).append((k, c))
        self.stats["vanilla, checked" + (" (copies dropped)" if len(real) < len(clusters) else "")] += 1
        return real

    def fit(self):
        """x_copy = a x + b and y_copy = c y + d for each map with enough copies"""
        self.shift = {}
        for m, pairs in self.pairs.items():
            if len(pairs) < 3:
                continue
            fx = linfit([p[0][1] for p in pairs], [p[1][1] for p in pairs])
            fy = linfit([p[0][2] for p in pairs], [p[1][2] for p in pairs])
            if fx and fy:
                self.shift[m] = (fx, fy)

    def new(self, clusters):
        """Forever's own NPCs: drop the spots that are another spot's copy"""
        out = []
        for c in clusters:
            copy = False
            for k in clusters:
                sh = self.shift.get(k[0])
                if k is not c and sh:
                    (a, b), (cc, d) = sh
                    if close((k[0], a * k[1] + b, cc * k[2] + d), c, MATCH):
                        copy = True
            if not copy:
                out.append(c)
        self.stats["new" + (" (copies dropped)" if len(out) < len(clusters) else "")] += 1
        return out


def linfit(xs, ys):
    """least squares y = a x + b; None when the points don't agree on one"""
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    if sxx < 1e-6:
        return None
    a = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sxx
    b = my - a * mx
    worst = max(abs(a * x + b - y) for x, y in zip(xs, ys))
    return (a, b) if worst < 2 else None


def side_of(react):
    a, h = (react or [None, None]) + [None] * (2 - len(react or []))
    return (1 if a is not None and a >= 0 else 0) | (2 if h is not None and h >= 0 else 0)


def class_of(mask):
    for bit, token in CLASS_BITS.items():
        if mask == bit:
            return token
    return None


def classify(npc):
    """The entries of what an NPC teaches, or [] for none worth listing."""
    tag = npc["list"].get("tag") or ""
    teach = npc.get("teach") or {}
    ability = teach.get("teaches-ability", [])
    recipe = teach.get("teaches-recipe", [])
    other = teach.get("teaches-other", [])
    out = []

    # class spells (category 7), by the class they're for
    class_spells = [s for s in ability if s[CAT] == 7 and class_of(s[REQCLASS] or s[CHRCLASS] or 0)]
    pet_spells = [s for s in ability if s[CAT] == -3]
    if "Portal Trainer" in tag:
        names = sorted({s[NAME] for s in class_spells if s[NAME].startswith(("Portal", "Teleport"))})
        out.append(["portal", None, {"s": names or sorted({s[NAME] for s in class_spells})}])
        class_spells = []
    if class_spells:
        by_class = Counter(class_of(s[REQCLASS] or s[CHRCLASS]) for s in class_spells)
        token = by_class.most_common(1)[0][0]
        mine = [s for s in class_spells if class_of(s[REQCLASS] or s[CHRCLASS]) == token]
        # Wowhead also hangs a short placeholder list of first spells on some vendors and crafters;
        # a real class trainer is tagged with the class ("Mage Trainer", "Master Mage") or has a full list
        if token.lower() in tag.lower() or len(mine) >= 20:
            out.append(["class", token, {"max": max(s[LEVEL] or 0 for s in mine), "n": len(mine)}])
        else:
            class_spells = []
    if "Pet Trainer" in tag and pet_spells:
        out.append(["pet", None, {"s": sorted({s[NAME] for s in pet_spells})}])

    # professions and riding, from the recipe tab (and any ability that names a profession)
    by_skill = {}
    riding = []
    for s in recipe + [s for s in ability if s[CAT] != 7 and s[CAT] != -3]:
        skills = [REWORKED.get(k, k) for k in (s[SKILL] or [])]
        if any(k in RIDING for k in skills) or s[NAME].endswith(("Riding", "Piloting", "Horsemanship")):
            riding.append(s[NAME])
            continue
        prof = next((k for k in skills if k in PROFESSIONS), None)
        if prof:
            by_skill.setdefault(prof, []).append(s)
    for prof, spells in sorted(by_skill.items()):
        # the rank spells ("Enchanting", rank "Journeyman") are what lets you past each skill cap
        is_rank = lambda s: s[RANK] in RANKS and s[NAME] == PROF_NAMES[prof]
        ranks = [RANKS.index(s[RANK]) + 1 for s in spells if is_rank(s)]
        recipes = [s for s in spells if not is_rank(s)]
        levels = [s[LEARNEDAT] for s in recipes if isinstance(s[LEARNEDAT], int) and s[LEARNEDAT] < 9999]
        info = {"n": len(recipes)}
        if ranks:
            info["rank"], info["low"] = max(ranks), min(ranks)
        if levels:
            info["top"] = max(levels)
        out.append(["prof", prof, info])
    if riding:
        out.append(["riding", None, {"s": sorted(set(riding))}])

    # weapon skills; class trainers' armor and parry lines go with their class
    weapons = [s for s in other if s[NAME] in WEAPONS]
    if weapons and not class_spells:
        weapons.sort(key=lambda s: WEAPONS.index(s[NAME]))
        out.append(["weapon", None, {"w": [s[NAME] for s in weapons], "ids": [s[ID] for s in weapons]}])

    if not out:
        # something else that isn't the placeholder pet list
        names = sorted({s[NAME] for s in recipe + other + [s for s in ability if s[CAT] != -3]})
        if names:
            out.append(["other", None, {"s": names}])
    return out


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def lua_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return ("%.1f" % v).rstrip("0").rstrip(".")
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, (list, tuple)):
        return "{" + ", ".join(lua_value(x) for x in v) + "}"
    raise TypeError(v)


def teach_lua(entry):
    kind, key, info = entry
    parts = [lua_str(kind)]
    if key is not None:
        parts.append(lua_value(key))
    for k in ("max", "n", "rank", "low", "top", "w", "ids", "s"):
        if k in info:
            parts.append(f"{k} = {lua_value(info[k])}")
    return "{" + ", ".join(parts) + "}"


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "data", "wowhead", "scrape.json")
    scrape = json.load(open(src))
    maps = load_maps()
    placer = Placer(load_bounds(), json.load(open(os.path.join(HERE, "data", "cmangos_trainers.json"))))
    found, dropped, unplaced = [], Counter(), []
    for npc_id, npc in sorted(scrape["npcs"].items(), key=lambda kv: int(kv[0])):
        if npc.get("missing"):
            dropped["no page"] += 1
            continue
        teach = classify(npc)
        if not teach:
            dropped["placeholder pet list only"] += 1
            continue
        clusters = [c for c in clusters_of(npc.get("map")) if c[0] in maps]
        if not clusters:
            unplaced.append(f'{npc["list"]["name"]} ({npc_id})')
            continue
        found.append((npc_id, npc, teach, clusters, placer.vanilla(npc_id, clusters)))
    placer.fit()
    trainers = []
    for npc_id, npc, teach, clusters, real in found:
        at = real if real is not None else placer.new(clusters)
        lst = npc["list"]
        trainers.append({"id": int(npc_id), "name": lst["name"], "tag": lst.get("tag"), "side": side_of(lst.get("react")),
                         "at": at[:MAX_SPAWNS], "teach": teach})

    used = set()
    for t in trainers:
        for m, _, _ in t["at"]:
            while m and m in maps and m not in used:
                used.add(m)
                m = maps[m][1]

    lines = ["-- Generated by tools/build_data.py from Wowhead's WoW: Forever database. Don't edit by hand.",
             "local _, ns = ...", "ns.Data = {}", "",
             "-- [uiMapID] = { name, parent map, map type (2 continent, 3 zone) }", "ns.Data.maps = {"]
    for m in sorted(used):
        name, parent, kind = maps[m]
        lines.append(f"\t[{m}] = {{{lua_str(name)}, {parent}, {kind}}},")
    lines += ["}", "",
              "-- side: 1 Alliance, 2 Horde, 3 both will talk to you. at: { uiMapID, x, y } spots, 0-100.",
              "-- teach: { kind, key, ... } for each thing they train: class (spells up to level max, n of them),",
              "-- prof (skill line; ranks low to rank, n recipes up to skill top), weapon (w names, ids spells),",
              "-- riding, pet, portal and other (s names)",
              "ns.Data.trainers = {"]
    for t in sorted(trainers, key=lambda t: t["name"]):
        tag = f", tag = {lua_str(t['tag'])}" if t["tag"] else ""
        at = ", ".join(lua_value(list(s)) for s in t["at"])
        teach = ", ".join(teach_lua(e) for e in t["teach"])
        lines.append(f"\t{{id = {t['id']}, name = {lua_str(t['name'])}{tag}, side = {t['side']}, at = {{{at}}}, teach = {{{teach}}}}},")
    lines += ["}", ""]
    with open(OUT, "w", newline="\n") as f:
        f.write("\n".join(lines))

    kinds = Counter(e[0] if e[0] != "prof" else f"prof {e[1]}" for t in trainers for e in t["teach"])
    print(f"{len(trainers)} trainers, {len(used)} maps -> {os.path.relpath(OUT, ROOT)}")
    print("dropped:", dict(dropped), "| no map spot:", len(unplaced), ", ".join(unplaced[:12]))
    print("by kind:", dict(sorted(kinds.items())))
    print("spots:", dict(placer.stats), "| maps with copies:",
          ", ".join(f"{maps[m][0]} x{a:.3f}{b:+.1f} y{c:.3f}{d:+.1f}" for m, ((a, b), (c, d)) in sorted(placer.shift.items())))


if __name__ == "__main__":
    sys.exit(main())
