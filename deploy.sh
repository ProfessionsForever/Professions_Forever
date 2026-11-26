#!/usr/bin/env bash
# Replaces <AddOns>/<addon> with the current source files, in every listed AddOns folder.
# AddOns paths: the arguments, else $WOW_ADDONS_DIR, else each line of .addons-path next to this script (blank lines
# and lines starting with # are skipped; .addons-path is local and not committed).
# Shared between addons: a copy from the ThreeLightsLib repository (its sync.sh brings it in).
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOC="$(ls "$SRC"/*.toc | head -n 1)"
NAME="$(basename "$TOC" .toc)"

TARGETS=()
if [[ $# -gt 0 ]]; then
	TARGETS=("$@")
elif [[ -n "${WOW_ADDONS_DIR:-}" ]]; then
	TARGETS=("$WOW_ADDONS_DIR")
elif [[ -f "$SRC/.addons-path" ]]; then
	while IFS= read -r line || [[ -n "$line" ]]; do
		[[ -z "${line//[[:space:]]/}" || "$line" == \#* ]] && continue
		TARGETS+=("$line")
	done < "$SRC/.addons-path"
fi
if [[ ${#TARGETS[@]} -eq 0 ]]; then
	echo "No AddOns path. Pass it as an argument, set WOW_ADDONS_DIR, or list it in $SRC/.addons-path" >&2
	exit 1
fi

# Guard against deleting the wrong thing: check every target before touching any.
for i in "${!TARGETS[@]}"; do
	TARGETS[$i]="${TARGETS[$i]%/}"
	if [[ "$(basename "${TARGETS[$i]}")" != "AddOns" || ! -d "${TARGETS[$i]}" ]]; then
		echo "Refusing: '${TARGETS[$i]}' is not an existing folder named AddOns" >&2
		exit 1
	fi
done

for ADDONS in "${TARGETS[@]}"; do
	DEST="$ADDONS/$NAME"
	rm -rf -- "$DEST"
	mkdir -p -- "$DEST"
	cp -- "$SRC"/*.toc "$SRC/LICENSE" "$DEST/"
	# Files and folders the .toc doesn't name line by line: bindings, media, and libraries loaded through an XML file.
	for extra in Bindings.xml Media Libs; do
		if [[ -e "$SRC/$extra" ]]; then cp -r -- "$SRC/$extra" "$DEST/"; fi
	done
	# Everything the .toc loads: lines with a backslash copy their top folder, other lines (e.g. embeds.xml) the file.
	grep -v -e '^#' -e '^[[:space:]]*$' "$TOC" | tr -d '\r' | sed 's/\\.*$/\\/' | sort -u |
		while IFS= read -r entry; do
			if [[ "$entry" == *\\ ]]; then cp -r -- "$SRC/${entry%\\}" "$DEST/"; else cp -- "$SRC/$entry" "$DEST/"; fi
		done
	# The library's list of globals is for tools/check.py only.
	rm -f -- "$DEST/Libs/ThreeLightsLib/known-globals.txt"
	echo "Deployed to $DEST"
done
