#!/bin/sh
# Copies the Lua release named in Sources/CLua/VERSION from lua.org into Sources/CLua after a check of
# its SHA-256, and writes the SHA-256 of each vendored file to Sources/CLua/VENDOR.sha256. The
# stand-alone interpreter and compiler and the libraries for files, modules, and debugging stay out,
# so a script cannot reach them even through a bug of the host (ADR 0015).
#   scripts/vendor-lua.sh                replace the sources (needs lua.org)
#   scripts/vendor-lua.sh --check [dir]  fail when a file of dir (default Sources/CLua) differs from
#                                        VENDOR.sha256, is missing, or is neither listed nor one of OWN
#   scripts/vendor-lua.sh --self-test    show that --check fails on a changed, an extra, and a missing file,
#                                        and on a VERSION that VENDOR.sha256 was not written for
# --check and --self-test work offline, because lua.org resets connections from CI runners.
set -e
cd "$(dirname "$0")/.."
# The files that Moneten adds to the release.
OWN="VERSION VENDOR.sha256 clua.c include/clua.h"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# The first line of VENDOR.sha256 names the archive and its SHA-256, as VERSION pins them.
pin() {
	echo "# $(sed -n 1p "$1/VERSION") $(sed -n 2p "$1/VERSION")"
}

check() {
	[ "$(sed -n 1p "$1/VENDOR.sha256")" = "$(pin "$1")" ] || { echo "$1/VENDOR.sha256 lists the files of another release than VERSION." >&2; return 1; }
	(cd "$1" && sed 1d VENDOR.sha256 | shasum -a 256 -c --quiet -) || { echo "$1 differs from VENDOR.sha256." >&2; return 1; }
	{ sed '1d; s/^[0-9a-f]*  //' "$1/VENDOR.sha256"; for f in $OWN; do echo "./$f"; done; } | LC_ALL=C sort > "$WORK/expected"
	(cd "$1" && find . -type f) | LC_ALL=C sort > "$WORK/present"
	extra=$(LC_ALL=C comm -13 "$WORK/expected" "$WORK/present")
	[ -z "$extra" ] || { echo "$1 has files that are not part of the release: $extra" >&2; return 1; }
	echo "$1 matches $(sed -n 1p "$1/VERSION")."
}

fails() {
	if check "$1" 2>/dev/null >&2; then echo "--check passed $2." >&2; exit 1; fi
}

case "$1" in
--check)
	check "${2:-Sources/CLua}"
	;;
--self-test)
	check Sources/CLua >/dev/null
	cp -R Sources/CLua "$WORK/changed" && printf 'x' >> "$WORK/changed/lvm.c" && fails "$WORK/changed" "a changed file"
	cp -R Sources/CLua "$WORK/extra" && touch "$WORK/extra/lextra.c" && fails "$WORK/extra" "an extra file"
	cp -R Sources/CLua "$WORK/missing" && rm "$WORK/missing/lvm.c" && fails "$WORK/missing" "a missing file"
	cp -R Sources/CLua "$WORK/stale" && printf 'lua-5.4.10.tar.gz\n%064d\n' 0 > "$WORK/stale/VERSION" && fails "$WORK/stale" "a VERSION of another release"
	echo "--check fails on a changed, an extra, and a missing file, and on a VERSION of another release."
	;;
"")
	ARCHIVE=$(sed -n 1p Sources/CLua/VERSION)
	SHA256=$(sed -n 2p Sources/CLua/VERSION)
	curl -sS --fail --retry 3 --retry-all-errors -L -o "$WORK/$ARCHIVE" "https://www.lua.org/ftp/$ARCHIVE"
	echo "$SHA256  $WORK/$ARCHIVE" | shasum -a 256 -c >/dev/null
	tar -xzf "$WORK/$ARCHIVE" -C "$WORK"
	SRC="$WORK/${ARCHIVE%.tar.gz}/src"
	for f in lua.c luac.c lua.hpp linit.c liolib.c loadlib.c ldblib.c Makefile; do rm "$SRC/$f"; done
	mkdir -p "$SRC/include"
	for f in lua.h luaconf.h lualib.h lauxlib.h; do mv "$SRC/$f" "$SRC/include/"; done
	find Sources/CLua -name 'l*.[ch]' -delete
	cp -R "$SRC/" Sources/CLua/
	{ pin Sources/CLua; (cd "$SRC" && find . -type f | LC_ALL=C sort | xargs shasum -a 256); } > Sources/CLua/VENDOR.sha256
	echo "Vendored $ARCHIVE into Sources/CLua."
	;;
*)
	echo "usage: scripts/vendor-lua.sh [--check [dir] | --self-test]" >&2
	exit 2
	;;
esac
