"""Trainer spawn points and what each trainer teaches, from the cMaNGOS classic world database.

The dump is ~13 MB gzipped and isn't kept here. Download it once:
    curl -L -o /tmp/classicdb.sql.gz \
      https://raw.githubusercontent.com/cmangos/classic-db/master/Full_DB/ClassicDB_1_12_1_z2815.sql.gz
    python3 tools/extract_cmangos.py /tmp/classicdb.sql.gz

Writes, for every creature with the trainer flag:
  tools/data/cmangos_trainers.json  {creatureID: [[mapID, x, y], ...]} in world coordinates, for the
                                    ones that stand on Eastern Kingdoms (0) or Kalimdor (1)
  tools/data/cmangos_teach.json     {creatureID: {type, class, n, level, skills, ranks}}: its
                                    TrainerType (0 class, 1 riding, 2 professions, 3 pets) and
                                    TrainerClass, and from its npc_trainer spells how many there are
                                    (n), the highest level they need (level), how many need each skill
                                    and up to what skill value ({reqskill: [count, top]}, rank spells
                                    left out) and the profession ranks it teaches ([[skill, rank]],
                                    1 Apprentice to 4 Artisan)

Why: for some maps Wowhead lists each NPC twice, once where it stands and once projected onto the
modern client's differently sized map of the same place. The vanilla spawn picks the right one. And
some vanilla trainers' Wowhead pages have no Teaches tab; cMaNGOS says what they teach.
"""
import gzip
import json
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
WANT = {'creature', 'creature_spawn_entry', 'creature_template', 'npc_trainer', 'npc_trainer_template'}
TRAINER_FLAG = 16

# The trainer spells that teach a profession rank: (skill line, rank). Apprentice needs no skill
# (reqskill 0), the others the skill at 50, 125 and 200; the check in teach_of holds them to that.
RANK_SPELLS = {
    2275: (171, 1), 2280: (171, 2), 3465: (171, 3), 11612: (171, 4),    # Alchemy
    2020: (164, 1), 2021: (164, 2), 3539: (164, 3), 9786: (164, 4),     # Blacksmithing
    7414: (333, 1), 7415: (333, 2), 7416: (333, 3), 13921: (333, 4),    # Enchanting
    4039: (202, 1), 4040: (202, 2), 4041: (202, 3), 12657: (202, 4),    # Engineering
    2372: (182, 1), 2373: (182, 2), 3571: (182, 3), 11994: (182, 4),    # Herbalism
    2155: (165, 1), 2154: (165, 2), 3812: (165, 3), 10663: (165, 4),    # Leatherworking
    2581: (186, 1), 2582: (186, 2), 3568: (186, 3), 10249: (186, 4),    # Mining
    8615: (393, 1), 8619: (393, 2), 8620: (393, 3), 10769: (393, 4),    # Skinning
    3911: (197, 1), 3912: (197, 2), 3913: (197, 3), 12181: (197, 4),    # Tailoring
    2551: (185, 1), 3412: (185, 2),                                     # Cooking
    3279: (129, 1), 3280: (129, 2),                                     # First Aid
    7733: (356, 1), 7734: (356, 2), 18249: (356, 4),                    # Fishing
}
RANK_SKILL = [0, 50, 125, 200]


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


def teach_of(template, spells):
    """A trainer's cmangos_teach.json record from its creature_template row and its npc_trainer rows
    (reqskill, reqskillvalue and reqlevel by spell)"""
    skills, ranks = {}, []
    for spell, (skill, value, level) in sorted(spells.items()):
        if spell in RANK_SPELLS:
            line, rank = RANK_SPELLS[spell]
            if (skill, value) != ((0 if rank == 1 else line), RANK_SKILL[rank - 1]):
                raise SystemExit(f"rank spell {spell} needs skill {skill} at {value}, not what RANK_SPELLS says")
            ranks.append([line, rank])
            continue
        count, top = skills.get(skill, (0, 0))
        skills[skill] = (count + 1, max(top, value))
    return {"type": int(template['TrainerType']), "class": int(template['TrainerClass']), "n": len(spells),
            "level": max((s[2] for s in spells.values()), default=0),
            "skills": {str(k): list(v) for k, v in sorted(skills.items())}, "ranks": sorted(ranks)}


def main(path):
    db = read_dump(path)
    templates = {int(r['Entry']): r for r in db['creature_template'] if int(r['NpcFlags']) & TRAINER_FLAG}
    trainers = set(templates)
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

    # what they teach: their own npc_trainer spells and their template's (TrainerTemplateId)
    by_entry = defaultdict(dict)
    for table in ('npc_trainer', 'npc_trainer_template'):
        for r in db.get(table, []):
            by_entry[(table, int(r['entry']))][int(r['spell'])] = (int(r['reqskill']), int(r['reqskillvalue']), int(r['reqlevel']))
    teach = {}
    for cid, t in sorted(templates.items()):
        spells = dict(by_entry.get(('npc_trainer_template', int(t['TrainerTemplateId'])), {}))
        spells.update(by_entry.get(('npc_trainer', cid), {}))
        teach[str(cid)] = teach_of(t, spells)
    out = os.path.join(HERE, 'data', 'cmangos_teach.json')
    with open(out, 'w') as f:
        # a line a trainer, so a new dump's changes read as a diff
        f.write('{\n' + ',\n'.join(f'"{k}":' + json.dumps(v, separators=(',', ':')) for k, v in teach.items()) + '\n}\n')
    print(len(teach), 'trainers\' spells ->', os.path.relpath(out, os.path.dirname(HERE)))


if __name__ == '__main__':
    main(sys.argv[1])
