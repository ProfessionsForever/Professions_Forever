"""Where each recipe is learned from, by recipe spell ID, for tools/gen_npcs.py, which writes it as Data/RecipeSources.lua
beside the NPCs those sources name. Not run by itself.

Every source is a (kind, id) pair with the code of the best source that has it. Sources in priority order:

    p  a player's recording on a Forever build (none are merged yet)
    w  the Forever client (wago.tools, product wowf)
    t  QuestieDB Forever, traced in game by players
    q  QuestieDB Forever, its base and generated Forever delta
    f  forever-db, a merge of open databases (it does not say which of them has a given vendor or drop)
    d  ForeverTDB, rows seen on a Forever build
    c  cmangos classic-db: a 1.12 fact, not confirmed in Forever

Kinds: T trainer, V vendor, L vendor with a limited supply, D creature drop, O object (chest, node), Q quest reward.

QuestieDB (Questie/QuestieDB) and forever-db (foreverfraddons/forever-db) are pinned to one commit each and cached in
~/.cache/professionsforever. Recipe items are joined to recipe spells by ID with the Forever client's item effects.
"""
import re

from wago import CACHE, fetch, rows

QUESTIE = "Questie/QuestieDB"
QUESTIE_COMMIT = "4f628e8328ed8923ffba169c8b432996e0a7a326"
QUESTIE_BASE = "data/Forever/foreverItemDB.lua"
# Applied over the base in this order, as QuestieDB does: its generated Forever delta, its hand-written fixes, traces.
QUESTIE_DELTAS = ("src/corrections/Forever/generated/foreverBaseItem.lua", "src/corrections/Forever/foreverItemFixes.lua")
QUESTIE_DUNGEONS = "support/Forever/Zones/dungeons.lua"  # where each dungeon's entrance is, in Forever percentages
QUESTIE_TRACES = "src/corrections/Forever/traces/foreverItemTraces.lua"
# QuestieDB.itemKeys: the field of an item's entry -> the kind of source it lists.
QUESTIE_FIELDS = {"npcDrops": "D", "objectDrops": "O", "questRewards": "Q", "vendors": "V"}
QUESTIE_INDEX = {"npcDrops": 2, "objectDrops": 3, "questRewards": 6, "vendors": 14}

FOREVER_DB = "foreverfraddons/forever-db"
FOREVER_DB_COMMIT = "7cbe0ad546f82b45cc8849534f829b9ce4e1446c"
FOREVER_DB_FILES = ("ForeverDB/ForeverDB.lua", "ForeverDB/ForeverDB_3.lua", "ForeverDB_Full/ForeverDB_Full.lua",
                    "ForeverDB_Full/ForeverDB_Full_2.lua", "ForeverDB_Full/ForeverDB_Full_3.lua",
                    "ForeverDB_Full/ForeverDB_Full_4.lua", "ForeverDB_Full/ForeverDB_Full_5.lua")
# Its tables read here: vendors, creature drops, object drops and quest rewards per item; an NPC's name, the side it is
# friendly to and its spots on Forever's maps (uiMap -> x, y, ... in thousandths); a quest's name and levels, who gives
# it ("c" creature or "o" object, then the id) and who may take it; an object's name.
FOREVER_DB_TABLES = {"vend": "V", "drop": "D", "odrop": "O", "rew": "Q", "npc": None, "nfac": None, "spz": None,
                     "quest": None, "qg": None, "qx": None, "obj": None}
# A quest's first qx value: the side in the high 32 bits (1 Alliance, 2 Horde, 0 by race), the races in the low ones.
ALLIANCE_RACES, HORDE_RACES = 77, 178

TABLES = ("SkillLineAbility", "SpellReagents", "SpellEffect", "ItemEffect", "ItemXItemEffect")
LEARN_TRIGGER = "6"  # ItemEffect.TriggerType of a recipe item's "learn" effect
CREATE_ITEM = "24"   # SpellEffect.Effect that makes an item
PRIORITY = "pwtqfdc"
KINDS = "TVLDOQ"
MOST = 10  # creatures or objects listed for one recipe, the likeliest first: a world drop has hundreds

LUA_TOKEN = re.compile(r"""\s*(?:(-?\d+(?:\.\d+)?)|'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)"|(nil|true|false)|\[(-?\d+)\]\s*=|([{},]))""")


def cached_file(repo, commit, path):
    """A file of a GitHub repository at a pinned commit, downloaded once."""
    target = CACHE.parent / repo.split("/")[1].lower() / commit / path.rsplit("/", 1)[-1]
    if not target.exists():
        print(f"downloading {path} ({repo} {commit[:8]})")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(fetch(f"https://raw.githubusercontent.com/{repo}/{commit}/{path}"))
    return target


