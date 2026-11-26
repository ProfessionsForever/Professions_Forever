#!/usr/bin/env python3
"""Writes Data/ClassicNpcs.lua: where the profession trainers, bankers and vendors stand, for players without
Questie, with the reagents the vendors sell and what a trainer asks to teach a recipe. It also writes
Data/RecipeSources.lua: who teaches, sells, drops or rewards each recipe, by recipe spell ID, and which recipes are
new or changed in Forever (tools/recipe_sources.py, which names the other sources read for it).

Spawns, trainers' spell lists, the 1.12 teaching spells and vendors' stock come from cmangos/classic-db (GPL-3.0),
pinned to one commit and cached in ~/.cache/professionsforever/classic-db. A trainer inside a dungeon is placed at
that dungeon's entrance. Trainer rows seen on a Forever build come from ForeverTDB (advocaite/TrinityCore, GPL-2.0 or later),
pinned to one release and cached in ~/.cache/professionsforever/forever-tdb (bsdtar unpacks it): the trainers
classic-db lacks with what they teach, and the skill and cost to learn a recipe, which win over 1.12's. Its rows
without a Forever build are its 1.12 base, which duplicates classic-db, and are not read. Spell names, skill, faction and map data come from the wago.tools
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
import subprocess
import sys
from pathlib import Path

import recipe_sources
import wago
from gen_recipes import PROFESSIONS
from wago import CACHE, cached_table, fetch, latest_build, rows

wago.AGENT = "ProfessionsForever-npc-generator (run by hand)"

CLASSIC_DB = "cmangos/classic-db"
COMMIT = "c33f90b8eeb3f8bacb53d5cbfee45075c80b416c"
DUMP = "Full_DB/ClassicDB_1_12_1_z2815.sql.gz"
DUMP_CACHE = CACHE.parent / "classic-db" / COMMIT / "ClassicDB.sql.gz"
TDB = "advocaite/TrinityCore"
TDB_TAG = "forever-tdb-2026-10-14"
TDB_ASSET = "TDB_full_forever_2026_10_14.7z"
TDB_SQL = "TDB_full_world_forever_2026_10_14.sql"
TDB_CACHE = CACHE.parent / "forever-tdb" / TDB_TAG.removeprefix("forever-tdb-") / TDB_SQL
ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / "Data" / "ClassicNpcs.lua"
SOURCES = ROOT / "Data" / "RecipeSources.lua"
RECIPES = ROOT / "Data" / "Recipes.lua"

WAGO_TABLES = ("UiMap", "UiMapAssignment", "FactionTemplate", "SkillLine", "SkillLineAbility", "SpellName", "AreaTable", "Map",
               *recipe_sources.TABLES)
SQL_TABLES = ("creature", "creature_template", "npc_trainer", "npc_trainer_template", "npc_vendor",
              "npc_vendor_template", "item_template", "disenchant_loot_template", "spell_template", "areatrigger_teleport", "gameobject")

TDB_TABLES = ("trainer_spell", "creature_trainer", "creature", "creature_template", "gameobject")
FOREVER_BUILDS = 70000  # a ForeverTDB row's VerifiedBuild from here up was seen on a Forever client (1.60.1.70124, ...)

FLAG_VENDOR, FLAG_TRAINER, FLAG_BANKER = 0x4, 0x10, 0x100  # UNIT_NPC_FLAG_* of the 1.12 client
# spell_template effect 36 learns a spell: most trainer rows are such 1.12 teaching spells ("Journeyman Mining",
# "Smelt Thorium"). Forever's client no longer has them, so they are decoded from the dump.
LEARN_SPELL = 36
# Instance map -> (the areatrigger_teleport row that leaves it by its front door, the zone map that door is on), for
# Uldaman (Badlands) and Razorfen Downs (The Barrens): where a trainer inside that dungeon is placed.
DUNGEON_EXITS = {70: (288, 1418), 129: (444, 1413)}
# Mobs classic-db flags as trainers that teach nothing (Hillsbrad Tailor, Pyrewood Tailor).
NOT_TRAINERS = {2264, 3530}
ZONE_MAP = "3"     # UiMap.Type of a zone or a city
WORLD_MAP = "0"    # UiMap.System of the maps a player opens (1 is the flight map's copy)
CAPITAL_FLAG = 0x8  # AreaTable.Flags_0 of a capital city
CITY_MARGIN = 0.04  # a city's map counts for points at least this far (of the map's size) from its edge
# NPC id -> the zone map seen in game where the rule above picks a neighbor (Goldshire, Ironforge's edge, ...).
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


def download_tdb():
    if not TDB_CACHE.exists():
        print(f"downloading {TDB_ASSET} ({TDB_TAG})")
        archive = TDB_CACHE.with_name("tdb.7z")
        archive.parent.mkdir(parents=True, exist_ok=True)
        archive.write_bytes(fetch(f"https://github.com/{TDB}/releases/download/{TDB_TAG}/{TDB_ASSET}"))
        subprocess.run(["bsdtar", "-xf", archive, "-C", archive.parent, TDB_SQL], check=True)


def unescape(text):
    return re.sub(r"\\(.)|''", lambda m: "'" if m.group(0) == "''" else ESCAPES.get(m.group(1), m.group(1)), text)


def sql_rows(statement):
    """Yields each parenthesized row of an INSERT ... VALUES statement as a list of Python values."""
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


def load_dump(path, wanted):
    """Returns { table: (column names, rows) } for the wanted tables of a SQL dump."""
    columns, found, current = {}, {t: [] for t in wanted}, None
    with (gzip.open if path.suffix == ".gz" else open)(path, "rt", encoding="utf-8", errors="replace") as dump:
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
    return {t: (columns[t], found[t]) for t in wanted}


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
        zones = {r["ID"]: r["Name_lang"] for r in rows(tables["UiMap"]) if r["Type"] == ZONE_MAP and r["System"] == WORLD_MAP}
        self.zones = {int(ui): name for ui, name in zones.items()}
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
        """(ui map, zone name, map x, map y) of the point, or None. The art of neighboring zones overlaps, so a capital
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


