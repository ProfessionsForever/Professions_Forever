#!/usr/bin/env python3
"""Builds the release zip the way the CurseForge packager does.

Packages a tag, never the working folder, so the zip holds exactly what was released:
  - the files committed at the tag, inside one folder named by .pkgmeta's package-as
  - without the .pkgmeta ignore list, and without dot files and dot folders
  - @do-not-package@ blocks cut out of .toc, .lua and .xml files
  - @debug@ blocks in .lua files commented out

Usage: tools/package.py [tag]   (the newest version tag when left out)
Writes dist/<package-as>-<tag>.zip
"""
import io
import re
import subprocess
import sys
import tarfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

DO_NOT_PACKAGE = {
    ".toc": re.compile(rb"^#@do-not-package@.*?^#@end-do-not-package@[^\n]*\n?", re.S | re.M),
    ".lua": re.compile(rb"^[ \t]*--@do-not-package@.*?--@end-do-not-package@[^\n]*\n?", re.S | re.M),
    ".xml": re.compile(rb"^[ \t]*<!--@do-not-package@-->.*?<!--@end-do-not-package@-->[^\n]*\n?", re.S | re.M),
}


def git(*args):
    return subprocess.run(["git", "-C", str(ROOT), *args], check=True, capture_output=True).stdout


def pkgmeta(text):
    """The two .pkgmeta keys the package depends on: the folder name and the ignore list."""
    name = re.search(r"^package-as:\s*(\S+)", text, re.M).group(1)
    block = re.search(r"^ignore:\n((?:[ \t]+-.*\n?)+)", text, re.M).group(1)
    return name, [line.split("-", 1)[1].strip() for line in block.splitlines()]


def ignored(path, ignore):
    if any(part.startswith(".") for part in path.split("/")):
        return True
    return any(path == entry or path.startswith(entry + "/") for entry in ignore)


def process(path, data):
    suffix = Path(path).suffix
    if suffix in DO_NOT_PACKAGE:
        data = DO_NOT_PACKAGE[suffix].sub(b"", data)
    if suffix == ".lua":
        data = data.replace(b"--@debug@", b"--[===[@debug@").replace(b"--@end-debug@", b"--@end-debug@]===]")
    return data


def main():
    tag = sys.argv[1] if len(sys.argv) > 1 else git("tag", "--sort=-v:refname").decode().split()[0]
    name, ignore = pkgmeta(git("show", f"{tag}:.pkgmeta").decode())

    out = ROOT / "dist" / f"{name}-{tag}.zip"
    out.parent.mkdir(exist_ok=True)
    count = 0
    with tarfile.open(fileobj=io.BytesIO(git("archive", "--format=tar", tag))) as tar, \
            zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for member in tar:
            if not member.isfile() or ignored(member.name, ignore):
                continue
            data = process(member.name, tar.extractfile(member).read())
            zf.writestr(f"{name}/{member.name}", data)
            count += 1
    print(f"{out.relative_to(ROOT)}: {count} files, {out.stat().st_size / 1024:.0f} KB, from {tag}")


if __name__ == "__main__":
    main()
