#!/usr/bin/env python3
"""Checks the addon's Lua code without starting the game. Prints only problems, then a one-line summary.

  1. Syntax of every code file the .toc loads, with LuaJIT (WoW runs Lua 5.1).
  2. Globals each file reads that are not in tools/known-globals.txt: usually a local that stopped resolving after
     code moved between files. A real WoW or Lua global the addon starts using goes in that list.
  3. Globals a file writes that are not in the list either: usually a missing `local`.
  4. Locals that are declared but never used.
  5. Files the .toc lists that don't exist, and Lua files the .toc doesn't load.
  6. The locale template (Locales/enUS.lua): keys listed twice, keys no code uses, and L["..."] lookups it lacks.
  7. FP.* functions and values that are defined but never used anywhere.

With --map it also prints, for review (not counted as problems), each file's functions that other files use and by
whom, and the ones in a feature's file that other features call: a shared helper in the wrong place, or a window's API.

Usage: tools/check.py [--map]   (inside the VS Code Flatpak it runs the host's LuaJIT through flatpak-spawn)
"""
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOC = ROOT / "ProfessionsForever.toc"
KNOWN = Path(__file__).resolve().parent / "known-globals.txt"
# Lua files that are deliberately not loaded.
NOT_LOADED = set()


def luajit():
    if shutil.which("luajit"):
        return ["luajit"]
    if shutil.which("flatpak-spawn"):
        return ["flatpak-spawn", "--host", "luajit"]
    sys.exit("LuaJIT not found")


def toc_files():
    lines = TOC.read_text(encoding="utf-8").splitlines()
    return [l.strip().replace("\\", "/") for l in lines if l.strip() and not l.startswith("#")]


def bytecode(cmd, path):
    """LuaJIT's bytecode listing, or None with the error printed when the file doesn't compile."""
    result = subprocess.run(cmd + ["-bl", str(path)], capture_output=True, text=True)
    if result.returncode != 0:
        print(f"SYNTAX  {result.stderr.strip()}")
        return None
    return result.stdout


def unknown_globals(listing, op, known):
    """Global names the listing reads (GGET) or writes (GSET) that aren't known. LuaJIT cuts names after 40
    characters and marks them with ~, so a cut name only has to start a known one."""
    names = set(re.findall(op + r'\s.*; "([A-Za-z_][A-Za-z0-9_]*)"(~?)', listing))
    return sorted(name for name, cut in names
                  if name not in known and not (cut and any(k.startswith(name) for k in known)))


DECLARED = re.compile(r"^[ \t]*local[ \t]+(?:function[ \t]+)?([\w \t,]+?)[ \t]*(=|\(|$)", re.M)


def unused_locals(text):
    """Locals named nowhere else in the file (a field `x.name` or a method `x:name` doesn't count as a use)."""
    found = []
    for m in DECLARED.finditer(text):
        for name in (n.strip() for n in m.group(1).split(",")):
            if name and name != "_" and len(re.findall(r"(?<![.:\w])" + re.escape(name) + r"\b", text)) == 1:
                found.append((text[:m.start()].count("\n") + 1, name))
    return found


