#!/usr/bin/env python3
"""Writes Data/ClassicNpcs.lua: where the profession trainers, bankers and vendors stand, for players without
Questie. It also lists what the trainers teach and which reagents and recipes the vendors sell.

Spawns, trainers' spell lists and vendors' stock come from cmangos/classic-db (GPL-3.0), pinned to one commit and
cached in ~/.cache/professionsforever/classic-db. Spell, skill, faction and map data come from the wago.tools
tables for the WoW: Forever build (product wowf), cached the same way gen_recipes.py does; run that first, since
the reagents come from its Data/Recipes.lua. Run it by hand when the pin or the Forever build moves; leave the
attribution in the generated file.

Usage: tools/gen_npcs.py [--build 1.60.1.70888] [--refresh]
    no --build   use the newest wowf build wago.tools lists
    --refresh    download the Wago tables and the classic-db dump again even if cached
"""
import argparse
import gzip
import re
import sys
from pathlib import Path

import wago
from gen_recipes import PROFESSIONS
from wago import CACHE, cached_table, fetch, latest_build, rows

wago.AGENT = "ProfessionsForever-npc-generator (run by hand)"

CLASSIC_DB = "cmangos/classic-db"
COMMIT = "c33f90b8eeb3f8bacb53d5cbfee45075c80b416c"
DUMP = "Full_DB/ClassicDB_1_12_1_z2815.sql.gz"
DUMP_CACHE = CACHE.parent / "classic-db" / COMMIT / "ClassicDB.sql.gz"
ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / "Data" / "ClassicNpcs.lua"
RECIPES = ROOT / "Data" / "Recipes.lua"

WAGO_TABLES = ("UiMap", "UiMapAssignment", "FactionTemplate", "SkillLine", "SkillLineAbility", "SpellName", "SpellEffect", "AreaTable")
SQL_TABLES = ("creature", "creature_template", "npc_trainer", "npc_trainer_template", "npc_vendor",
              "npc_vendor_template", "item_template", "disenchant_loot_template")

FLAG_VENDOR, FLAG_TRAINER, FLAG_BANKER = 0x4, 0x10, 0x100  # UNIT_NPC_FLAG_* of the 1.12 client
# SpellEffect.Effect 36 learns a spell: most trainer rows are such teaching spells ("Journeyman Mining", "Smelt Thorium").
LEARN_SPELL = "36"
ZONE_MAP = "3"     # UiMap.Type of a zone or a city
CAPITAL_FLAG = 0x8  # AreaTable.Flags_0 of a capital city
CITY_MARGIN = 0.04  # a city's map counts for points at least this far (of the map's size) from its edge
# NPC id -> the zone map seen in game where the rule above picks a neighbour (Goldshire, Ironforge's edge, ...).
ZONE_FIX = {1215: 1429, 1218: 1429, 12942: 1422, 2481: 1431}
# The Expert skill books of First Aid, Cooking and Fishing; a vendor sells each. Keep in step with Waypoints/WaypointTrainers.lua.
SKILL_BOOKS = {16084, 16072, 16083}
# Who finishes the Artisan quest of First Aid (Gustaf, Gregory), Cooking (Dirge) and Fishing (Nat Pagle). Keep in step with Waypoints/WaypointTrainers.lua.
ARTISAN_NPCS = {12939, 12920, 8125, 12919}
# npc_trainer.reqskillvalue of the spell that teaches a rank -> the skill cap that rank gives (Apprentice needs none).
RANK_CAPS = {0: 75, 50: 150, 125: 225, 200: 300}
RECIPE_CLASS = 9   # item class of patterns, plans and the like
# FactionTemplate ids of a Human (Alliance) and an Orc (Horde) player.
PLAYER_TEMPLATES = {"alliance": "1", "horde": "2"}

TOKEN = re.compile(r"'((?:[^'\\]|\\.|'')*)'|(-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)|(NULL)|([(),;])")
ESCAPES = {"n": "\n", "r": "\r", "t": "\t", "0": "\0", "Z": "\x1a"}


def download_dump(refresh):
    if refresh or not DUMP_CACHE.exists():
        print(f"downloading {DUMP} ({COMMIT[:8]})")
        DUMP_CACHE.parent.mkdir(parents=True, exist_ok=True)
        DUMP_CACHE.write_bytes(fetch(f"https://raw.githubusercontent.com/{CLASSIC_DB}/{COMMIT}/{DUMP}"))


