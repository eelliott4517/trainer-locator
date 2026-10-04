"""Builds TrainerLocator/Data.lua from the Wowhead scrape and Forever's own map table.

    python3 tools/build_data.py

Reads:
  data/wowhead/scrape.json   every NPC Wowhead's WoW: Forever database flags as a trainer (the
                             npcs?filter=28;1;0 list) and the Forever trainers it doesn't flag
                             (scrape_wowhead.js's EXTRA list), with their map spots (g_mapperData)
                             and Teaches tabs; made by scrape_wowhead.js
  data/db2/UiMap.csv         Forever 1.60.1's map tables from wago.tools (zone names, continents,
  data/db2/UiMapAssignment.csv   and the world rectangle each map shows)
  data/cmangos_trainers.json vanilla trainers' spawns, to pick Wowhead's right spots (extract_cmangos.py)
  data/cmangos_teach.json    what vanilla trainers teach by cMaNGOS: trainer type, class and the
                             skills their spells need (extract_cmangos.py)

Each trainer gets one entry per thing it teaches: a class's spells, a profession (with the ranks it
trains), weapon skills, riding, pet skills, mage portals, or anything else. That comes from the
Teaches tabs; a vanilla trainer whose page has none gets it from cMaNGOS, and an EXTRA one from its
title. Vendors Wowhead lists as trainers that only carry its placeholder hunter-pet list are left out.
"""
import csv
import json
import os
import re
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "TrainerLocator", "Data.lua")

CLASS_BITS = {1: "WARRIOR", 2: "PALADIN", 4: "HUNTER", 8: "ROGUE", 16: "PRIEST", 64: "SHAMAN",
              128: "MAGE", 256: "WARLOCK", 1024: "DRUID"}
CLASS_IDS = {bit.bit_length(): token for bit, token in CLASS_BITS.items()}   # 1 WARRIOR .. 11 DRUID
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

# cMaNGOS's trainer types (creature_template.TrainerType)
CM_CLASS, CM_RIDING, CM_TRADESKILL, CM_PET = 0, 1, 2, 3

# What a title says someone trains, for the trainers Wowhead doesn't flag (scrape_wowhead.js's EXTRA
# list) when their page has no Teaches tab either
TITLE_KINDS = [
    (re.compile(r"\b(%s) Trainer\b" % "|".join(t.title() for t in CLASS_BITS.values())), "class"),
    (re.compile(r"\bPet Trainer\b"), "pet"),
    (re.compile(r"\bPortal Trainer\b"), "portal"),
    (re.compile(r"\bRiding\b"), "riding"),
    (re.compile(r"\bWeapons? (?:Trainer|Master)\b"), "weapon"),
]
TITLE_PROFS = [
    (171, r"Alchemist|Alchemy"),
    (164, r"Blacksmith|Armorsmith|Weaponsmith|Swordsmith|Axesmith|Hammersmith|Weapon Crafter|Armor Crafter"),
    (333, r"Enchanter|Enchanting"),
    (202, r"Engineer"),
    (182, r"Herbalist|Herbalism"),
    (165, r"Leatherworker|Leathercrafter|Leatherworking"),
    (186, r"\bMiner\b|\bMining\b"),
    (393, r"Skinner|Skinning"),
    (197, r"\bTailor"),
    (185, r"\bCook\b|\bCooking\b|\bChef\b"),
    (129, r"First Aid|Physician|Surgeon"),
    (356, r"Fisherman|Fishing"),
]

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
    bounds, lands on the real spot. The copies they leave behind give each map's scale and shift.
    That's fitted first, from every vanilla NPC (learn, then fit), and then places them all: it
    puts back the vanilla NPCs Wowhead lists only by their copy, and clears the copies off
    Forever's new NPCs, who have no cMaNGOS spawn."""

    def __init__(self, bounds, cmangos):
        self.bounds, self.cmangos = bounds, cmangos
        self.pairs = {}         # [uiMapID] = [(real spot, copy)]
        self.shift = {}         # [uiMapID] = ((a, b), (c, d)): a copy sits at a x + b, c y + d
        self.stats = Counter()
        self.names = {}         # [what happened] = names, for the spots worth a second look

    def note(self, what, name):
        self.stats[what] += 1
        self.names.setdefault(what, []).append(name)

    def spawns_on(self, npc_id, clusters):
        """The NPC's cMaNGOS spawns, put on each map Wowhead shows it on ([] for Forever's own NPCs)"""
        spawns = self.cmangos.get(str(npc_id)) or []
        maps = sorted({c[0] for c in clusters})
        return [p for m in maps for s in spawns for p in [project(self.bounds, m, s)] if p]

    def learn(self, npc_id, clusters):
        """First pass, over every NPC: a vanilla NPC seen on its spawn and off it gives (real spot,
        copy) pairs"""
        truth = self.spawns_on(npc_id, clusters)
        real = [c for c in clusters if any(close(c, t, MATCH) for t in truth)]
        if not real:
            return
        for c in clusters:
            if c not in real:
                k = min((r for r in real if r[0] == c[0]), key=lambda r: (r[1] - c[1]) ** 2 + (r[2] - c[2]) ** 2, default=None)
                if k:
                    self.pairs.setdefault(c[0], []).append((k, c))

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

    def unshift(self, c):
        """Where the NPC a copy was made from stands; None on maps Wowhead doesn't copy"""
        sh = self.shift.get(c[0])
        if not sh:
            return None
        (a, b), (cc, d) = sh
        return (c[0], (c[1] - b) / a, (c[2] - d) / cc)

    def vanilla(self, npc_id, name, clusters):
        """A vanilla NPC's spots (after fit); None for Forever's own NPCs"""
        if not self.cmangos.get(str(npc_id)):
            return None
        truth = self.spawns_on(npc_id, clusters)
        real = [c for c in clusters if any(close(c, t, MATCH) for t in truth)]
        if real:
            self.stats["vanilla, checked" + (" (copies dropped)" if len(real) < len(clusters) else "")] += 1
            return real
        # None of its spots is on its spawn. On a map Wowhead copies it may have kept only the copy:
        # undone, that lands back on the spawn.
        back = [u for c in clusters for u in [self.unshift(c)] if u and any(close(u, t, MATCH) for t in truth)]
        if back:
            self.note("vanilla, copy put back", name)
            return back
        kept = self.drop_copies(clusters)
        home = dedupe([t for t in truth if 0 <= t[1] <= 100 and 0 <= t[2] <= 100])
        if home and len(kept) == len(clusters) and all(c[0] in self.shift for c in clusters):
            # only spots on copied maps, none of them a copy of another, and too far from the spawn to
            # undo (one that wanders): its cMaNGOS spawn
            self.note("vanilla, at its cMaNGOS spawn", name)
            return home
        # it stands somewhere else in Forever: a spot on a map Wowhead doesn't copy, or a spot and
        # its copy side by side
        self.note("vanilla, moved in Forever", name)
        return kept

    def drop_copies(self, clusters):
        """The spots that aren't another of the NPC's spots' copy"""
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
        return out

    def new(self, clusters):
        """Forever's own NPCs: drop the spots that are another spot's copy"""
        out = self.drop_copies(clusters)
        self.stats["new" + (" (copies dropped)" if len(out) < len(clusters) else "")] += 1
        return out


