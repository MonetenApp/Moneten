#!/bin/sh
# Downloads the command line tools of Sparkle once into .build/sparkle, checks their SHA-256, and
# prints the folder of sign_update. The version is the one of the Sparkle package of the app.
set -e
cd "$(dirname "$0")/.."
VERSION=2.10.1
SHA256=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
[ "$(sed -n '/^  Sparkle:$/,/^  [^ ]/s/^ *exactVersion: *//p' App/project.yml)" = "$VERSION" ] || {
	echo "App/project.yml names another version of Sparkle than scripts/sparkle-tools.sh ($VERSION). Change both, and scripts/generate-project.sh." >&2; exit 1; }
DIR=.build/sparkle/$VERSION
if [ ! -x "$DIR/bin/sign_update" ]; then
	mkdir -p "$DIR"
	curl -fsSL -o "$DIR/Sparkle.tar.xz" "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz"
	echo "$SHA256  $DIR/Sparkle.tar.xz" | shasum -a 256 -c >/dev/null || { rm -rf "$DIR"; echo "The Sparkle download has a wrong SHA-256." >&2; exit 1; }
	tar -xf "$DIR/Sparkle.tar.xz" -C "$DIR" ./bin
	rm "$DIR/Sparkle.tar.xz"
fi
echo "$PWD/$DIR/bin"
