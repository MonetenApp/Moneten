#!/bin/sh
# The pin of Sparkle, which only the app uses. It must name the version of App/project.yml, and this
# script is the only one that reads it there.
#   scripts/sparkle-tools.sh      downloads the command line tools once into .build/sparkle, checks
#                                 their SHA-256, and prints the folder of sign_update
#   scripts/sparkle-tools.sh pin  prints the version and the commit of the pin for generate-project.sh
set -e
cd "$(dirname "$0")/.."
VERSION=2.10.1
REVISION=ab7d71291238df6e0492143b120c9b696a35f603
SHA256=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
[ "$(sed -n '/^  Sparkle:$/,/^  [^ ]/s/^ *exactVersion: *//p' App/project.yml)" = "$VERSION" ] || {
	echo "App/project.yml names another version of Sparkle than scripts/sparkle-tools.sh ($VERSION). Change both." >&2; exit 1; }
if [ "$1" = pin ]; then
	echo "$VERSION $REVISION"
	exit 0
fi
DIR=.build/sparkle/$VERSION
if [ ! -x "$DIR/bin/sign_update" ]; then
	mkdir -p "$DIR"
	curl -fsSL -o "$DIR/Sparkle.tar.xz" "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz"
	echo "$SHA256  $DIR/Sparkle.tar.xz" | shasum -a 256 -c >/dev/null || { rm -rf "$DIR"; echo "The Sparkle download has a wrong SHA-256." >&2; exit 1; }
	tar -xf "$DIR/Sparkle.tar.xz" -C "$DIR" ./bin
	rm "$DIR/Sparkle.tar.xz"
fi
echo "$PWD/$DIR/bin"
