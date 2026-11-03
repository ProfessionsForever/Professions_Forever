#!/usr/bin/env bash
# Replaces <AddOns>/ProfessionsForever with the current source files, in every listed AddOns folder.
# AddOns paths: the arguments, else $WOW_ADDONS_DIR, else each line of .addons-path next to this script
# (blank lines and lines starting with # are skipped).
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="ProfessionsForever"

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
	cp -r -- "$SRC/Media" "$DEST/"
	# Every folder the .toc loads files from.
	while IFS= read -r dir; do cp -r -- "$SRC/$dir" "$DEST/"; done < <(grep -v '^#' "$SRC/$NAME.toc" | grep '\\' | cut -d'\' -f1 | sort -u)
	echo "Deployed to $DEST"
done
