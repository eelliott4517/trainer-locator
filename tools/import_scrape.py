"""Saves a scrape read out of the browser as tools/data/wowhead/scrape.json, for a browser that can't
reach recv.py's bridge (scrape_wowhead.js run with window.TL_NO_BRIDGE = true leaves it in TS.packed).

    python3 tools/import_scrape.py <file> [out, default tools/data/wowhead/scrape.json]

The file holds TS.packed (gzip, base64): alone, or between <<<TLSCRAPE and TLSCRAPE>>> anywhere in
it, as in a saved tool result. Prints what it got; then run python3 tools/build_data.py.
"""
import base64
import gzip
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "data", "wowhead", "scrape.json")


def main(path, out=OUT):
    text = open(path, encoding="utf-8", errors="replace").read()
    m = re.search(r"<<<TLSCRAPE([A-Za-z0-9+/=\\\s]+?)TLSCRAPE>>>", text)
    packed = re.sub(r"[\\\s]", "", m.group(1) if m else text)
    data = gzip.decompress(base64.b64decode(packed))
    scrape = json.loads(data)
    npcs = scrape.get("npcs") or {}
    if not scrape.get("list") or not npcs:
        raise SystemExit("that isn't a finished scrape: it needs the trainer list and the NPCs")
    missing = [k for k, n in npcs.items() if n.get("missing")]
    with open(out, "wb") as f:
        f.write(data)
    print(f"{len(scrape['list'])} trainers listed, {len(npcs)} pages ({len(missing)} not there) -> {os.path.relpath(out, os.path.dirname(HERE))}")
    for i in scrape.get("extra") or []:
        n = npcs.get(str(i))
        row = (n or {}).get("list") or {}
        print(f"  extra {i}: " + ("not scraped" if not n else "no page" if n.get("missing") else
              f"{row.get('name')} <{row.get('tag')}> react {row.get('react')} ({row.get('reactText', 'no React line')})"
              f"{', no tooltip' if row.get('noTooltip') else ''}, {sum(len(v) for v in (n.get('teach') or {}).values())} taught, "
              f"{'map spots' if n.get('map') else 'no map spots'}"))


if __name__ == "__main__":
    main(*sys.argv[1:3])