def lua_value(text):
    """A Lua literal as Python: a table with [n] = keys becomes a dict, any other a list."""
    tokens = LUA_TOKEN.finditer(text)

    def value(m):
        number, single, double, word, _, punct = m.groups()
        if number is not None:
            return float(number) if "." in number else int(number)
        if word:
            return {"nil": None, "true": True, "false": False}[word]
        if punct != "{":
            return re.sub(r"\\(.)", r"\1", single if single is not None else double)
        items, keyed = [], {}
        for m in tokens:
            if m.group(6) == "}":
                break
            if m.group(6) == ",":
                continue
            if m.group(5) is not None:
                keyed[int(m.group(5))] = value(next(tokens))
            else:
                items.append(value(m))
        return keyed or items

    return value(next(tokens))


def recipes(tables):
    """{recipe spell: skill line} of the professions' recipes, as tools/gen_recipes.py picks them."""
    from gen_recipes import PROFESSIONS
    has_reagents = {int(r["SpellID"]) for r in rows(tables["SpellReagents"])}
    out = {}
    for r in rows(tables["SkillLineAbility"]):
        line, spell = int(r["SkillLine"]), int(r["Spell"])
        if line in PROFESSIONS and r["AcquireMethod"] != "3" and spell in has_reagents:
            out.setdefault(spell, line)
    return out


def recipe_items(tables, recipe_spells):
    """{item: recipe spell} of the patterns, plans and the like that teach a recipe in the Forever client."""
    effects = {r["ID"]: int(r["SpellID"]) for r in rows(tables["ItemEffect"])
               if r["TriggerType"] == LEARN_TRIGGER and int(r["SpellID"]) in recipe_spells}
    return {int(r["ItemID"]): effects[r["ItemEffectID"]] for r in rows(tables["ItemXItemEffect"]) if r["ItemEffectID"] in effects}


# Season of Discovery's Supply Officers, carried over in QuestieDB's base and forever-db with the recipes they sold
# there. Forever's own Supply Officers have their own ids (256384, 256389), stand elsewhere and sell no recipes
# (Tamelyn Aldridge seen in game, 2026-11-21: Redridge Mountains, three Merchant's Favor items).
SOD_SUPPLY_OFFICERS = {213077, 214070, 214096, 214098, 214099, 214101}


class Sources:
    """{recipe spell: {kind: {id: source code}}}: each source keeps the code of the best source that has it."""

    def __init__(self):
        self.by_spell = {}
        self.order = {}     # (spell, kind, id) -> how likely the source is, for the ones that say
        self.limited = set()  # (spell, vendor) whose supply of the recipe is limited

    def add(self, spell, kind, source_id, code, chance=0):
        if kind in "VLD" and source_id in SOD_SUPPLY_OFFICERS:
            return
        if kind == "L":
            kind = "V"
            self.limited.add((spell, source_id))
        ids = self.by_spell.setdefault(spell, {}).setdefault(kind, {})
        ids[source_id] = min(code, ids.get(source_id, code), key=PRIORITY.index)
        key = (spell, kind, source_id)
        self.order[key] = max(self.order.get(key, 0), chance)

    def text(self, spell):
        """"Tc:514,957;Td:257003;Vq:3413": per kind and source code, the ids."""
        parts = []
        for kind in KINDS:
            ids = self.by_spell[spell].get("V" if kind == "L" else kind, {})
            listed = sorted(ids, key=lambda i: (-self.order[spell, kind, i], PRIORITY.index(ids[i]), i)) if kind in "DO" else list(ids)
            if kind == "D":  # forever-db also lists a vendor as dropping what it sells
                listed = [i for i in listed if i not in self.by_spell[spell].get("V", {})]
            if kind in "DO":
                listed = listed[:MOST]
            elif kind in "VL":
                listed = [i for i in listed if ((spell, i) in self.limited) == (kind == "L")]
            for code in PRIORITY:
                group = sorted(i for i in listed if ids[i] == code)
                if group:
                    parts.append(f"{kind}{code}:{','.join(map(str, group))}")
        return ";".join(parts)