def unescape(text):
    return re.sub(r"\\(.)|''", lambda m: "'" if m.group(0) == "''" else ESCAPES.get(m.group(1), m.group(1)), text)


def sql_rows(statement):
    """Yields each parenthesised row of an INSERT ... VALUES statement as a list of Python values."""
    row = None
    for m in TOKEN.finditer(statement, statement.index("VALUES")):
        string, number, null, punct = m.groups()
        if punct == "(":
            row = []
        elif punct == ")":
            yield row
            row = None
        elif punct is None and row is not None:
            if null:
                row.append(None)
            elif number is not None:
                row.append(float(number) if re.search(r"[.eE]", number) else int(number))
            else:
                row.append(unescape(string))


def load_dump():
    """Returns { table: (column names, rows) } for the tables this script reads."""
    columns, found, current = {}, {t: [] for t in SQL_TABLES}, None
    with gzip.open(DUMP_CACHE, "rt", encoding="utf-8", errors="replace") as dump:
        for line in dump:
            if line.startswith("CREATE TABLE `"):
                current = line.split("`")[1]
                columns[current] = []
            elif current and line.startswith("  `"):
                columns[current].append(line.split("`")[1])
            elif line.startswith(")"):
                current = None
            elif line.startswith("INSERT INTO `"):
                table = line.split("`")[1]
                if table in found:
                    found[table].extend(sql_rows(line))
    return {t: (columns[t], found[t]) for t in SQL_TABLES}


def records(table):
    names, data = table
    return (dict(zip(names, row)) for row in data)


def reagent_items():
    text = RECIPES.read_text(encoding="utf-8")
    block = text[text.index("FP.ReagentUses = {"):]
    return {int(m.group(1)) for m in re.finditer(r"^\s*\[(\d+)\] = \"", block, re.M)}


class Maps:
    """World positions to the zone map a player sees them on, as fractions of that map."""

    def __init__(self, tables):
        zones = {r["ID"]: r["Name_lang"] for r in rows(tables["UiMap"]) if r["Type"] == ZONE_MAP}
        capitals = {r["ID"] for r in rows(tables["AreaTable"]) if int(r["Flags_0"]) & CAPITAL_FLAG}
        self.boxes = {}
        for r in rows(tables["UiMapAssignment"]):
            ui = r["UiMapID"]
            # Assignments for a WMO group or doodad place only cover part of a map.
            if ui not in zones or r["WMOGroupID"] != "0" or r["WMODoodadPlacementID"] != "0":
                continue
            x0, y0, x1, y1 = (float(r[k]) for k in ("Region_0", "Region_1", "Region_3", "Region_4"))
            self.boxes.setdefault(int(r["MapID"]), []).append((int(ui), zones[ui], r["AreaID"] in capitals, x0, y0, x1, y1))

    def locate(self, world_map, x, y, ui=None):
        """(ui map, zone name, map x, map y) of the point, or None. The art of neighbouring zones overlaps, so a capital
        wins unless the point sits on the edge of its map, and otherwise the map the point is most central on.
        A given ui map wins when it holds the point."""
        held = []
        for box_ui, name, capital, x0, y0, x1, y1 in self.boxes.get(world_map, ()):
            if x0 <= x <= x1 and y0 <= y <= y1:
                mx, my = (y1 - y) / (y1 - y0), (x1 - x) / (x1 - x0)
                held.append((min(mx, 1 - mx, my, 1 - my), capital, box_ui, name, mx, my))
        pool = [h for h in held if h[2] == ui] or [h for h in held if h[1] and h[0] >= CITY_MARGIN] or held
        return max(pool)[2:] if pool else None


def hostile_to(player, npc):
    """FactionTemplateEntry::IsHostileTo of mangos: whether a creature of this template attacks that player."""
    if npc["ID"] == player["ID"]:
        return False
    faction = npc["Faction"]
    if faction != "0":
        if faction in [player[f"Enemies_{i}"] for i in range(8)]:
            return True
        if faction in [player[f"Friend_{i}"] for i in range(8)]:
            return False
    return int(player["EnemyGroup"]) & int(npc["FactionGroup"]) != 0


