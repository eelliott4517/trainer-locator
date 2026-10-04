"""The data builder's checks (tools/build_data.py), run by run.py as the "build" scenario: where it
puts the trainers Wowhead lists only by a copy, the trainers it fills in when their pages have no
Teaches tab, and who'll talk to whom. Each part runs on a small made-up case and on the checked-in
data, which also has to be what Data.lua holds.

    python3 tools/test/run.py build
"""
import json
import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
import build_data as B  # noqa: E402

failures = 0


def check(ok, msg):
    global failures
    if not ok:
        failures += 1
    print(("  ok   " if ok else "  FAIL ") + msg, flush=True)


def near(spot, m, x, y, tol=0.5):
    return spot[0] == m and abs(spot[1] - x) < tol and abs(spot[2] - y) < tol


def where(spots):
    return "; ".join("%d %.1f, %.1f" % tuple(s) for s in spots or [])


# A made-up continent (instance 0) whose maps 1 and 2 show world x 0-100 and y 0-100, so a spawn at
# world (100 - y, 100 - x) is at x, y on them. Wowhead copies map 1 at 1.25 x - 10, 1.25 y - 20.
BOUNDS = {1: (0, 0.0, 0.0, 100.0, 100.0), 2: (0, 0.0, 0.0, 100.0, 100.0)}


def spawn(x, y):
    return [0, 100.0 - y, 100.0 - x]


def copy(x, y):
    return 1.25 * x - 10, 1.25 * y - 20


def npc(name, react=None, tag=None, teach=None, extra=False, spots=()):
    out = {"list": {"name": name, "tag": tag, "react": react}, "teach": teach or {},
           "map": {"1": [{"uiMapId": m, "coords": [[x, y]]} for m, x, y in spots]}}
    if extra:
        out["extra"] = True
    return out


def placement():
    print("  - trainers Wowhead lists only by a copy")
    cmangos = {}
    placer = B.Placer(BOUNDS, cmangos)
    # four vanilla trainers seen on their spawn and at its copy give map 1's shift
    for i, (x, y) in enumerate([(30, 40), (50, 60), (70, 50), (40, 80)]):
        cmangos[str(100 + i)] = [spawn(x, y)]
        placer.learn(100 + i, [(1, x, y), (1, *copy(x, y))])
    placer.fit()
    (a, b), (c, d) = placer.shift[1]
    check(abs(a - 1.25) < 1e-6 and abs(b + 10) < 1e-6 and abs(c - 1.25) < 1e-6 and abs(d + 20) < 1e-6,
          "the copies give map 1's shift (x%.3f%+.1f y%.3f%+.1f)" % (a, b, c, d))

    cmangos["200"] = [spawn(60, 50)]                   # listed only by its copy, a step off its spawn
    at = placer.vanilla(200, "Copy Only", [(1, *copy(61, 50.5))])
    check(len(at) == 1 and near(at[0], 1, 61, 50.5, 0.01), "one listed only by its copy is put back where it was seen: " + where(at))
    cmangos["201"] = [spawn(40, 40)]                   # wanders: its copy undoes to 3.6 off its spawn
    at = placer.vanilla(201, "Wanderer", [(1, *copy(43, 42))])
    check(at == [(1, 40.0, 40.0)], "one whose copy undoes too far from its spawn goes on the spawn: " + where(at))
    cmangos["202"] = [spawn(30, 30)]                   # really moved, on a map Wowhead doesn't copy
    at = placer.vanilla(202, "Moved", [(2, 70.0, 70.0)])
    check(at == [(2, 70.0, 70.0)], "one that moved, on a map without copies, stays where Wowhead saw it")
    cmangos["203"] = [spawn(20, 30)]                   # moved, with its copy beside it
    at = placer.vanilla(203, "Moved Copied", [(1, 80.0, 70.0), (1, *copy(80, 70))])
    check(at == [(1, 80.0, 70.0)], "one that moved on a copied map keeps its new spot and drops the copy: " + where(at))
    cmangos["204"] = [spawn(50, 60)]                   # on its spawn, with its copy
    at = placer.vanilla(204, "Checked", [(1, *copy(50, 60)), (1, 50.0, 60.0)])
    check(at == [(1, 50.0, 60.0)], "one seen on its spawn keeps that spot and loses the copy")
    at = placer.new([(1, 20.0, 60.0), (1, *copy(20, 60))])
    check(at == [(1, 20.0, 60.0)], "a Forever trainer loses its copy too")
    check(placer.vanilla(205, "Forever", [(1, 20.0, 60.0)]) is None, "and isn't treated as vanilla")


