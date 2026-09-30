"""Trainer spawn points from the cMaNGOS classic world database, to check Wowhead's map spots by.

The dump is ~13 MB gzipped and isn't kept here. Download it once:
    curl -L -o /tmp/classicdb.sql.gz \
      https://raw.githubusercontent.com/cmangos/classic-db/master/Full_DB/ClassicDB_1_12_1_z2815.sql.gz
    python3 tools/extract_cmangos.py /tmp/classicdb.sql.gz

Writes tools/data/cmangos_trainers.json: {creatureID: [[mapID, x, y], ...]} in world coordinates,
for every creature with the trainer flag on Eastern Kingdoms (0) or Kalimdor (1).

Why: for some maps Wowhead lists each NPC twice, once where it stands and once projected onto the
modern client's differently sized map of the same place. The vanilla spawn picks the right one.
"""
import gzip
import json
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
WANT = {'creature', 'creature_spawn_entry', 'creature_template'}
TRAINER_FLAG = 16


def rows_of(s):
    """Split the VALUES part of an INSERT into rows of string fields."""
    out, field, fields = [], [], []
    depth, quoted, esc = 0, False, False
    for c in s:
        if quoted:
            if esc:
                field.append(c)
                esc = False
            elif c == '\\':
                esc = True
            elif c == "'":
                quoted = False
            else:
                field.append(c)
        elif c == "'":
            quoted = True
        elif c == '(':
            depth += 1
            if depth == 1:
                fields, field = [], []
            else:
                field.append(c)
        elif c == ')':
            depth -= 1
            if depth == 0:
                fields.append(''.join(field))
                out.append(fields)
            else:
                field.append(c)
        elif c == ',' and depth == 1:
            fields.append(''.join(field))
            field = []
        elif depth >= 1:
            field.append(c)
    return out


def read_dump(path):
    cols, data, table = {}, defaultdict(list), None
    with gzip.open(path, 'rt', encoding='utf-8', errors='replace') as f:
        for line in f:
            m = re.match(r'CREATE TABLE `(\w+)`', line)
            if m:
                table = m.group(1)
                if table in WANT:
                    cols[table] = []
                continue
            if table in WANT and line.startswith('  `'):
                cols[table].append(re.match(r'  `(\w+)`', line).group(1))
                continue
            m = re.match(r'INSERT INTO `(\w+)` VALUES (.*);\s*$', line)
            if m and m.group(1) in WANT:
                data[m.group(1)].extend(rows_of(m.group(2)))
    return {t: [dict(zip(cols[t], r)) for r in rows] for t, rows in data.items()}


def main(path):
    db = read_dump(path)
    trainers = {int(r['Entry']) for r in db['creature_template'] if int(r['NpcFlags']) & TRAINER_FLAG}
    entry_of = {int(r['guid']): int(r['entry']) for r in db.get('creature_spawn_entry', [])}
    spawns = defaultdict(list)
    for r in db['creature']:
        cid = int(r['id']) or entry_of.get(int(r['guid']), 0)
        mp = int(r['map'])
        if cid in trainers and mp in (0, 1):
            spawns[cid].append([mp, round(float(r['position_x']), 1), round(float(r['position_y']), 1)])
    out = os.path.join(HERE, 'data', 'cmangos_trainers.json')
    with open(out, 'w') as f:
        json.dump({str(k): v for k, v in sorted(spawns.items())}, f, separators=(',', ':'))
    print(len(trainers), 'trainer templates,', len(spawns), 'with world spawns ->', os.path.relpath(out, os.path.dirname(HERE)))


if __name__ == '__main__':
    main(sys.argv[1])
