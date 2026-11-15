#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
WORK=$(mktemp -d "$PWD/.build/check-export-sync.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
clang -dynamiclib Tests/ExportFileProbe/sync.c -o "$WORK/sync.dylib"
MONETEN_EXPORT_SYNC_LIBRARY="$WORK/sync.dylib" MONETEN_EXPORT_SYNC_TRACE="$WORK/trace" \
	python3 scripts/check-export-files.py
python3 - "$WORK/trace" <<'PY'
import pathlib
import sys
actual = pathlib.Path(sys.argv[1]).read_text()
assert actual == "file\nrename\ndirectory\n" * 4, actual
print("The export syncs the temporary file before rename and its folder after rename.")
PY