def dedupe(spots):
    out = []
    for s in spots:
        if not any(close(k, s) for k in out):
            out.append(s)
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
    """1 Alliance, 2 Horde, 3 both: who'll talk to the NPC (it's friendly or neutral to them).
    Wowhead's react is [Alliance, Horde]: 1 friendly, 0 neutral, -1 hostile, null not recorded. With
    neither recorded (Forever's new neutral towns, like Riverglades) it's listed for both."""
    a, h = (list(react or []) + [None, None])[:2]
    if a is None and h is None:
        return 3
    return (1 if a is not None and a >= 0 else 0) | (2 if h is not None and h >= 0 else 0)


def class_of(mask):
    for bit, token in CLASS_BITS.items():
        if mask == bit:
            return token
    return None


def from_cmangos(cm):
    """What a vanilla trainer teaches by cMaNGOS (a cmangos_teach.json record), for the ones whose
    Wowhead page has no Teaches tab: a class trainer's class, spell count and top level; a profession
    trainer's professions, with the ranks it teaches and how many recipes, up to what skill"""
    kind = cm.get("type")
    if kind == CM_CLASS and cm.get("class") in CLASS_IDS:
        return [["class", CLASS_IDS[cm["class"]], {"max": cm["level"], "n": cm["n"]}]]
    if kind == CM_PET:
        return [["pet", None, {}]]
    if kind == CM_RIDING:
        return [["riding", None, {}]]
    if kind != CM_TRADESKILL:
        return []
    skills = {int(k): v for k, v in (cm.get("skills") or {}).items()}
    ranks = {}
    for skill, rank in cm.get("ranks") or []:
        ranks.setdefault(skill, []).append(rank)
    out = []
    for prof in sorted((set(skills) | set(ranks)) & PROFESSIONS):
        n, top = skills.get(prof, (0, 0))
        info = {"n": n}
        if prof in ranks:
            info["rank"], info["low"] = max(ranks[prof]), min(ranks[prof])
        if n and top:
            info["top"] = top
        out.append(["prof", prof, info])
    return out


def from_title(tag):
    """What a title says someone trains ("Shaman Trainer", "Weapons Trainer", "Expert Enchanter"):
    only the kind. How far a profession trainer goes isn't in it: Forever's own "Expert" trainers
    teach Expert, vanilla's teach Journeyman."""
    tag = tag or ""
    for pattern, kind in TITLE_KINDS:
        m = pattern.search(tag)
        if m:
            return [[kind, m.group(1).upper() if kind == "class" else None, {}]]
    for prof, pattern in TITLE_PROFS:
        if re.search(pattern, tag):
            return [["prof", prof, {}]]
    return []


