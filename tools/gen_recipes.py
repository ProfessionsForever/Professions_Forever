#!/usr/bin/env python3
"""Writes Data/Recipes.lua: what the profession recipes need and make. That is the skill each needs to learn, the
item each makes (for its icon; a recipe's own spell icon is only the profession's), for each item the recipes
that use it as a reagent, the spells that open each profession's crafting window, and its specialization spells.

Downloads the DB2 tables it needs from wago.tools for the WoW: Forever build (product wowf), keeps them in a cache
folder (~/.cache/professionsforever/wago/<build>), and generates the file from them. Run it by hand when Forever
patches; it makes seven requests at most, and none once a build is cached. wago.tools publishes no data terms, so
leave the attribution in the generated file.

Usage: tools/gen_recipes.py [--build 1.60.1.70707] [--refresh]
    no --build   use the newest wowf build wago.tools lists
    --refresh    download the tables again even if cached
"""
import argparse
from pathlib import Path

import wago
from wago import cached_table, latest_build, rows

TABLES = ("SkillLineAbility", "SpellReagents", "SpellEffect", "ItemSparse", "ItemEffect", "ItemXItemEffect", "SpellName")
TARGET = Path(__file__).resolve().parent.parent / "Data" / "Recipes.lua"

# Skill lines of the professions this addon lists (Core/Professions.lua).
PROFESSIONS = {171, 164, 333, 202, 182, 773, 755, 165, 186, 393, 197, 129, 185, 356}
# The ones with no crafting window in Classic, so no opener is expected (Forever may give one, as Bait and Tackle).
GATHERING = {182, 393, 356}  # Herbalism, Skinning, Fishing
SLOTS = 8
# SpellEffect.Effect 24 creates an item.
CREATE_ITEM = "24"
# SpellEffect.Effect 47 opens a profession's crafting window (Trade Skill). Specializations (Gnomish Engineer,
# Weaponsmith, Dragonscale Leatherworking...) have it too, so an opener is a spell with it that is either a rank of the
# profession (it also has Effect 118, Skill) or learned with the profession (SkillLineAbility.AcquireMethod 1 or 2:
# Smelting, and Forever's Gardening, Tanning, Bait and Tackle). A specialization is neither, and every specialist
# knows a rank, so leaving them out loses no opener. Herbalism, Skinning and Fishing take only the second kind: their
# ranks share the profession's name, and /cast Fishing casts the line.
TRADE_SKILL = "47"
SKILL = "118"
LEARNED_WITH_LINE = {"1", "2"}
# ItemEffect.TriggerType 6 is the "learn" effect of a recipe item (pattern, plans, schematic).
LEARN_TRIGGER = "6"


wago.AGENT = "ProfessionsForever-recipe-generator (run by hand)"