def generate(tables, sql, tdb):
    spell_names = {r["ID"]: r["Name_lang"] for r in rows(tables["SpellName"])}
    skill_names = {int(r["ID"]): r["DisplayName_lang"] for r in rows(tables["SkillLine"]) if int(r["ID"]) in PROFESSIONS}
    recipe_skill = {}
    skill_set = set(skill_names.values())
    for r in rows(tables["SkillLineAbility"]):
        line, spell = int(r["SkillLine"]), int(r["Spell"])
        if line in PROFESSIONS and r["AcquireMethod"] != "3":
            recipe_skill.setdefault(spell, line)
    recipes = recipe_sources.recipes(tables)
    sources = recipe_sources.Sources()
    learns, classic_spells = {}, {}
    for r in records(sql["spell_template"]):
        if r["Id"] in recipes:
            classic_spells[r["Id"]] = r
        for i in "123":
            if r[f"Effect{i}"] == LEARN_SPELL and r[f"EffectTriggerSpell{i}"]:
                learns.setdefault(r["Id"], r[f"EffectTriggerSpell{i}"])
    teleports = {r["id"]: r for r in records(sql["areatrigger_teleport"])}
    exits = {instance: (teleports[trigger], ui) for instance, (trigger, ui) in DUNGEON_EXITS.items()}

    templates = {r["ID"]: r for r in rows(tables["FactionTemplate"])}
    players = {side: templates[tid] for side, tid in PLAYER_TEMPLATES.items()}
    maps = Maps(tables)
    reagents = reagent_items() | SKILL_BOOKS

    spawns = {}
    for c in sorted(records(sql["creature"]), key=lambda c: c["guid"]):
        spawns.setdefault(c["id"], []).append(c)

    # A 1.12 recipe item teaches through a teaching spell too: item -> recipe spell, joined by ID.
    item_recipe = {}
    for r in records(sql["item_template"]):
        for i in "12345":
            spell = learns.get(r[f"spellid_{i}"], r[f"spellid_{i}"])
            if r["class"] == RECIPE_CLASS and spell in recipes:
                item_recipe[r["entry"]] = spell

    # (from a template, entry) -> {item: whether its supply is limited}
    trainer_spells, vendor_items = {}, {}
    for table in ("npc_trainer", "npc_trainer_template"):
        for r in records(sql[table]):
            trainer_spells.setdefault((table.endswith("template"), r["entry"]), set()).add(r["spell"])
    for table in ("npc_vendor", "npc_vendor_template"):
        for r in records(sql[table]):
            vendor_items.setdefault((table.endswith("template"), r["entry"]), {})[r["item"]] = r["maxcount"] > 0
    stock_rows = [(item, limited) for stock in vendor_items.values() for item, limited in stock.items() if item in item_recipe]
    stats = {"classic recipes sold by a vendor": len({item_recipe[item] for item, _ in stock_rows}),
             "limited-supply rows": sum(limited for _, limited in stock_rows)}

    # (from a template, entry) -> {(spell, skill needed to learn it)}, to tell which ranks a trainer teaches.
    trainer_reqs = {}
    # recipe spell -> {(skill needed to learn it, cost in copper)} of 1.12's trainers
    classic_learn = {}
    for table in ("npc_trainer", "npc_trainer_template"):
        for r in records(sql[table]):
            trainer_reqs.setdefault((table.endswith("template"), r["entry"]), set()).add((r["spell"], r["reqskillvalue"]))
            spell = learns.get(r["spell"], r["spell"])
            if spell in recipes:
                classic_learn.setdefault(spell, set()).add((r["reqskillvalue"], r["spellcost"]))

    def sides_of(faction):
        npc = templates.get(str(faction))
        return {side: not (npc and hostile_to(p, npc)) for side, p in players.items()}

    # recipe spell -> the spell each of its 1.12 trainers only teaches to those who know it (0: to anyone)
    classic_spec = {}
    out = {"trainers": {}, "bankers": {}, "vendors": {}, "artisan": {}}
    for t in records(sql["creature_template"]):
        flags = t["NpcFlags"]
        if not flags & (FLAG_TRAINER | FLAG_VENDOR | FLAG_BANKER) and t["Entry"] not in ARTISAN_NPCS:
            continue
        spot = next(filter(None, (maps.locate(s["map"], s["position_x"], s["position_y"], ZONE_FIX.get(t["Entry"])) for s in spawns.get(t["Entry"], ()))), None)
        dungeon = None
        if not spot:
            dungeon = next((s["map"] for s in spawns.get(t["Entry"], ()) if s["map"] in exits), None)
            if not dungeon:
                continue
            door, door_ui = exits[dungeon]
            spot = maps.locate(door["target_map"], door["target_position_x"], door["target_position_y"], door_ui)
        ui, zone, x, y = spot
        sides = sides_of(t["Faction"])
        entry = {"npc": t["Name"], "sub": t["SubName"], "zone": zone, "uiMap": ui, "x": x, "y": y,
                 "alliance": sides["alliance"], "horde": sides["horde"], "dungeon": dungeon}
        if not (sides["alliance"] or sides["horde"]):
            continue

        if t["Entry"] in ARTISAN_NPCS:
            out["artisan"][t["Entry"]] = dict(entry)
        if flags & FLAG_TRAINER and t["Entry"] not in NOT_TRAINERS:
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
                for s in taught & recipes.keys():
                    sources.add(s, "T", t["Entry"], "c")
                    classic_spec.setdefault(s, set()).add(t["TrainerSpell"])
        if flags & FLAG_BANKER:
            out["bankers"][t["Entry"]] = dict(entry)
        if flags & FLAG_VENDOR:
            stock = vendor_items.get((True, t["VendorTemplateId"]), {}) | vendor_items.get((False, t["Entry"]), {})
            items = sorted(stock.keys() & reagents)
            sold = {item: limited for item, limited in stock.items() if item in item_recipe}
            if items or sold:
                v = dict(entry)
                v["items"] = items
                out["vendors"][t["Entry"]] = v
            for item, limited in sold.items():
                sources.add(item_recipe[item], "L" if limited else "V", t["Entry"], "c")

    # A limited supply counts for a vendor classic-db has no spawn for too (Super-Seller 680, Vendor-Tron 1000 in
    # Desolace), which the loop above skips: QuestieDB or forever-db may list and place it.
    for t in records(sql["creature_template"]):
        if t["NpcFlags"] & FLAG_VENDOR:
            stock = vendor_items.get((True, t["VendorTemplateId"]), {}) | vendor_items.get((False, t["Entry"]), {})
            for item, limited in stock.items():
                if limited and item in item_recipe:
                    sources.mark_limited(item_recipe[item], t["Entry"])

    # ForeverTDB: trainer list -> {recipe spell: (skill, cost)} of the rows seen on a Forever build.
    forever, forever_learn = {}, {}
    # recipe spell -> the specialization a trainer asks for it (Goblin Engineer): every 1.12 trainer of the recipe
    # teaches only its specialists, or a trainer list asks for the ability.
    known_specs = specializations()
    specs = {spell: next(iter(asked)) for spell, asked in classic_spec.items() if len(asked) == 1 and 0 not in asked}
    for r in records(tdb["trainer_spell"]):
        spell = r["SpellId"]
        if spell in recipes:
            specs.update({spell: r[f"ReqAbility{i}"] for i in "123" if r[f"ReqAbility{i}"] in known_specs})
        if r["VerifiedBuild"] >= FOREVER_BUILDS and spell in recipes:
            learn = forever.setdefault(r["TrainerId"], {})[spell] = (r["ReqSkillRank"], r["MoneyCost"])
            forever_learn[spell] = min(learn, forever_learn.get(spell, learn))
    # recipe spell -> (skill needed to learn it, cost in copper, seen on a Forever build); the lowest skill listed.
    trainer_learn = {spell: (*min(learn), False) for spell, learn in classic_learn.items()}
    trainer_learn.update({spell: (*learn, True) for spell, learn in forever_learn.items()})
    classic_npcs = {t["Entry"] for t in records(sql["creature_template"])}
    tdb_templates = {t["entry"]: t for t in records(tdb["creature_template"]) if t["npcflag"] & FLAG_TRAINER}
    tdb_spawns = {}
    for c in sorted(records(tdb["creature"]), key=lambda c: c["guid"]):
        if c["id"] in tdb_templates:
            tdb_spawns.setdefault(c["id"], []).append(c)
    for link in sorted(records(tdb["creature_trainer"]), key=lambda r: (r["CreatureID"], r["TrainerID"])):
        npc_id, taught = link["CreatureID"], forever.get(link["TrainerID"])
        # Only Forever's own trainers: which list a 1.12 NPC is tied to comes from the dump's 1.12 base.
        if not taught or npc_id in classic_npcs:
            continue
        if npc_id not in out["trainers"]:
            t = tdb_templates.get(npc_id)
            spot = next(filter(None, (maps.locate(s["map"], s["position_x"], s["position_y"]) for s in tdb_spawns.get(npc_id, ()))), None)
            sides = t and sides_of(t["faction"])
            if not spot or not (sides["alliance"] or sides["horde"]):
                continue
            lines = [recipes[s] for s in taught]
            out["trainers"][npc_id] = {"npc": t["name"], "sub": t["subname"], "skill": skill_names[max(set(lines), key=lines.count)],
                                       "zone": spot[1], "uiMap": spot[0], "x": spot[2], "y": spot[3],
                                       "alliance": sides["alliance"], "horde": sides["horde"]}
        for s in taught:
            sources.add(s, "T", npc_id, "d")

    # Forever's recipe items, and who sells, drops or rewards them.
    item_spell = recipe_sources.recipe_items(tables, recipes)
    stats["QuestieDB sources"] = recipe_sources.questie(item_spell, sources)
    forever_db = recipe_sources.ForeverDB()
    forever_db.add(item_spell, sources)
    stats["forever-db sources"] = forever_db.count
    # A vendor classic-db doesn't have selling a recipe or a reagent is placed from forever-db.
    for by_kind in sources.by_spell.values():
        for npc_id in by_kind.get("V", ()):
            entry = npc_id not in out["vendors"] and forever_db.npc(npc_id, maps.zones)
            if entry:
                out["vendors"][npc_id] = entry
    # Where each quest that rewards a recipe is given, from forever-db.
    quests = {}
    for by_kind in sources.by_spell.values():
        for quest_id in by_kind.get("Q", ()):
            entry = quest_id not in quests and forever_db.quest(quest_id, maps.zones)
            if entry:
                quests[quest_id] = entry
    stats["recipe quests placed"] = len(quests)
    # Who drops or holds each recipe, for the sources the file lists, from forever-db.
    # The dungeons, raids and battlegrounds each of them stands in, from the spawns of classic-db and ForeverTDB.
    instances = {int(r["ID"]): r["MapName_lang"] for r in rows(tables["Map"]) if r["InstanceType"] != "0"}
    inside = {"D": {}, "O": {}}
    for kind, table in (("D", "creature"), ("O", "gameobject")):
        for dump in (sql, tdb):
            for r in records(dump[table]):
                if r["map"] in instances:
                    inside[kind].setdefault(r["id"], set()).add(r["map"])
    droppers = {"D": {}, "O": {}}
    for spell in sources.by_spell:
        for part in sources.text(spell).split(";"):
            if part[:1] in droppers and ":" in part:
                for source_id in map(int, part.split(":")[1].split(",")):
                    if source_id not in droppers[part[0]]:
                        droppers[part[0]][source_id] = (*forever_db.dropper(source_id, part[0] == "O", maps.zones),
                                                         sorted(inside[part[0]].get(source_id, ())))
    stats["droppers"] = sum(len(d) for d in droppers.values())
    stats["droppers placed"] = sum(1 for d in droppers.values() for e in d.values() if e[2])
    stats["droppers in a dungeon"] = sum(1 for d in droppers.values() for e in d.values() if e[3])
    # Each of those dungeons, and its entrance on a zone map from QuestieDB: matched by the areas the client puts on
    # the instance's map, else by name.
    areas_on = {}
    for r in rows(tables["AreaTable"]):
        areas_on.setdefault(int(r["ContinentID"]), set()).add(int(r["ID"]))
    area_ui = {}
    for r in rows(tables["UiMapAssignment"]):
        if int(r["UiMapID"]) in maps.zones and r["AreaID"] != "0":
            area_ui.setdefault(int(r["AreaID"]), int(r["UiMapID"]))
    doors = [d for d in recipe_sources.dungeon_doors() if d[3] in area_ui]
    dungeons = {}
    for m in sorted({m for d in droppers.values() for e in d.values() for m in e[3]}):
        here = areas_on.get(m, set())
        door = next((d for d in doors if here & {d[0], *d[2]}), None) or next((d for d in doors if d[1] == instances[m]), None)
        dungeons[m] = {"name": instances[m], **({"uiMap": area_ui[door[3]], "x": door[4] / 100, "y": door[5] / 100} if door else {})}
    stats["dungeons with an entrance"] = sum(1 for d in dungeons.values() if "uiMap" in d)
    tagged = recipe_sources.tags(tables, recipes, classic_spells, classic_learn, forever_learn)
    stats.update({"recipes": len(recipes), "in 1.12": len(classic_spells), "with a source": len(sources.by_spell)})
    for kind in "TVDOQ":
        stats[f"with {kind}"] = sum(1 for by_kind in sources.by_spell.values() if by_kind.get(kind))
    stats.update({"new in Forever": sum(1 for t in tagged.values() if t == "N"), "changed in Forever": sum(1 for t in tagged.values() if t != "N")})
    stats["recipes asking a specialization"] = len(specs)
    return out, sources, trainer_learn, tagged, item_spell, quests, specs, (droppers, dungeons), stats


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
    if e.get("dungeon"):
        parts.append(f"dungeon = {e['dungeon']}")
    if e.get("ranks"):
        parts.append(f'ranks = ",{",".join(map(str, e["ranks"]))},"')
    if e.get("items"):
        parts.append(f'items = ",{",".join(map(str, e["items"]))},"')
    return "{ " + ", ".join(parts) + " }"