def questie(item_spell, sources):
    """Adds what QuestieDB's Forever data lists for the recipe items; returns how many sources it gave."""
    lists = {}  # (item, field) -> ids
    with open(cached_file(QUESTIE, QUESTIE_COMMIT, QUESTIE_BASE), encoding="utf-8") as f:
        for line in f:
            m = re.match(r"\[(\d+)\] = (\{.*\}),$", line)
            if m and int(m.group(1)) in item_spell:
                entry = lua_value(m.group(2))
                for field, index in QUESTIE_INDEX.items():
                    if index <= len(entry) and entry[index - 1]:
                        lists[int(m.group(1)), field] = set(entry[index - 1])

    def changes(path):
        text = cached_file(QUESTIE, QUESTIE_COMMIT, path).read_text(encoding="utf-8")
        for block in re.finditer(r"^        \[(\d+)\] = \{(.*?)^        \},", text, re.M | re.S):
            item = int(block.group(1))
            if item in item_spell:
                for m in re.finditer(r"\[itemKeys\.(\w+?)(_add|_remove)?\] = \{([\d, ]*)\}", block.group(2)):
                    if m.group(1) in QUESTIE_FIELDS:
                        yield item, m.group(1), m.group(2), {int(i) for i in re.findall(r"\d+", m.group(3))}

    for path in QUESTIE_DELTAS:
        for item, field, how, ids in changes(path):
            old = lists.get((item, field), set())
            lists[item, field] = old | ids if how == "_add" else old - ids if how == "_remove" else ids
    traced = set()
    for item, field, _, ids in changes(QUESTIE_TRACES):
        lists[item, field] = lists.get((item, field), set()) | ids
        traced |= {(item, field, i) for i in ids}
    count = 0
    for (item, field), ids in lists.items():
        for source_id in ids:
            sources.add(item_spell[item], QUESTIE_FIELDS[field], source_id, "t" if (item, field, source_id) in traced else "q")
            count += 1
    return count


def dungeon_doors():
    """QuestieDB's dungeon entrances: [(the dungeon's area ID, its name, its other area IDs, the zone's area ID, x, y)],
    x and y in hundredths of the zone's map. The first entrance of each; a battleground's depends on the side and is left out."""
    text = open(cached_file(QUESTIE, QUESTIE_COMMIT, QUESTIE_DUNGEONS), encoding="utf-8").read()
    entry = re.compile(r'^\s*\[(\d+)\] = \{"([^"]*)",(?:nil|\{([\d,]*)\}),\d+,\{\{(\d+), ?([\d.]+), ?([\d.]+)\}', re.M)
    return [(int(m[1]), m[2], [int(a) for a in (m[3] or "").split(",") if a], int(m[4]), float(m[5]), float(m[6]))
            for m in entry.finditer(text)]


class ForeverDB:
    """forever-db's tables as { table: { key: the Lua text of its value } }, parsed when asked for."""

    def __init__(self, tables=FOREVER_DB_TABLES):
        self.raw = {t: {} for t in tables}
        for path in FOREVER_DB_FILES:
            current = None
            with open(cached_file(FOREVER_DB, FOREVER_DB_COMMIT, path), encoding="utf-8") as f:
                for line in f:
                    if line.startswith("D."):
                        current = self.raw.get(line[2:line.index(" ")])
                    elif current is not None and line.startswith("t["):
                        key, value = line[2:].split("]=", 1)
                        current[key.strip('"')] = value
        self.count = 0

    def get(self, table, key):
        raw = self.raw[table].get(str(key))
        return lua_value(raw) if raw else None

    def add(self, item_spell, sources):
        for table, kind in FOREVER_DB_TABLES.items():
            for item, spell in item_spell.items() if kind else ():
                ids = self.get(table, item) or []
                # A drop table lists each source with its chance in ten-thousandths.
                pairs = zip(ids[::2], ids[1::2]) if kind in "DO" else ((i, 0) for i in ids)
                for source_id, chance in pairs:
                    sources.add(spell, kind, source_id, "f", chance)
                    self.count += 1

    def npc(self, npc_id, zones):
        """An NPC's entry for Data/ClassicNpcs.lua on the first zone map it has a spot on, or None."""
        name, side, spots = self.get("npc", npc_id), self.get("nfac", npc_id), self.get("spz", f"c{npc_id}")
        for ui in sorted(spots or {}):
            if name and side and ui in zones:
                return {"npc": name[0], "sub": name[1], "zone": zones[ui], "uiMap": ui, "x": spots[ui][0] / 1000,
                        "y": spots[ui][1] / 1000, "alliance": "A" in side, "horde": "H" in side}

    def dropper(self, source_id, is_object, zones):
        """A creature that drops a recipe or an object that holds one: its name, the sides it is friendly to ("A",
        "H", "AH" or ""), and a spot (ui map, x, y in thousandths) on each zone map it stands on. No spot in a dungeon."""
        name = self.get("obj" if is_object else "npc", source_id)
        side = "" if is_object else self.get("nfac", source_id) or ""
        spots = self.get("spz", f"{'o' if is_object else 'c'}{source_id}") or {}
        return name[0], side, [(ui, spots[ui][0], spots[ui][1]) for ui in sorted(spots) if ui in zones and spots[ui]]

    def quest(self, quest_id, zones):
        """A quest's entry for FP.RecipeQuests on the first zone map a giver of it has a spot on, or None: its name,
        the level it asks, the sides that may take it, and who gives it where. A quest an item starts has no place."""
        info, extra = self.get("quest", quest_id), self.get("qx", quest_id)
        who = extra[0] if extra and isinstance(extra[0], int) else 0
        side, races = who >> 32, who & 0xffffffff
        for giver in self.get("qg", quest_id) or ():
            name = giver[0] in "co" and self.get("npc" if giver[0] == "c" else "obj", giver[1:])
            spots = self.get("spz", giver) or {}
            for ui in sorted(spots):
                if info and name and ui in zones:
                    return {"quest": info[0], "level": info[2], "npc": name[0], "zone": zones[ui], "uiMap": ui,
                            "x": spots[ui][0] / 1000, "y": spots[ui][1] / 1000,
                            "alliance": side == 1 or side == 0 and (not races or bool(races & ALLIANCE_RACES)),
                            "horde": side == 2 or side == 0 and (not races or bool(races & HORDE_RACES))}


