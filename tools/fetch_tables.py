#!/usr/bin/env python3
"""Downloads every wago.tools DB2 table the generator scripts read, for one WoW: Forever build (product wowf), into
<out>/<build>/<Table>.csv, with a MANIFEST.json beside them (build, date, and each table's size and SHA-256).

The list of tables is taken from the generator scripts themselves, so it cannot drift from what they read. The tables
in EXTRA are not read by any generator yet; they are fetched to see what Forever's client holds (which skill a
gathering node needs, the Merchant's Favor currency, ...). One that wago.tools doesn't have is reported and skipped;
a table a generator needs that fails stops the run.

.github/workflows/wago-tables.yml runs this, because a GitHub runner can reach wago.tools where other machines can't.
By hand:

    python3 tools/fetch_tables.py [--build 1.60.1.70959] [--out DIR] [--extra Table ...] [--refresh]
    no --build   use the newest wowf build wago.tools lists
    no --out     the generators' own cache, ~/.cache/professionsforever/wago
"""
import argparse
import datetime
import hashlib
import json
import os
import sys
import time
from pathlib import Path

import gen_camp
import gen_cooldowns
import gen_disenchant
import gen_items  # reads ItemSparse; it keeps no table list of its own
import gen_npcs
import gen_recipes
import wago

REQUIRED = sorted({"ItemSparse", *gen_recipes.TABLES, *gen_camp.TABLES, *gen_cooldowns.TABLES, *gen_npcs.WAGO_TABLES,
                   *gen_disenchant.WAGO_TABLES})
EXTRA = ("CurrencyTypes", "GameObjects", "Item", "Lock", "Map")
PAUSE = 2  # seconds between downloads: wago.tools is a free service


def main():
    parser = argparse.ArgumentParser(description="Download the wago.tools tables the generators read.")
    parser.add_argument("--build", help="Forever build, such as 1.60.1.70959 (default: the newest)")
    parser.add_argument("--out", type=Path, help="folder to download into (default: the generators' cache)")
    parser.add_argument("--extra", nargs="*", default=[], help="more table names to try")
    parser.add_argument("--refresh", action="store_true", help="download the tables again")
    args = parser.parse_args()

    wago.AGENT = "ProfessionsForever-table-fetch (https://github.com/ProfessionsForever/Professions_Forever)"
    if args.out:
        wago.CACHE = args.out
    build = args.build or wago.latest_build()
    optional = [t for t in dict.fromkeys((*EXTRA, *args.extra)) if t not in REQUIRED]

    tables, missing = {}, []
    for table in (*REQUIRED, *optional):
        fresh = args.refresh or not (wago.CACHE / build / f"{table}.csv").exists()
        try:
            path = wago.cached_table(build, table, args.refresh)
        except (SystemExit, OSError) as error:  # cached_table exits on a download that isn't a table
            if table in REQUIRED:
                sys.exit(f"{table}: {error}")
            print(f"skipped {table}: {error}")
            missing.append(table)
        else:
            data = path.read_bytes()
            tables[table] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
        if fresh:
            time.sleep(PAUSE)

    manifest = {
        "product": "wowf",
        "build": build,
        "fetched": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source": "https://wago.tools/db2/<Table>/csv?build=<build>",
        "tables": tables,
        "missing": missing,
    }
    (wago.CACHE / build / "MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    total = sum(t["bytes"] for t in tables.values())
    print(f"{len(tables)} tables for build {build} in {wago.CACHE / build} ({total / 1048576:.1f} MB)"
          + (f"; not on wago.tools: {', '.join(missing)}" if missing else ""))
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as out:
            out.write(f"build={build}\n")


if __name__ == "__main__":
    main()