def fallbacks():
    print("  - trainers whose pages have no Teaches tab")
    placeholder = {"teaches-ability": [[2649, "Growl", 1, None, None, 0, 0, 0, -3, None]]}
    got = B.classify(npc("Malosh", tag="Warrior Trainer"), {"type": 0, "class": 1, "n": 99, "level": 60})
    check(got == [["class", "WARRIOR", {"max": 60, "n": 99}]], "a class trainer gets its class from cMaNGOS: %s" % got)
    got = B.classify(npc("Peter Galen"), {"type": 2, "class": 0, "n": 17, "level": 10, "skills": {"165": [15, 300]},
                                          "ranks": [[165, 1], [165, 2]]})
    check(got == [["prof", 165, {"n": 15, "rank": 2, "low": 1, "top": 300}]], "a profession trainer its profession and ranks: %s" % got)
    got = B.classify(npc("Kulleg Stonehorn"), {"type": 2, "class": 0, "n": 4, "level": 35, "skills": {},
                                               "ranks": [[393, 1], [393, 2], [393, 3], [393, 4]]})
    check(got == [["prof", 393, {"n": 0, "rank": 4, "low": 1}]], "one that only teaches ranks: %s" % got)
    check(B.classify(npc("Grokor"), {"type": 3, "class": 3}) == [["pet", None, {}]], "a pet trainer")
    check(B.classify(npc("Meilosh"), {"type": 0, "class": 0, "n": 75}) == [], "nothing from a classless 'class' trainer")
    check(B.classify(npc("Vendor", tag="General Goods", teach=placeholder)) == [], "a vendor with Wowhead's placeholder pet list is still left out")
    fireball = {"teaches-ability": [[133, "Fireball", 1, None, None, 0, 0, 128, 7, None]]}
    got = B.classify(npc("Twin", tag="Mage Trainer", teach=fireball), {"type": 0, "class": 1, "n": 99, "level": 60})
    check(got == [["class", "MAGE", {"max": 1, "n": 1}]], "cMaNGOS only fills in when Wowhead has nothing: %s" % got)

    titles = {"Shaman Trainer": ["class", "SHAMAN", {}], "Warrior Trainer": ["class", "WARRIOR", {}],
              "Weapons Trainer": ["weapon", None, {}], "Expert Enchanter": ["prof", 333, {}],
              "Artisan Weapon Crafter": ["prof", 164, {}], "Artisan Armorsmith": ["prof", 164, {}]}
    for title, want in titles.items():
        got = B.classify(npc("Extra", tag=title, teach=placeholder, extra=True))
        check(got == [want], "one Wowhead doesn't flag as a trainer goes by its title, %s: %s" % (title, got))
    check(B.classify(npc("Flagged", tag="Shaman Trainer", teach=placeholder)) == [],
          "a title alone doesn't make a trainer of an NPC Wowhead flags (its placeholder vendors)")


def sides():
    print("  - who'll talk to whom")
    cases = [([None, None], 3), (None, 3), ([], 3), ([1, None], 1), ([None, 1], 2), ([1, -1], 1), ([-1, 1], 2),
             ([0, 0], 3), ([None, 0], 2), ([1, 1], 3)]
    for react, want in cases:
        check(B.side_of(react) == want, "react %s: side %d (%s)" % (react, want, B.side_of(react)))