def generate(tables, sql):
    spell_names = {r["ID"]: r["Name_lang"] for r in rows(tables["SpellName"])}
    skill_names = {int(r["ID"]): r["DisplayName_lang"] for r in rows(tables["SkillLine"]) if int(r["ID"]) in PROFESSIONS}
    recipe_skill = {}
    skill_set = set(skill_names.values())
    for r in rows(tables["SkillLineAbility"]):
        line, spell = int(r["SkillLine"]), int(r["Spell"])
        if line in PROFESSIONS and r["AcquireMethod"] != "3":
            recipe_skill.setdefault(spell, line)
    recipe_names = {spell_names[str(s)] for s in recipe_skill if str(s) in spell_names}
    learns = {}
    for r in rows(tables["SpellEffect"]):
        if r["Effect"] == LEARN_SPELL and r["EffectTriggerSpell"] != "0":
            learns.setdefault(int(r["SpellID"]), int(r["EffectTriggerSpell"]))

    templates = {r["ID"]: r for r in rows(tables["FactionTemplate"])}
    players = {side: templates[tid] for side, tid in PLAYER_TEMPLATES.items()}
    maps = Maps(tables)
    reagents = reagent_items() | SKILL_BOOKS

    spawns = {}
    for c in sorted(records(sql["creature"]), key=lambda c: c["guid"]):
        spawns.setdefault(c["id"], []).append(c)

    trainer_spells, vendor_items = {}, {}
    for table, key, store in (("npc_trainer", "spell", trainer_spells), ("npc_trainer_template", "spell", trainer_spells),
                              ("npc_vendor", "item", vendor_items), ("npc_vendor_template", "item", vendor_items)):
        for r in records(sql[table]):
            store.setdefault((table.endswith("template"), r["entry"]), set()).add(r[key])

    # (from a template, entry) -> {(spell, skill needed to learn it)}, to tell which ranks a trainer teaches.
    trainer_reqs = {}
    for table in ("npc_trainer", "npc_trainer_template"):
        for r in records(sql[table]):
            trainer_reqs.setdefault((table.endswith("template"), r["entry"]), set()).add((r["spell"], r["reqskillvalue"]))

    recipe_items = {}
    for r in records(sql["item_template"]):
        if r["class"] == RECIPE_CLASS and ": " in r["name"]:
            name = r["name"].split(": ", 1)[1]
            if name in recipe_names:
                recipe_items[r["entry"]] = name

    out = {"trainers": {}, "bankers": {}, "vendors": {}, "artisan": {}}
    trainer_recipes = {}
    for t in records(sql["creature_template"]):
        flags = t["NpcFlags"]
        if not flags & (FLAG_TRAINER | FLAG_VENDOR | FLAG_BANKER) and t["Entry"] not in ARTISAN_NPCS:
            continue
        spot = next(filter(None, (maps.locate(s["map"], s["position_x"], s["position_y"], ZONE_FIX.get(t["Entry"])) for s in spawns.get(t["Entry"], ()))), None)
        if not spot:
            continue
        ui, zone, x, y = spot
        npc = templates.get(str(t["Faction"]))
        sides = {side: not (npc and hostile_to(p, npc)) for side, p in players.items()}
        entry = {"npc": t["Name"], "sub": t["SubName"], "zone": zone, "uiMap": ui, "x": x, "y": y,
                 "alliance": sides["alliance"], "horde": sides["horde"]}
        if not (sides["alliance"] or sides["horde"]):
            continue

        if t["Entry"] in ARTISAN_NPCS:
            out["artisan"][t["Entry"]] = dict(entry)
        if flags & FLAG_TRAINER:
            spells = trainer_spells.get((False, t["Entry"]), set()) | trainer_spells.get((True, t["TrainerTemplateId"]), set())
            taught = {learns.get(s, s) for s in spells}
            # A profession trainer teaches the profession itself (a spell named like it) and its recipes.
            skills = [n for n in (spell_names.get(str(s)) for s in taught) if n in skill_set]
            skills = skills or [skill_names[recipe_skill[s]] for s in taught if s in recipe_skill]
            if skills:
                entry["skill"] = max(set(skills), key=skills.count)
                # The spells named like the profession are its ranks; the skill each needs says which rank.
                reqs = trainer_reqs.get((False, t["Entry"]), set()) | trainer_reqs.get((True, t["TrainerTemplateId"]), set())
                entry["ranks"] = sorted({RANK_CAPS[need] for s, need in reqs
                                         if spell_names.get(str(learns.get(s, s))) == entry["skill"] and need in RANK_CAPS})
                out["trainers"][t["Entry"]] = entry
                for s in taught & recipe_skill.keys():
                    name = spell_names.get(str(s))
                    if name and name not in skill_set:
                        trainer_recipes.setdefault(name, set()).add(t["Entry"])
        if flags & FLAG_BANKER:
            out["bankers"][t["Entry"]] = dict(entry)
        if flags & FLAG_VENDOR:
            stock = vendor_items.get((False, t["Entry"]), set()) | vendor_items.get((True, t["VendorTemplateId"]), set())
            items = sorted(stock & reagents)
            recipes = sorted({recipe_items[i] for i in stock if i in recipe_items})
            if items or recipes:
                v = dict(entry)
                v["items"], v["recipes"] = items, recipes
                out["vendors"][t["Entry"]] = v
    return out, trainer_recipes


