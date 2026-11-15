#!/bin/sh
# Writes a test feed for a Debug build into a folder, signed with the test update key of
# Fixtures/update, through the same release-notes.py appcast and sign_update as a release.
#   scripts/update-test-feed.sh DIR [--port N] [--no-notes VERSION] ITEM...
# ITEM is VERSION:BUILD, VERSION:BUILD:MIN_MACOS, or VERSION:BUILD:MIN_MACOS:DMG. Without a DMG the
# enclosure is a made-up file, enough for every window before "Install". Each version gets two
# made-up entries, one with a link. --no-notes leaves the description of that version empty.
# Then serve the folder and start a Debug build with it:
#   python3 -m http.server --directory DIR 8765
#   open --env MONETEN_FEED_URL=http://127.0.0.1:8765/appcast.xml --env MONETEN_DATA_DIR=... dist/Moneten.app
set -e
cd "$(dirname "$0")/.."
[ -n "$1" ] || { echo "usage: scripts/update-test-feed.sh DIR [--port N] [--no-notes VERSION] VERSION:BUILD[:MIN_MACOS[:DMG]]..." >&2; exit 2; }
DIR=$1
shift
PORT=8765
NO_NOTES=""
while [ $# -gt 0 ]; do
	case "$1" in
		--port) PORT=$2; shift 2 ;;
		--no-notes) NO_NOTES=$2; shift 2 ;;
		*) break ;;
	esac
done
KEY=Fixtures/update/test-update.key
SPARKLE=$(scripts/sparkle-tools.sh)
mkdir -p "$DIR"
rm -f "$DIR/appcast.xml"

# A changelog with a section for every version, newest first, dated by its build number.
python3 - "$DIR/CHANGELOG.md" "$@" <<'EOF'
import sys
items = [a.split(":") for a in sys.argv[2:]]
items.sort(key=lambda i: int(i[1]), reverse=True)
lines = ["# Changelog", "", "## Unreleased", ""]
for item in items:
	version, build = item[0], int(item[1])
	lines += ["## %s (2026-11-%02d)" % (version, build % 28 + 1), "",
		"- Made-up change number one of version %s." % version,
		"- [Made-up link](https://github.com/MonetenApp/Moneten/releases) of version %s." % version, ""]
open(sys.argv[1], "w").write("\n".join(lines))
EOF

FEED=--first-release
for ITEM in "$@"; do
	VERSION=$(echo "$ITEM" | cut -d: -f1)
	BUILD=$(echo "$ITEM" | cut -d: -f2)
	MIN=$(echo "$ITEM" | cut -d: -f3)
	DMG=$(echo "$ITEM" | cut -d: -f4)
	FILE="$DIR/Moneten-$VERSION.dmg"
	if [ -n "$DMG" ]; then cp "$DMG" "$FILE"; else echo "Made-up disk image of $VERSION" > "$FILE"; fi
	SIGNATURE=$("$SPARKLE/sign_update" --ed-key-file "$KEY" -p "$FILE")
	python3 scripts/release-notes.py --changelog "$DIR/CHANGELOG.md" appcast "$VERSION" --build "$BUILD" --min-macos "${MIN:-15.0}" \
		--url "https://github.com/MonetenApp/Moneten/releases/download/v$VERSION/Moneten-$VERSION.dmg" --length "$(stat -f%z "$FILE")" --signature "$SIGNATURE" \
		$FEED --out "$DIR/appcast.xml"
	FEED="--feed $DIR/appcast.xml"
done
# The disk images come from the local server, and --no-notes empties one description.
python3 - "$DIR/appcast.xml" "$PORT" "$NO_NOTES" <<'EOF'
import re, sys
path, port, empty = sys.argv[1:]
text = open(path).read()
text = re.sub(r"https://github.com/MonetenApp/Moneten/releases/download/v[^/]*/", "http://127.0.0.1:%s/" % port, text)
if empty:
	pattern = r"(<title>%s</title>.*?<description[^>]*>).*?(</description>)" % re.escape(empty)
	text = re.sub(pattern, r"\1\2", text, count=1, flags=re.S)
open(path, "w").write(text)
EOF
"$SPARKLE/sign_update" --ed-key-file "$KEY" "$DIR/appcast.xml" >/dev/null
"$SPARKLE/sign_update" --verify --ed-key-file "$KEY" "$DIR/appcast.xml"
echo "Wrote the signed test feed $DIR/appcast.xml for http://127.0.0.1:$PORT/."