def generate(tables, build):
    # Every recipe uses reagents. The skill lines also list spells that don't: the profession's rank and specialization
    # spells, gathering and Find spells, Disenchant, Fishing Poles and unnamed placeholders, which are not recipes.
    has_reagents = {int(r["SpellID"]) for r in rows(tables["SpellReagents"])}

    # recipe spell -> (skill line, skill needed to learn it)
    recipes = {}
    # recipe spell -> (skill where it turns yellow, skill where it turns grey); green is halfway between
    trivial = {}
    for r in rows(tables["SkillLineAbility"]):
        line, spell = int(r["SkillLine"]), int(r["Spell"])
        # AcquireMethod 3 is the use effect of crafted devices (dragonlings, Battle Chicken), not a recipe.
        if line in PROFESSIONS and r["AcquireMethod"] != "3" and spell in has_reagents and spell not in recipes:
            recipes[spell] = (line, int(r["MinSkillLineRank"] or 0))
            yellow, grey = int(r["TrivialSkillLineRankLow"] or 0), int(r["TrivialSkillLineRankHigh"] or 0)
            if grey > yellow:
                trivial[spell] = (yellow, grey)

    uses, seen = {}, set()
    for r in rows(tables["SpellReagents"]):
        spell = int(r["SpellID"])
        if spell not in recipes or spell in seen:
            continue
        seen.add(spell)
        line, _ = recipes[spell]
        for i in range(SLOTS):
            item, count = int(r[f"Reagent_{i}"] or 0), int(r[f"ReagentCount_{i}"] or 0)
            if item > 0 and count > 0:
                uses.setdefault(item, []).append((spell, count, line))

    # Every spell of a profession's skill line, to find the ones that open its window.
    line_of, auto = {}, set()
    for r in rows(tables["SkillLineAbility"]):
        line, spell = int(r["SkillLine"]), int(r["Spell"])
        if line in PROFESSIONS:
            line_of.setdefault(spell, line)
            if r["AcquireMethod"] in LEARNED_WITH_LINE:
                auto.add(spell)
    ranks = {int(r["SpellID"]) for r in rows(tables["SpellEffect"]) if r["Effect"] == SKILL}

    outputs, openers, specializations = {}, {}, {}
    for r in rows(tables["SpellEffect"]):
        spell = int(r["SpellID"])
        if spell in seen and spell not in outputs and r["Effect"] == CREATE_ITEM and int(r["EffectItemType"] or 0) > 0:
            outputs[spell] = int(r["EffectItemType"])
        if (r["Effect"] == TRADE_SKILL and spell in line_of and spell not in has_reagents
                and (spell in auto or (spell in ranks and line_of[spell] not in GATHERING))):
            openers.setdefault(line_of[spell], set()).add(spell)
        # What is left of the Trade Skill spells: Weaponsmith, Dragonscale Leatherworking, Gnomish Engineer...
        elif (r["Effect"] == TRADE_SKILL and spell in line_of and spell not in has_reagents
                and spell not in auto and spell not in ranks and line_of[spell] not in GATHERING):
            specializations.setdefault(line_of[spell], set()).add(spell)
    names = {int(r["ID"]): r["Name_lang"] for r in rows(tables["SpellName"])}

    # A recipe that is taught by an item needs the skill that item asks for; the earliest way to learn it counts.
    item_skill = {r["ID"]: int(r["RequiredSkillRank"] or 0) for r in rows(tables["ItemSparse"])}
    learn_effects = {}
    for r in rows(tables["ItemEffect"]):
        if r["TriggerType"] == LEARN_TRIGGER and int(r["SpellID"]) in recipes:
            learn_effects[r["ID"]] = int(r["SpellID"])
    need = {spell: rank for spell, (_, rank) in recipes.items() if rank > 1}
    for r in rows(tables["ItemXItemEffect"]):
        spell = learn_effects.get(r["ItemEffectID"])
        rank = item_skill.get(r["ItemID"], 0)
        if spell and rank > 1:
            need[spell] = min(need.get(spell, rank), rank)

    lines = [
        f"-- Generated by tools/gen_recipes.py from wago.tools DB2 tables (product wowf, build {build}). Do not edit.",
        "local _, FP = ...",
        "",
        "-- [recipe spell ID] = item ID the recipe makes (enchants and the like make none)",
        "FP.RecipeOutputs = {",
    ]
    for spell in sorted(outputs):
        lines.append(f"    [{spell}] = {outputs[spell]},")
    lines += [
        "}",
        "",
        "-- [recipe spell ID] = skill needed to learn it, from its recipe item or skill line, for the recipes that need more than the starting skill",
        "FP.RecipeMinSkill = {",
    ]
    for spell in sorted(need):
        lines.append(f"    [{spell}] = {need[spell]},")
    for name, index, what in (("RecipeYellow", 0, "yellow"), ("RecipeGrey", 1, "grey")):
        lines += [
            "}",
            "",
            f"-- [recipe spell ID] = skill where the recipe turns {what}; between the two it can still give a skill up",
            f"FP.{name} = {{",
        ]
        for spell in sorted(trivial):
            lines.append(f"    [{spell}] = {trivial[spell][index]},")
    by_line = {}
    for spell, (line, _) in recipes.items():
        by_line.setdefault(line, []).append(spell)
    lines += [
        "}",
        "",
        "-- [skill line ID] = \"recipe spell ID,...\": every recipe of the profession, learned or not",
        "FP.RecipeLines = {",
    ]
    for line in sorted(by_line):
        lines.append(f"    [{line}] = \"{','.join(map(str, sorted(by_line[line])))}\",")
    lines += [
        "}",
        "",
        "-- [skill line ID] = { spell ID, ... }: the spells that open the profession's crafting window, every rank",
        "-- (UI/ProfessionOpener.lua casts one the character knows)",
        "FP.ProfessionOpeners = {",
    ]
    for line in sorted(openers):
        spells = sorted(openers[line])
        label = ", ".join(sorted({" ".join(names.get(s, "?").split()) for s in spells}))
        lines.append(f"    [{line}] = {{ {', '.join(map(str, spells))} }}, -- {label}")
    lines += [
        "}",
        "",
        "-- [skill line ID] = { spell ID, ... }: the profession's specialization spells, in ID order, so a specialization",
        "-- that builds on another (Master Swordsmith on Weaponsmith) comes after it",
        "FP.Specializations = {",
    ]
    for line in sorted(specializations):
        spells = sorted(specializations[line])
        label = ", ".join(" ".join(names.get(s, "?").split()) for s in spells)
        lines.append(f"    [{line}] = {{ {', '.join(map(str, spells))} }}, -- {label}")
    lines += [
        "}",
        "",
        "-- [reagent item ID] = \"recipe spell ID,count,skill line ID;...\"",
        "FP.ReagentUses = {",
    ]
    for item in sorted(uses):
        entries = ";".join(",".join(map(str, e)) for e in sorted(uses[item]))
        lines.append(f"    [{item}] = \"{entries}\",")
    lines.append("}")

    # Worth a look before shipping: a crafting profession with no opener can't be opened from the addon's tabs, and
    # one whose ranks go by more than one name has something besides its ranks among them.
    notes = []
    for line in sorted(PROFESSIONS - GATHERING):
        if line in by_line and line not in openers:
            notes.append(f"no opener for skill line {line}: its tab will fall back to C_TradeSkillUI.OpenTradeSkill")
    for line, spells in sorted(openers.items()):
        distinct = sorted({names.get(s, "?") for s in spells if s in ranks})
        if len(distinct) > 1:
            notes.append(f"skill line {line} has openers with different names, check them: {', '.join(distinct)}")
    return "\n".join(lines) + "\n", len(seen), len(uses), notes


def main():
    parser = argparse.ArgumentParser(description="Generate Data/Recipes.lua from wago.tools data.")
    parser.add_argument("--build", help="Forever build, such as 1.60.1.70707 (default: the newest)")
    parser.add_argument("--refresh", action="store_true", help="download the tables again")
    args = parser.parse_args()

    build = args.build or latest_build()
    tables = {t: cached_table(build, t, args.refresh) for t in TABLES}
    text, recipes, reagents, notes = generate(tables, build)
    old = TARGET.read_text(encoding="utf-8") if TARGET.exists() else ""
    TARGET.parent.mkdir(exist_ok=True)
    TARGET.write_text(text, encoding="utf-8")
    print(f"build {build}: {recipes} recipes, {reagents} reagents, {len(text) // 1024} KB -> {TARGET}"
          + (" (unchanged)" if text == old else " (changed)"))
    for note in notes:
        print("  check: " + note)


if __name__ == "__main__":
    main()