def checked_in():
    print("  - the checked-in data")
    inputs = B.load_inputs()
    trainers, used, report = B.build(**inputs)
    by_id = {t["id"]: t for t in trainers}
    data = open(os.path.join(TOOLS, "..", "TrainerLocator", "Data.lua"), encoding="utf-8").read()
    check(B.render(trainers, used, inputs["maps"]) == data, "Data.lua is what build_data.py makes of tools/data")

    # 1: the seven Wowhead had only by their copy, on their cMaNGOS spawns
    placer = report["placer"]
    for i in (812, 914, 918, 5480, 5484, 5497, 5517):
        t = by_id.get(i)
        home = t and placer.spawns_on(i, t["at"])
        check(t is not None and all(any(B.close(s, h, B.MATCH) for h in home) for s in t["at"]),
              "%s stands on the cMaNGOS spawn: %s" % (t and t["name"] or i, where(t and t["at"])))
    ander = by_id.get(914)
    check(ander and near(ander["at"][0], 1453, 80.2, 61.3, 0.6), "Ander Germaine at Stormwind 80.2, 61, as his tooltip says: " + where(ander and ander["at"]))

    # 2: the vanilla trainers whose pages have no Teaches tab, and Forever's trainers Wowhead doesn't flag
    classes = {985: "WARRIOR", 986: "SHAMAN", 8141: "WARRIOR", 8142: "DRUID", 5146: "MAGE", 4215: "ROGUE"}
    for i, token in classes.items():
        t = by_id.get(i)
        check(t is not None and ["class", token] == t["teach"][0][:2], "%s trains %s" % (t and t["name"] or i, token.lower()))
    for i in (3622, 3624):
        t = by_id.get(i)
        e = t and t["teach"][0]
        check(e and e[0] == "pet" and "Growl" in e[2].get("s", []), "%s is a pet trainer, with the pet skills" % (t and t["name"] or i))
    profs = {4578: 197, 4900: 171, 5164: 164, 7230: 164, 7231: 164, 7232: 164, 7406: 202, 7866: 165, 7868: 165, 7869: 165,
             7870: 165, 7871: 165, 7944: 202, 8126: 202, 8144: 393, 8153: 165, 8738: 202, 9584: 197, 11097: 165,
             11146: 164, 11177: 164, 11178: 164}
    missing = [i for i, skill in profs.items() if not (i in by_id and any(e[:2] == ["prof", skill] for e in by_id[i]["teach"]))]
    check(not missing, "the %d profession trainers with no Teaches tab are listed (missing %s)" % (len(profs), missing))
    # a scrape made with scrape_wowhead.js's EXTRA list says so; the one before it predates them
    extras = {270263: ("class", "SHAMAN"), 270278: ("class", "WARRIOR"), 271465: ("prof", 164), 271478: ("prof", 164),
              260080: ("weapon", None), 259287: ("prof", 333)}
    scraped = inputs["scrape"].get("extra")
    if scraped is None:
        print("  - (this scrape predates the EXTRA list, so it hasn't Forever's unflagged trainers yet)")
    else:
        check(set(extras) <= set(scraped), "the scrape fetched every EXTRA trainer (%s)" % sorted(set(extras) - set(scraped)))
        for i in extras:
            t = by_id.get(i)
            kind, key = extras[i]
            check(t is not None and any(e[0] == kind and (key is None or e[1] == key) for e in t["teach"]),
                  "Forever's %s (%d), whom Wowhead doesn't flag as a trainer, is listed: %s" % (t and t["name"] or "?", i, t and t["teach"]))

    # 3: nobody's hidden from both factions
    nobody = [t["name"] for t in trainers if t["side"] == 0]
    check(not nobody, "every trainer talks to someone (side 0: %s)" % nobody)
    react = {t["id"]: inputs["scrape"]["npcs"][str(t["id"])]["list"].get("react") or [] for t in trainers}
    unknown = [t for t in trainers if all(r is None for r in react[t["id"]])]
    check(all(t["side"] == 3 for t in unknown), "the %d whose reactions Wowhead hasn't recorded are listed for both: %s"
          % (len(unknown), ", ".join(t["name"] for t in unknown)))
    for i in (255891, 260562, 259585):
        t = by_id.get(i)
        check(t is not None and t["side"] != 0, "%s is listed (side %s)" % (t and t["name"] or i, t and t["side"]))


def run():
    global failures
    failures = 0
    placement()
    fallbacks()
    sides()
    checked_in()
    return failures


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
