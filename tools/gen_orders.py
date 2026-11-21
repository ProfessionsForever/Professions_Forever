#!/usr/bin/env python3
"""Writes Data/Orders.lua: Forever's Waylaid Crates and Craftsman's Writs, for the Crates and Writs window.

Crates, from the Forever client (wago.tools): a "Waylaid Crate: <tier> <kind>" item's use spell (Stock Crate) lists the
bundles that fill it, one per line of its description ("- $M3 Peacebloom": the item's name, with the quantity in the
spell's effect of that number). A crate's quality says which Sealed crate it becomes: a white or a green one.

Writs: a "Craftsman's Writ: <item>" item starts a quest (the client). What the quest asks for, the reputation it pays
(75, 125 or 200: its tier) and the customer who takes it come from forever-db (foreverfraddons/forever-db, a merge of
open databases, pinned in tools/recipe_sources.py), which has no customer for some writs.

Run it by hand when Forever patches.

Usage: tools/gen_orders.py [--build 1.60.1.70959] [--refresh]
    no --build   use the newest wowf build wago.tools lists
    --refresh    download the tables again even if cached
"""
import argparse
import csv
import re
from pathlib import Path

import wago
from recipe_sources import FOREVER_DB_COMMIT, ForeverDB
from wago import cached_table, latest_build, rows

TABLES = ("ItemSparse", "ItemEffect", "ItemXItemEffect", "SpellEffect", "SpellReagents", "Spell")
TARGET = Path(__file__).resolve().parent.parent / "Data" / "Orders.lua"

TIERS = ("Apprentice", "Journeyman", "Expert", "Artisan", "Elite")
REP_TIER = {75: 2, 125: 3, 200: 4}
SEALED = "Sealed %s Crate"
SEALED_WRIT = "Sealed %s's Writ"
BUNDLE = re.compile(r"-\s*\$M(\d)\s+(.+?)\s*(?:\|r)?\s*$")
# The two factions' camps: who takes Sealed crates (Inventory Intake) and who sells the Forged Delivery Receipt and
# the Forger's Quill (Uncertified Scribe). NPC IDs from forever-db.
CAMPS = {"Alliance": (256390, 256742), "Horde": (256386, 256672)}
RECEIPT, QUILL, CONTAINER, UNOPENED = "Forged Delivery Receipt", "Forger's Quill", "Notarized Shipping Container", "Waylaid Crate"

wago.AGENT = "ProfessionsForever-orders-generator (run by hand)"
csv.field_size_limit(10 ** 9)  # Spell's descriptions


