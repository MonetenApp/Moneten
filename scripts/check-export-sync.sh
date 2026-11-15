#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
WORK=$(mktemp -d "$PWD/.build/check-export-sync.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
clang -Wall -Wextra -Werror -dynamiclib Tests/ExportFileProbe/sync.c -o "$WORK/sync.dylib"
# macOS strips DYLD variables when it starts /bin/sh, so run the toolchain executable directly.
SWIFT=$(xcrun --find swift)
run() {
	MONETEN_EXPORT_SYNC_TRACE="$WORK/trace" DYLD_INSERT_LIBRARIES="$WORK/sync.dylib" \
		"$SWIFT" test --disable-keychain --skip-build --filter "$1"
}
run ExportFileTests/privateExportFile
python3 - "$WORK/trace" <<'PY'
import pathlib
import sys
actual = pathlib.Path(sys.argv[1]).read_text()
assert actual == "file\nrename\ndirectory\n" * 2, actual
print("Full file sync precedes rename; directory sync follows rename, for new and replaced files.")
PY
rm "$WORK/trace"
MONETEN_EXPORT_SYNC_FALLBACK=1 run ExportFileTests/privateExportFile
python3 - "$WORK/trace" <<'PY'
import pathlib
import sys
actual = pathlib.Path(sys.argv[1]).read_text()
assert actual == "file\nfallback\nrename\ndirectory\n" * 2, actual
print("Unsupported full sync falls back to fsync before rename.")
PY
rm "$WORK/trace"
unset MONETEN_EXPORT_SYNC_FALLBACK
MONETEN_EXPORT_CANCEL_PROBE=1 MONETEN_EXPORT_SYNC_DELAY=1 run ExportFileTests/cancellationDuringSync
python3 - "$WORK/trace" <<'PY'
import pathlib
import sys
actual = pathlib.Path(sys.argv[1]).read_text()
assert actual in ["file\n", "file\nfallback\n"], actual
print("Cancellation during sync prevents rename.")
PY