def credits():
    return [
        f"-- Trainers, vendors and their limited supplies: {CLASSIC_DB} (GPL-3.0), commit {COMMIT}.",
        f"-- Forever's own trainers, and the skill and cost to learn a recipe seen on a Forever build: {TDB} ForeverTDB (GPL-2.0 or later), release {TDB_TAG}.",
        f"-- Vendors, drops, objects and quest rewards: {recipe_sources.FOREVER_DB} (GPL-3.0), commit {recipe_sources.FOREVER_DB_COMMIT},",
        f"-- and QuestieDB ({recipe_sources.QUESTIE}, commit {recipe_sources.QUESTIE_COMMIT}; also the dungeon entrances), whose team allows copying under the",
        "-- GPLv3 terms. QuestieDB's data will be removed from this file on request.",
    ]


def render_learn(trainer_learn):
    lines = [
        "",
        "-- [recipe spell ID] = { skill needed to learn it from a trainer, cost in copper, true when seen on a Forever build (else 1.12's) }",
        "FP.RecipeTrainerLearn = {",
    ]
    for spell in sorted(trainer_learn):
        skill, cost, seen = trainer_learn[spell]
        lines.append(f"    [{spell}] = {{ {skill}, {cost}{', true' if seen else ''} }},")
    return "\n".join(lines + ["}"]) + "\n"