def spot(db, key):
    """A creature's or object's first spot on a Forever map: (uiMap, x, y) as map fractions, or None."""
    spots = db.get("spz", key)
    for ui in sorted(spots or {}):
        return ui, spots[ui][0] / 1000, spots[ui][1] / 1000


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def generate(tables, build):
    items, by_name = {}, {}
    for r in rows(tables["ItemSparse"]):
        item = int(r["ID"])
        items[item] = r
        by_name.setdefault(r["Display_lang"], []).append(item)

    reagents = {int(r[f"Reagent_{i}"]) for r in rows(tables["SpellReagents"]) for i in range(8)}

    def one(name):
        """The item of that name; of two (Dark Iron Ore is also a quest item), the one some recipe uses."""
        ids = by_name.get(name, [])
        if len(ids) > 1:
            ids = [i for i in ids if i in reagents]
        if len(ids) != 1:
            raise SystemExit(f"{name}: {len(ids)} items have this name")
        return ids[0]

    effects = {r["ID"]: r for r in rows(tables["ItemEffect"])}
    use_spell = {}
    for r in rows(tables["ItemXItemEffect"]):
        effect = effects.get(r["ItemEffectID"])
        if effect:
            use_spell.setdefault(int(r["ItemID"]), int(effect["SpellID"]))

    crates = {i: r for i, r in items.items() if r["Display_lang"].startswith("Waylaid Crate: ")}
    spells = {use_spell[i] for i in crates}
    points = {}  # (spell, effect number as the description counts it) -> quantity
    for r in rows(tables["SpellEffect"]):
        if int(r["SpellID"]) in spells:
            points[int(r["SpellID"]), int(r["EffectIndex"]) + 1] = int(float(r["EffectBasePointsF"]))
    described = {int(r["ID"]): r["Description_lang"] for r in rows(tables["Spell"]) if int(r["ID"]) in spells}

    # Sealed crates by tier and quality (1 white, 2 green, 3 blue).
    sealed = {}
    for tier, word in enumerate(TIERS, 1):
        for item in by_name.get(SEALED % word, []):
            sealed[tier, int(items[item]["OverallQualityID"])] = item

    crate_lines = []
    for item in sorted(crates):
        name = crates[item]["Display_lang"]
        tier = next(t for t, word in enumerate(TIERS, 1) if word in name.split(": ", 1)[1].split())
        quality = int(crates[item]["OverallQualityID"])
        bundles = []
        for line in described[use_spell[item]].splitlines():
            m = BUNDLE.match(line.strip())
            if m:
                bundles.append(f"{one(m.group(2))}:{points[use_spell[item], int(m.group(1))]}")
        if not bundles:
            raise SystemExit(f"{name}: no bundles in its spell's description")
        crate_lines.append(f'    [{item}] = {{ {tier}, {sealed[tier, quality]}, "{",".join(bundles)}" }}, -- {name}')

    sealed_lines = [f"    [{item}] = {{ {tier}, {quality} }}, -- {SEALED % TIERS[tier - 1]}"
                    for (tier, quality), item in sorted(sealed.items(), key=lambda kv: kv[1])]

    db = ForeverDB(("quest", "qx", "qe", "npc", "obj", "spz"))
    writ_lines, placed = [], 0
    for item in sorted(i for i, r in items.items() if r["Display_lang"].startswith("Craftsman's Writ: ")):
        r = items[item]
        quest = int(r["StartQuestID"])
        detail = db.get("qx", quest)
        wanted = next(i for i in detail[9] if i != item)
        rep = detail[14][1]
        entry = f"{quest}, {wanted}, {REP_TIER[rep]}, {rep}"
        for ender in db.get("qe", quest) or ():
            at = spot(db, ender)
            who = db.get("npc" if ender[0] == "c" else "obj", ender[1:])
            if at and who:
                entry += f", {lua_string(who[0])}, {at[0]}, {at[1]:.3f}, {at[2]:.3f}"
                placed += 1
                break
        writ_lines.append(f"    [{item}] = {{ {entry} }}, -- {r['Display_lang']}")

    sealed_writs = [f"    [{one(SEALED_WRIT % word)}] = {tier}, -- {SEALED_WRIT % word}"
                    for tier, word in enumerate(TIERS[:4], 1)]

    camp_lines = []
    for faction, npcs in CAMPS.items():
        parts = []
        for npc in npcs:
            ui, x, y = spot(db, f"c{npc}")
            parts.append(f"{{ {npc}, {lua_string(db.get('npc', npc)[0])}, {ui}, {x:.3f}, {y:.3f} }}")
        camp_lines.append(f"    {faction} = {{ intake = {parts[0]}, scribe = {parts[1]} }},")

    lines = [
        f"-- Generated by tools/gen_orders.py from wago.tools DB2 tables (product wowf, build {build}) and forever-db",
        f"-- (github.com/foreverfraddons/forever-db, GPL-3.0, commit {FOREVER_DB_COMMIT[:8]}). Do not edit.",
        "local _, FP = ...",
        "",
        "-- [crate item ID] = { tier (1 Apprentice to 4 Artisan), the Sealed crate it becomes, the bundles that fill it",
        '-- as "item ID:quantity,..." (any one of them) }',
        "FP.Crates = {", *crate_lines, "}",
        "",
        "-- [Sealed crate item ID] = { tier (5 is Elite), quality (1 white, 2 green, 3 blue) }",
        "FP.SealedCrates = {", *sealed_lines, "}",
        "",
        "-- [writ item ID] = { its quest, the item it asks for, tier (2 Journeyman to 4 Artisan), reputation, then the",
        "-- customer where known: name, map, x, y }",
        "FP.Writs = {", *writ_lines, "}",
        "",
        "-- [sealed writ item ID] = tier; opening one gives a random writ of that tier.",
        "FP.SealedWrits = {", *sealed_writs, "}",
        "",
        "-- Each faction's camp: { NPC ID, name, map, x, y } of who takes Sealed crates and of the Uncertified Scribe.",
        "FP.OrderCamps = {", *camp_lines, "}",
        "",
        f"FP.OrderItems = {{ receipt = {one(RECEIPT)}, quill = {one(QUILL)}, container = {one(CONTAINER)}, "
        f"unopened = {one(UNOPENED)} }}",
    ]
    return "\n".join(lines) + "\n", len(crate_lines), len(writ_lines), placed


def main():
    parser = argparse.ArgumentParser(description="Generate Data/Orders.lua from wago.tools data and forever-db.")
    parser.add_argument("--build", help="Forever build, such as 1.60.1.70959 (default: the newest)")
    parser.add_argument("--refresh", action="store_true", help="download the tables again")
    args = parser.parse_args()

    build = args.build or latest_build()
    tables = {t: cached_table(build, t, args.refresh) for t in TABLES}
    text, crates, writs, placed = generate(tables, build)
    old = TARGET.read_text(encoding="utf-8") if TARGET.exists() else ""
    TARGET.write_text(text, encoding="utf-8")
    print(f"build {build}: {crates} crates, {writs} writs ({placed} with a customer) -> {TARGET}"
          + (" (unchanged)" if text == old else " (changed)"))


if __name__ == "__main__":
    main()
