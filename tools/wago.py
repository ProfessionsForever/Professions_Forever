"""Downloads the WoW: Forever DB2 tables (product wowf) from wago.tools for the generator scripts, keeping each in a
cache folder (~/.cache/professionsforever/wago/<build>) so a build is downloaded once. Each script sets AGENT to its
own name before downloading. wago.tools publishes no data terms, so leave the attribution in the generated files.
"""
import csv
import json
import sys
import urllib.request
from pathlib import Path

CACHE = Path.home() / ".cache" / "professionsforever" / "wago"
AGENT = "ProfessionsForever-data-generator (run by hand)"


def fetch(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": AGENT}), timeout=120) as response:
        return response.read()


def latest_build():
    builds = json.loads(fetch("https://wago.tools/api/builds"))["wowf"]
    return builds[0]["version"]


def cached_table(build, table, refresh):
    path = CACHE / build / f"{table}.csv"
    if refresh or not path.exists():
        print(f"downloading {table} ({build})")
        data = fetch(f"https://wago.tools/db2/{table}/csv?build={build}")
        if not data.startswith(b"ID,") and b",ID," not in data.split(b"\n", 1)[0]:
            sys.exit(f"{table}: the download doesn't look like a CSV table")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    return path


def rows(path):
    with open(path, newline="", encoding="utf-8") as f:
        yield from csv.DictReader(f)