def render_quests(quests):
    lines = [
        "",
        "-- [quest ID] = the quest that rewards a recipe (a \"Q\" source above) and who gives it where: its name in English,",
        "-- the level it asks, the giver (npc, an NPC or an object) and the sides that may take it.",
        "FP.RecipeQuests = {",
    ]
    for quest_id in sorted(quests):
        e = quests[quest_id]
        lines.append(f"    [{quest_id}] = {{ quest = {lua_string(e['quest'])}, level = {e['level']}, {entry_text(e)[2:]},")
    return "\n".join(lines + ["}"]) + "\n"


def render_droppers(droppers, dungeons):
    lines = [
        "",
        "-- Who drops or holds the recipes above (their \"D\" and \"O\" sources): [ID] = \"name^the sides it is friendly to",
        "-- (A, H)^ui map:x:y;...;d36;...\": a spot on each zone map it stands on, in thousandths of the map, and each",
        "-- dungeon, raid or battleground it stands in (d and the instance's map ID, as GetInstanceInfo gives it).",
    ]
    for kind, table in (("D", "FP.DropCreatures"), ("O", "FP.DropObjects")):
        lines.append(f"{table} = {{")
        for source_id in sorted(droppers[kind]):
            name, side, spots, maps = droppers[kind][source_id]
            text = f"{name}^{side}^" + ";".join([f"{ui}:{x}:{y}" for ui, x, y in spots] + [f"d{m}" for m in maps])
            lines.append(f"    [{source_id}] = {lua_string(text)},")
        lines.append("}")
    lines += ["", "-- [instance map ID] = a dungeon, raid or battleground named above: its name in English, and where its entrance",
              "-- is on a zone map (none for a battleground)", "FP.Dungeons = {"]
    for m in sorted(dungeons):
        d = dungeons[m]
        door = f", uiMap = {d['uiMap']}, x = {d['x']:.4f}, y = {d['y']:.4f}" if "uiMap" in d else ""
        lines.append(f"    [{m}] = {{ name = {lua_string(d['name'])}{door} }},")
    lines.append("}")
    return "\n".join(lines) + "\n"


