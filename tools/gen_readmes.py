#!/usr/bin/env python3
"""Builds the two readme copies from their Markdown sources, so only the Markdown is ever edited.

  README.md      -> README.txt       the plain-text readme packaged with the addon (README.md isn't packaged):
                                     the header line, then every section from Features on, except Contents and
                                     Development, with a Support section before the license
  CURSEFORGE.md  -> CURSEFORGE.html  the CurseForge project page as HTML, for pasting into CurseForge's HTML editor
                                     (CURSEFORGE.md is kept out of git; the script skips it when it isn't there)

Usage: tools/gen_readmes.py   (run it after changing README.md or CURSEFORGE.md, and before a release)
"""
import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

SUPPORT = [
    "Discord: https://discord.gg/Ay4E5GEhA2",
    "Bug reports and ideas: https://github.com/ProfessionsForever/Professions_Forever/issues",
    "Email: professionsforever@gmail.com",
]
SKIP_SECTIONS = {"Contents", "Development"}


def inline(text):
    """Markdown inline markup to plain text: links as "text (url)", bold, code and escapes dropped."""
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r"\1 (\2)", text)
    text = text.replace("**", "").replace("`", "")
    text = re.sub(r"\\([<>*_`\\])", r"\1", text)
    return text


def table(rows, aligned):
    cells = [[inline(c.strip()) for c in r.strip().strip("|").split("|")] for r in rows]
    cells = [c for c in cells if not all(re.fullmatch(r"-+", x) for x in c)][1:]  # drop the header and the --- row
    if aligned:
        width = max(len(c[0]) for c in cells) + 3
        return [c[0].ljust(width) + c[1] for c in cells]
    return ["- " + c[0] + ": " + c[1] for c in cells]


def readme_txt():
    src = (ROOT / "README.md").read_text()
    blurb = re.search(r'<p align="center">\s*(A replacement.*?)</p>', src, re.S).group(1)
    blurb = html.unescape(re.sub(r"<[^>]+>", "", blurb.replace("<br>", " ")))
    blurb = re.sub(r"\s+", " ", blurb).strip()
    out = ["ProfessionsForever", "==================", "", blurb]

    def section(title, lines=()):
        while out[-1] == "":
            out.pop()
        out.extend(["", "", title.upper(), "-" * len(title), ""] + list(lines))

    sections = re.split(r"^## ", src[src.index("\n## Features"):], flags=re.M)[1:]
    for sec in sections:
        title, _, body = sec.partition("\n")
        title = title.strip()
        if title in SKIP_SECTIONS:
            continue
        if title.startswith("License"):
            section("Support", ["- " + s for s in SUPPORT])
        section(title)
        lines, rows = body.strip("\n").split("\n"), []
        for line in lines + [""]:
            if line.startswith("|"):
                rows.append(line)
                continue
            if rows:
                out += table(rows, aligned=title == "Slash commands")
                rows = []
            if line.startswith("### "):
                if out[-1] != "":
                    out.append("")
                out.append(inline(line[4:]))
            elif line.strip() or out[-1] != "":
                out.append(inline(line))
    while out[-1] == "":
        out.pop()
    (ROOT / "README.txt").write_text("\n".join(out) + "\n")
    print("README.txt written")


def curseforge_html():
    path = ROOT / "CURSEFORGE.md"
    if not path.exists():
        print("CURSEFORGE.md not found, skipped")
        return
    try:
        import markdown
    except ImportError:
        sys.exit("CURSEFORGE.html needs Python-Markdown: pip install markdown")
    src = re.sub(r"<!--.*?-->\n?", "", path.read_text(), flags=re.S).strip()
    page = markdown.markdown(src, extensions=["tables"])
    # CurseForge drops align=, so the logo is centred with a style instead.
    page = re.sub(r'<p align="center"><img src="([^"]+)" alt="([^"]+)" width="256"></p>',
                  r'<p style="text-align: center;"><img src="\1" alt="\2" width="256" height="256" /></p>', page)
    (ROOT / "CURSEFORGE.html").write_text(page + "\n")
    print("CURSEFORGE.html written")


readme_txt()
curseforge_html()