def tags(tables, recipe_spells, classic_spells, classic_learn, forever_learn):
    """{recipe spell: "N" for one new in Forever, or "C" and what changed since 1.12: r reagents, o the item it makes,
    s the skill a trainer asks, c what a trainer charges}. A 1.12 recipe that is the same has none. The skill and cost
    count as changed only where a Forever build's value is none of the ones 1.12's trainers have."""
    reagents, outputs = {}, {}
    for r in rows(tables["SpellReagents"]):
        spell = int(r["SpellID"])
        if spell in recipe_spells and spell not in reagents:
            pairs = ((int(r[f"Reagent_{i}"] or 0), int(r[f"ReagentCount_{i}"] or 0)) for i in range(8))
            reagents[spell] = {p for p in pairs if p[0] > 0 and p[1] > 0}
    for r in rows(tables["SpellEffect"]):
        spell = int(r["SpellID"])
        if spell in recipe_spells and r["Effect"] == CREATE_ITEM and int(r["EffectItemType"] or 0) > 0:
            outputs.setdefault(spell, int(r["EffectItemType"]))
    out = {}
    for spell in recipe_spells:
        old = classic_spells.get(spell)
        if not old:
            out[spell] = "N"
            continue
        was = {(old[f"Reagent{i}"], old[f"ReagentCount{i}"]) for i in range(1, 9) if old[f"Reagent{i}"] > 0 and old[f"ReagentCount{i}"] > 0}
        made = next((old[f"EffectItemType{i}"] for i in "123" if old[f"Effect{i}"] == int(CREATE_ITEM) and old[f"EffectItemType{i}"] > 0), None)
        changed = "r" if was != reagents.get(spell, set()) else ""
        changed += "o" if made != outputs.get(spell) else ""
        now, then = forever_learn.get(spell), classic_learn.get(spell)
        if now and then:
            changed += "s" if now[0] not in {skill for skill, _ in then} else ""
            changed += "c" if now[1] not in {cost for _, cost in then} else ""
        if changed:
            out[spell] = "C" + changed
    return out


def render(sources, tagged, item_spell, build, credits):
    lines = [
        "-- Generated by tools/gen_npcs.py (tools/recipe_sources.py) - do not edit.",
        *credits,
        f"-- Recipes, reagents and recipe items: wago.tools DB2 tables (product wowf, build {build}).",
        "local _, FP = ...",
        "",
        "-- [recipe spell ID] = \"<kind><source>:id,id;...\": who or what the recipe is learned from.",
        "-- Kinds: T trainer, V vendor, L vendor with a limited supply, D creature that drops its recipe item (the "
        f"likeliest {MOST}),",
        f"-- O object that holds it (the likeliest {MOST}), Q quest that rewards it. T, V, L and D are NPC ids.",
        "-- Sources: t QuestieDB Forever (traced in game), q QuestieDB Forever (base), f forever-db, d ForeverTDB (seen on a",
        "-- Forever build), c classic-db (1.12, not confirmed in Forever). Each id is under the best source that has it.",
        "FP.RecipeSources = {",
    ]
    for spell in sorted(sources.by_spell):
        lines.append(f'    [{spell}] = "{sources.text(spell)}",')
    lines += [
        "}",
        "",
        "-- [recipe spell ID] = \"N\" new in Forever (not in 1.12), or \"C\" changed in Forever and what changed: r reagents,",
        "-- o the item it makes, s the skill a trainer asks, c what a trainer charges. A 1.12 recipe that is the same has none.",
        "FP.RecipeForever = {",
    ]
    for spell in sorted(tagged):
        lines.append(f'    [{spell}] = "{tagged[spell]}",')
    lines += [
        "}",
        "",
        "-- [recipe item ID] = recipe spell ID it teaches: the patterns, plans and the like in a vendor's stock",
        "FP.RecipeItems = {",
    ]
    for item in sorted(item_spell):
        lines.append(f"    [{item}] = {item_spell[item]},")
    lines.append("}")
    return "\n".join(lines) + "\n"
