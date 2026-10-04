# Trainer Locator

A WoW: Forever addon that shows where every trainer is: class trainers, weapon masters, profession
and secondary-skill trainers, riding, pet and portal trainers. Pick a kind and it lists every one in
the world, nearest first, grouped by continent. Click one to put the game's map pin on them.

- `/trainers` (or `/tl`) opens the window. So do the book button on the minimap's edge, the
  minimap's addon menu and a key binding (Options > Keybindings > AddOns).
- Drag the minimap button to move it around the minimap; right-click it for the options.
  `/trainers minimap` (or the options page) hides or shows it.
- `/trainers alchemy`, `/trainers mage` or `/trainers weapon` opens it on that kind. Anything else
  searches every trainer by name, title or zone: `/trainers ironforge`.
- It starts on your class's trainers. Distances follow you as you walk.
- Click a trainer to put the map pin on them. That also tracks it, so the arrow shows in the world,
  and opens the map there (out of combat). Shift-click links the spot in chat and leaves your map pin
  where it was. Right-click clears the pin. TomTom gets a waypoint too when it's installed.
- Rows go grey when a trainer can't help you: a starting-area class trainer whose spells stop below
  your level, or a profession trainer who can't take you past your current rank.
- **Show on map** marks the list's trainers on zone and city maps. Hover a pin for the details,
  click it for the map pin.
- **Other faction** also lists trainers who won't talk to you, greyed out.
- Options > AddOns > Trainer Locator has the settings and the window scale.

## Data

`TrainerLocator/Data.lua` is generated. To refresh it:

1. `python3 tools/recv.py` (a localhost bridge the browser hands the scrape to)
2. Open <https://www.wowhead.com/forever/npcs?filter=28;1;0>, paste `tools/scrape_wowhead.js` into the
   developer console and let it run (an hour or so; Wowhead throttles it)
3. `python3 tools/build_data.py`

In a browser that can't reach the bridge, run `window.TL_NO_BRIDGE = true` before pasting the
scrape. When `TS.finished` is true, save `TS.packed` to a file and run
`python3 tools/import_scrape.py <file>` in place of step 1, then step 3.

Wowhead lists some maps' NPCs twice: where they stand, and that spot projected onto a
different-sized map of the same place. `build_data.py` keeps the spot that matches the NPC's vanilla
spawn from the cMaNGOS classic database, placed with Forever's own map bounds
(`tools/extract_cmangos.py` makes `tools/data/cmangos_trainers.json`). It uses the offset those pairs
reveal to clear the copies off Forever's new NPCs, and to put back the vanilla NPCs Wowhead only has
by their copy (on their cMaNGOS spawn when the copy can't be undone).

Some vanilla trainers' Wowhead pages have no Teaches tab; `tools/data/cmangos_teach.json` (also from
`extract_cmangos.py`) says what they teach. A few of Forever's own trainers aren't flagged as
trainers on Wowhead at all: the scrape fetches them by id (`EXTRA` in `scrape_wowhead.js`), and
they go by their title when their page has no Teaches tab either.

## Tests and previews

```
python3 -m venv /tmp/wowlua && /tmp/wowlua/bin/pip install lupa pillow
/tmp/wowlua/bin/python tools/test/run.py
/tmp/wowlua/bin/python tools/test/preview.py list out.png
/tmp/wowlua/bin/python tools/test/mapview.py 1453 class:MAGE map.png
/tmp/wowlua/bin/python tools/test/verify_atlases.py
```

`run.py` checks the data builder (`test_build.py`), then runs the addon in Lua 5.1 against a mock of
Forever's API, with the real map tables.
`preview.py` draws the window with the game's own art and font. `mapview.py` draws a world map
with the pins, to check spots against the buildings they belong in.

## Install

`sh tools/install.sh` copies it to the WoW: Forever beta client on macOS. A new addon needs a game
restart. Updates just need a `/reload`.

![Trainer Locator](tools/preview.png)