def classify(npc, cm=None):
    """The entries of what an NPC teaches, or [] for none worth listing. cm is its cMaNGOS record
    (cmangos_teach.json), the fallback for a vanilla trainer whose page has no Teaches tab; one
    Wowhead doesn't flag as a trainer (scrape_wowhead.js's EXTRA list) falls back on its title."""
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
    if not out and cm:
        out = from_cmangos(cm)
    if not out and npc.get("extra"):
        out = from_title(tag)
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


def load_inputs(scrape_path=None):
    """Everything build() reads, from tools/data"""
    data = os.path.join(HERE, "data")
    scrape = json.load(open(scrape_path or os.path.join(data, "wowhead", "scrape.json")))
    return dict(scrape=scrape, maps=load_maps(), bounds=load_bounds(),
                cmangos=json.load(open(os.path.join(data, "cmangos_trainers.json"))),
                cm_teach=json.load(open(os.path.join(data, "cmangos_teach.json"))))


def build(scrape, maps, bounds, cmangos, cm_teach):
    """The trainers to list, the maps they need, and a report of what happened on the way"""
    placer = Placer(bounds, cmangos)
    found, dropped, unplaced, filled = [], Counter(), [], {}
    for npc_id, npc in sorted(scrape["npcs"].items(), key=lambda kv: int(kv[0])):
        if npc.get("missing"):
            dropped["no page"] += 1
            continue
        teach = classify(npc, cm_teach.get(npc_id))
        if not teach:
            dropped["placeholder pet list only" if npc.get("teach") else "nothing it teaches"] += 1
            continue
        if not classify({k: v for k, v in npc.items() if k != "extra"}):
            source = "cMaNGOS" if from_cmangos(cm_teach.get(npc_id) or {}) else "its title"
            filled.setdefault(source, []).append(npc["list"]["name"])
        clusters = [c for c in clusters_of(npc.get("map")) if c[0] in maps]
        if not clusters:
            unplaced.append(f'{npc["list"]["name"]} ({npc_id})')
            continue
        placer.learn(npc_id, clusters)
        found.append((npc_id, npc, teach, clusters))
    placer.fit()
    trainers = []
    for npc_id, npc, teach, clusters in found:
        lst = npc["list"]
        at = placer.vanilla(npc_id, lst["name"], clusters)
        if at is None:
            at = placer.new(clusters)
        trainers.append({"id": int(npc_id), "name": lst["name"], "tag": lst.get("tag"), "side": side_of(lst.get("react")),
                         "at": at[:MAX_SPAWNS], "teach": teach, "extra": bool(npc.get("extra"))})

    # every pet trainer teaches the same pet skills: the ones cMaNGOS or a title filled in get the list
    # the others have
    lists = Counter(tuple(e[2]["s"]) for t in trainers for e in t["teach"] if e[0] == "pet" and e[2].get("s"))
    for t in trainers:
        for e in t["teach"]:
            if e[0] == "pet" and not e[2].get("s") and lists:
                e[2]["s"] = list(lists.most_common(1)[0][0])

    used = set()
    for t in trainers:
        for m, _, _ in t["at"]:
            while m and m in maps and m not in used:
                used.add(m)
                m = maps[m][1]
    report = dict(dropped=dropped, unplaced=unplaced, filled=filled, placer=placer)
    return trainers, used, report


def render(trainers, used, maps):
    """Data.lua's text"""
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
    return "\n".join(lines)


def main():
    inputs = load_inputs(sys.argv[1] if len(sys.argv) > 1 else None)
    trainers, used, report = build(**inputs)
    with open(OUT, "w", newline="\n") as f:
        f.write(render(trainers, used, inputs["maps"]))

    maps, placer = inputs["maps"], report["placer"]
    kinds = Counter(e[0] if e[0] != "prof" else f"prof {e[1]}" for t in trainers for e in t["teach"])
    print(f"{len(trainers)} trainers, {len(used)} maps -> {os.path.relpath(OUT, ROOT)}")
    print("dropped:", dict(report["dropped"]), "| no map spot:", len(report["unplaced"]), ", ".join(report["unplaced"][:12]))
    for source, names in sorted(report["filled"].items()):
        print(f"no Teaches tab, from {source}: {len(names)}:", ", ".join(names))
    extras = [t for t in trainers if t["extra"]]
    if extras:
        print(f"not flagged as trainers on Wowhead (EXTRA): {len(extras)}:", ", ".join(
            f"{t['name']} <{t['tag']}> side {t['side']} {' '.join(str(e[1] or e[0]) for e in t['teach'])}" for t in extras))
    print("by kind:", dict(sorted(kinds.items())))
    print("spots:", dict(placer.stats), "| maps with copies:",
          ", ".join(f"{maps[m][0]} x{a:.3f}{b:+.1f} y{c:.3f}{d:+.1f}" for m, ((a, b), (c, d)) in sorted(placer.shift.items())))
    for what, names in sorted(placer.names.items()):
        print(f"  {what}:", ", ".join(names))


if __name__ == "__main__":
    sys.exit(main())