def lua_string(text):
    return '"' + re.sub(r'[\\"]', r"\\\g<0>", re.sub(r"[\x00-\x1f]", "", text)) + '"'


def entry_text(e):
    parts = []
    for k in ("npc", "sub", "skill", "zone"):
        if e.get(k):
            parts.append(f"{k} = {lua_string(e[k])}")
    parts += [f"uiMap = {e['uiMap']}", f"x = {e['x']:.4f}", f"y = {e['y']:.4f}"]
    for side in ("alliance", "horde"):
        if e[side]:
            parts.append(f"{side} = true")
    if e.get("ranks"):
        parts.append(f'ranks = ",{",".join(map(str, e["ranks"]))},"')
    if e.get("items"):
        parts.append(f'items = ",{",".join(map(str, e["items"]))},"')
    if e.get("recipes"):
        parts.append("recipes = { " + ", ".join(lua_string(n) for n in e["recipes"]) + " }")
    return "{ " + ", ".join(parts) + " }"


def render(out, trainer_recipes, build):
    lines = [
        "-- Generated by tools/gen_npcs.py - do not edit.",
        f"-- Spawns, trainer spell lists and vendor stock: {CLASSIC_DB} (GPL-3.0), commit {COMMIT}.",
        f"-- Spells, skills, factions and maps: wago.tools DB2 tables (product wowf, build {build}).",
        "local _, FP = ...",
        "",
        "FP.ClassicNpcs = {",
    ]
    for kind in ("trainers", "bankers", "vendors", "artisan"):
        lines.append(f"    {kind} = {{")
        for npc_id in sorted(out[kind]):
            lines.append(f"        [{npc_id}] = {entry_text(out[kind][npc_id])},")
        lines.append("    },")
    lines.append('    -- [recipe name] = "npcId,npcId"')
    lines.append("    trainerRecipes = {")
    for name in sorted(trainer_recipes):
        ids = ",".join(map(str, sorted(trainer_recipes[name])))
        lines.append(f'        [{lua_string(name)}] = "{ids}",')
    lines += ["    },", "}"]
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description="Generate Data/ClassicNpcs.lua from classic-db and wago.tools data.")
    parser.add_argument("--build", help="Forever build, such as 1.60.1.70888 (default: the newest)")
    parser.add_argument("--refresh", action="store_true", help="download the data again")
    args = parser.parse_args()
    if not RECIPES.exists():
        sys.exit("Data/Recipes.lua is missing; run tools/gen_recipes.py first")

    build = args.build or latest_build()
    tables = {t: cached_table(build, t, args.refresh) for t in WAGO_TABLES}
    download_dump(args.refresh)
    out, trainer_recipes = generate(tables, load_dump())
    text = render(out, trainer_recipes, build)
    old = TARGET.read_text(encoding="utf-8") if TARGET.exists() else ""
    TARGET.write_text(text, encoding="utf-8")
    print(f"build {build}: {len(out['trainers'])} trainers, {len(out['bankers'])} bankers, {len(out['vendors'])} vendors, "
          f"{len(trainer_recipes)} taught recipes, {len(text) // 1024} KB -> {TARGET}" + (" (unchanged)" if text == old else " (changed)"))


if __name__ == "__main__":
    main()