def specializations():
    """The specialization spells of every profession, from Data/Recipes.lua (FP.Specializations)."""
    block = RECIPES.read_text(encoding="utf-8").split("FP.Specializations = {")[1].split("\n}")[0]
    return {int(v) for line in block.splitlines() for v in re.findall(r"\d+", line.split("=", 1)[-1].split("--")[0])}


def render_specs(specs):
    lines = [
        "",
        "-- [recipe spell ID] = the specialization spell a character must know to learn the recipe (Goblin Engineer)",
        "FP.RecipeSpecialization = {",
    ]
    lines += [f"    [{spell}] = {specs[spell]}," for spell in sorted(specs)]
    return "\n".join(lines + ["}"]) + "\n"


def render(out, build):
    lines = [
        "-- Generated by tools/gen_npcs.py - do not edit.",
        f"-- Spawns, trainer spell lists and vendor stock: {CLASSIC_DB} (GPL-3.0), commit {COMMIT}.",
        f"-- Forever's own trainers: {TDB} ForeverTDB (GPL-2.0 or later), release {TDB_TAG}.",
        f"-- Forever's own recipe vendors: {recipe_sources.FOREVER_DB} (GPL-3.0), commit {recipe_sources.FOREVER_DB_COMMIT}.",
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
    lines.append("}")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description="Generate Data/ClassicNpcs.lua and Data/RecipeSources.lua.")
    parser.add_argument("--build", help="Forever build, such as 1.60.1.70888 (default: the newest)")
    parser.add_argument("--refresh", action="store_true", help="download the data again")
    args = parser.parse_args()
    if not RECIPES.exists():
        sys.exit("Data/Recipes.lua is missing; run tools/gen_recipes.py first")

    build = args.build or latest_build()
    tables = {t: cached_table(build, t, args.refresh) for t in WAGO_TABLES}
    download_dump(args.refresh)
    download_tdb()
    out, sources, trainer_learn, tagged, item_spell, quests, specs, droppers, stats = generate(tables, load_dump(DUMP_CACHE, SQL_TABLES), load_dump(TDB_CACHE, TDB_TABLES))
    print(f"build {build}: " + ", ".join(f"{v} {k}" for k, v in stats.items()))
    texts = {TARGET: render(out, build),
             SOURCES: recipe_sources.render(sources, tagged, item_spell, build, credits()) + render_learn(trainer_learn)
                      + render_quests(quests) + render_specs(specs) + render_droppers(*droppers)}
    for target, text in texts.items():
        old = target.read_text(encoding="utf-8") if target.exists() else ""
        target.write_text(text, encoding="utf-8")
        print(f"{len(text) // 1024} KB -> {target}" + (" (unchanged)" if text == old else " (changed)"))
    print(f"{len(out['trainers'])} trainers, {len(out['bankers'])} bankers, {len(out['vendors'])} vendors, {len(trainer_learn)} recipes "
          f"with learn skill and cost ({sum(1 for v in trainer_learn.values() if v[2])} from a Forever build)")


if __name__ == "__main__":
    main()
