#!/bin/sh
# Copies the Lua release named in Sources/CLua/VERSION from lua.org into Sources/CLua after a check of
# its SHA-256. The stand-alone interpreter and compiler and the libraries for files, modules, and
# debugging stay out, so a script cannot reach them even through a bug of the host (ADR 0015).
#   scripts/vendor-lua.sh           replace the sources
#   scripts/vendor-lua.sh --check   fail when a vendored file differs from the release or is not part of it
set -e
cd "$(dirname "$0")/.."
ARCHIVE=$(sed -n 1p Sources/CLua/VERSION)
SHA256=$(sed -n 2p Sources/CLua/VERSION)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
curl -sSfL -o "$WORK/$ARCHIVE" "https://www.lua.org/ftp/$ARCHIVE"
echo "$SHA256  $WORK/$ARCHIVE" | shasum -a 256 -c >/dev/null
tar -xzf "$WORK/$ARCHIVE" -C "$WORK"
SRC="$WORK/${ARCHIVE%.tar.gz}/src"
LEFT_OUT="lua.c luac.c lua.hpp linit.c liolib.c loadlib.c ldblib.c Makefile"
PUBLIC="lua.h luaconf.h lualib.h lauxlib.h"
for f in $LEFT_OUT; do rm "$SRC/$f"; done
for f in $PUBLIC; do mkdir -p "$SRC/include" && mv "$SRC/$f" "$SRC/include/"; done
if [ "$1" = "--check" ]; then
	for f in $(cd "$SRC" && find . -type f); do
		cmp -s "$SRC/$f" "Sources/CLua/$f" || { echo "Sources/CLua/$f differs from $ARCHIVE." >&2; exit 1; }
	done
	# Only the shim of Moneten may come on top of the release.
	for f in $(cd Sources/CLua && find . -type f ! -name VERSION ! -name clua.c ! -name clua.h); do
		[ -f "$SRC/$f" ] || { echo "Sources/CLua/$f is not part of $ARCHIVE." >&2; exit 1; }
	done
	echo "Sources/CLua matches $ARCHIVE."
	exit 0
fi
find Sources/CLua -name 'l*.[ch]' -delete
cp -R "$SRC/" Sources/CLua/
echo "Vendored $ARCHIVE into Sources/CLua."