# --------------------------------------------------------------------------
# Source splitting: comments and strings out of the way, line numbers kept
# --------------------------------------------------------------------------
TOKEN = re.compile(r'--\[(=*)\[.*?\]\1\]|--[^\n]*|"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'|\[(=*)\[.*?\]\2\]', re.S)


def split_source(text):
    """The code with comments and strings blanked (line breaks kept), and the string literals as written."""
    literals = []

    def blank(m):
        s = m.group(0)
        if s.startswith("--"):
            return re.sub(r"[^\n]", " ", s)
        if s[0] in "\"'":
            literals.append(s[1:-1])
        else:
            literals.append(s[s.index("[", 1) + 1:s.rindex("]", 0, -1)])
        return '""' + "\n" * s.count("\n")

    return TOKEN.sub(blank, text), literals


# --------------------------------------------------------------------------
# Locale: the template in Locales/enUS.lua against the strings the code uses
# --------------------------------------------------------------------------
LOCALE = "Locales/enUS.lua"


def locale_problems(sources):
    """Template keys listed twice, keys no code names (as a literal anywhere: many are looked up through tables), and
    L["..."] lookups missing from the template. sources: {rel: text} of the code files, the locale file included."""
    _, template = split_source(sources[LOCALE])
    seen, out = set(), []
    for key in template:
        if key in seen:
            out.append(f"LOCALE  {LOCALE}: \"{key}\" is listed twice")
        seen.add(key)
    used, looked_up = set(), {}
    for rel, text in sources.items():
        if rel == LOCALE:
            continue
        code, literals = split_source(text)
        used.update(literals)
        for m in re.finditer(r'\bL\[\s*"((?:\\.|[^"\\\n])*)"\s*\]', text):
            looked_up.setdefault(m.group(1), rel)
    for key in sorted(seen - used):
        out.append(f"LOCALE  {LOCALE}: \"{key}\" is never used")
    for key, rel in sorted(looked_up.items()):
        if key not in seen:
            out.append(f"LOCALE  {rel}: L[\"{key}\"] is missing from {LOCALE}")
    return out


# --------------------------------------------------------------------------
# Exports: FP.* definitions against the files that use them
# --------------------------------------------------------------------------
IDENT = r"[A-Za-z_][A-Za-z0-9_]*"


def exports(sources):
    """defs: {qualified name: (file, line)}; uses: {qualified name: {files}}; by_name: {last name part: {files}} for
    self.x / self:x uses, which can't be resolved to a table. A local that holds an FP table (local UI = FP.UI, or a
    table the file creates and exports, local Shop = {} ... FP.Shop = Shop) stands for it."""
    defs, uses, by_name, modules = {}, {}, {}, set()
    for rel, text in sources.items():
        code, _ = split_source(text)
        aliases = {"FP": "FP"}
        # local A = FP.X, local A, B = FP.X, UI.Y, local Q = FP.Queue inside a function: each name gets its chain.
        for m in re.finditer(r"^[ \t]*local\s+([\w \t,]+?)\s*=\s*([^\n]+)$", code, re.M):
            names, exprs = [n.strip() for n in m.group(1).split(",")], [e.strip() for e in m.group(2).split(",")]
            for name, expr in zip(names, exprs):
                chain = re.fullmatch(rf"({IDENT})((?:\.{IDENT})*)", expr)
                if chain and chain.group(1) in aliases:
                    aliases[name] = aliases[chain.group(1)] + chain.group(2)
        for m in re.finditer(rf"^(FP(?:\.{IDENT})+)\s*=\s*({IDENT})\s*$", code, re.M):
            if re.search(rf"^local\s+{m.group(2)}\s*=\s*\{{\s*\}}", code, re.M):
                aliases[m.group(2)] = m.group(1)
                modules.add(m.group(1))
        names = "|".join(sorted(map(re.escape, aliases), key=len, reverse=True))
        spans = set()

        def define(base, name, pos):
            if aliases[base].count(".") > 1:
                return  # a field of a frame or record (f.detail.qty = ...), not one of FP's tables
            q = aliases[base] + "." + name
            defs.setdefault(q, (rel, code[:pos].count("\n") + 1))
            spans.add(pos)

        for m in re.finditer(rf"^\s*function\s+({names})[.:]({IDENT})\s*\(", code, re.M):
            define(m.group(1), m.group(2), m.start(1))
        for m in re.finditer(rf"^[ \t]*((?:(?:{names})\.{IDENT}\s*,\s*)*(?:{names})\.{IDENT})\s*=(?!=)", code, re.M):
            start = m.start(1)
            for t in re.finditer(rf"({names})\.({IDENT})", m.group(1)):
                define(t.group(1), t.group(2), start + t.start())
        for m in re.finditer(rf"(?<![\w.:])({names})((?:[.:]{IDENT})+)", code):
            if m.start() in spans:
                continue
            q = aliases[m.group(1)]
            for part in re.split(r"[.:]", m.group(2))[1:]:
                q += "." + part
                uses.setdefault(q, set()).add(rel)
        # self.x is the table a method belongs to; in event handlers (FP:RegisterEvent) self is FP itself, so a longer
        # chain (self.Alts:Flush) is also counted as FP's.
        for m in re.finditer(rf"(?<![\w.:])self[.:]({IDENT})((?:[.:]{IDENT})*)", code):
            by_name.setdefault(m.group(1), set()).add(rel)
            if m.group(2):
                q = "FP." + m.group(1)
                for part in re.split(r"[.:]", m.group(2))[1:]:
                    q += "." + part
                    uses.setdefault(q, set()).add(rel)
    return defs, uses, by_name, modules


def users_of(q, uses, by_name, defs):
    """Files that use q: directly, through a field under it, or as self.name in the file defining it."""
    found = set(uses.get(q, ()))
    prefix = q + "."
    for k, files in uses.items():
        if k.startswith(prefix):
            found |= files
    name = q.rsplit(".", 1)[1]
    found |= by_name.get(name, set()) & {defs[q][0]} if q in defs else set()
    return found


def export_problems(defs, uses, by_name):
    out = []
    for q, (rel, line) in sorted(defs.items()):
        name = q.rsplit(".", 1)[1]
        if not uses.get(q) and not any(k.startswith(q + ".") for k in uses) and name not in by_name:
            out.append(f"EXPORT  {rel}:{line} {q} is defined but never used")
    return out


# Where helpers are expected to be shared from; everything else is one feature's code.
SHARED = ("Core/", "Alts/", "Waypoints/", "Data/", "Locales/", "UI/Common/", "UI/Shared.lua")
WINDOW_API = {"Open", "Toggle", "Update", "QueueUpdate", "Create", "frame"}


def folder(rel):
    return rel.rsplit("/", 1)[0]


def print_map(defs, uses, by_name, modules):
    """For review, not counted as problems: each file's functions used by other files and by whom, then the ones that
    look like a shared helper living inside one feature's file (the kind that belongs in UI/Common or UI/Shared.lua).
    Module tables, saved settings (FP.db) and state fields (lowercase names) are left out."""
    per_file, hints = {}, []
    for q, (rel, line) in defs.items():
        name = q.rsplit(".", 1)[1]
        if q in modules or q.startswith("FP.db.") or name[0].islower():
            continue
        others = users_of(q, uses, by_name, defs) - {rel}
        if not others:
            continue
        per_file.setdefault(rel, []).append((q, sorted(others)))
        if (not rel.startswith(SHARED) and name not in WINDOW_API and not name.startswith("Create")
                and len(others) >= 2 and any(folder(o) != folder(rel) for o in others)):
            hints.append(f"  {rel}:{line} {q}: used by {', '.join(sorted(others))}")
    for rel in sorted(per_file):
        print(f"-- {rel}")
        for q, others in sorted(per_file[rel]):
            print(f"     {q.split('.', 1)[1]}: {', '.join(others)}")
    print("\nIn a feature's file but used by other features (shared helper in the wrong place, or a window's API?):")
    print("\n".join(sorted(hints)) or "  none")


def main():
    cmd = luajit()
    known = {l.strip() for l in KNOWN.read_text(encoding="utf-8").splitlines() if l.strip() and not l.startswith("#")}
    listed = toc_files()
    problems = 0

    for rel in listed:
        if not (ROOT / rel).exists():
            print(f"TOC     {rel} is listed but missing")
            problems += 1
    on_disk = {p.relative_to(ROOT).as_posix() for p in ROOT.rglob("*.lua")
               if not p.relative_to(ROOT).parts[0] in ("tools", ".vscode", ".git")}
    for rel in sorted(on_disk - set(listed) - NOT_LOADED):
        print(f"TOC     {rel} is not loaded by the .toc")
        problems += 1

    code = [rel for rel in listed if not rel.startswith("Data/") and (ROOT / rel).exists()]
    for rel in code:
        listing = bytecode(cmd, ROOT / rel)
        if listing is None:
            problems += 1
            continue
        for name in unknown_globals(listing, "GGET", known):
            print(f"GLOBAL  {rel}: reads unknown global '{name}'")
            problems += 1
        for name in unknown_globals(listing, "GSET", known):
            print(f"GLOBAL  {rel}: writes global '{name}' (missing local?)")
            problems += 1
        for line, name in unused_locals((ROOT / rel).read_text(encoding="utf-8")):
            print(f"UNUSED  {rel}:{line} local '{name}'")
            problems += 1

    sources = {rel: (ROOT / rel).read_text(encoding="utf-8") for rel in code}
    for line in locale_problems(sources):
        print(line)
        problems += 1
    defs, uses, by_name, modules = exports({rel: text for rel, text in sources.items() if rel != LOCALE})
    for line in export_problems(defs, uses, by_name):
        print(line)
        problems += 1
    if "--map" in sys.argv:
        print_map(defs, uses, by_name, modules)

    print(f"{len(code)} code files checked: " + ("all clear" if problems == 0 else f"{problems} problem(s)"))
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
