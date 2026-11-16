#!/bin/sh
# Downloads a pinned build tool once into .build/tools, checks its SHA-256, and prints its folder.
# scripts/release.sh takes both tools from here, so the job that holds the Developer ID and the
# notary key runs no tool whose version floats.
#   scripts/build-tools.sh xcodegen  the folder of the xcodegen binary
#   scripts/build-tools.sh jdk       the home of the JDK whose jlink runtime ships inside the app.
#                                    The jdk line of Tools/FinTSProbeJava/dependencies.lock pins
#                                    the Temurin build and its SHA-256.
set -e
cd "$(dirname "$0")/.."
fail() { echo "$*" >&2; exit 1; }
# Downloads $1 to $3 and keeps it only when its SHA-256 is $2.
fetch() {
	curl -fsSL -o "$3" "$1" || fail "The download of $1 failed."
	echo "$2  $3" | shasum -a 256 -c >/dev/null 2>&1 || { rm -f "$3"; fail "The download of $1 has a wrong SHA-256."; }
}
case "$1" in
xcodegen)
	VERSION=2.46.0
	SHA256=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
	DIR=.build/tools/xcodegen-$VERSION
	if [ ! -x "$DIR/xcodegen/bin/xcodegen" ]; then
		rm -rf "$DIR" "$DIR.part"
		mkdir -p "$DIR.part"
		fetch "https://github.com/yonaskolb/XcodeGen/releases/download/$VERSION/xcodegen.zip" "$SHA256" "$DIR.part/xcodegen.zip"
		ditto -x -k "$DIR.part/xcodegen.zip" "$DIR.part"
		rm "$DIR.part/xcodegen.zip"
		mv "$DIR.part" "$DIR"
	fi
	echo "$PWD/$DIR/xcodegen/bin"
	;;
jdk)
	[ "$(uname -m)" = arm64 ] || fail "The pinned JDK is the one for Apple silicon."
	set -- $(grep '^jdk:temurin-aarch64-mac:' Tools/FinTSProbeJava/dependencies.lock)
	VERSION=${1##*:}
	SHA256=$2
	[ -n "$VERSION" ] && [ -n "$SHA256" ] || fail "Tools/FinTSProbeJava/dependencies.lock has no jdk line."
	DIR=.build/tools/jdk-$VERSION
	if [ ! -x "$DIR/Contents/Home/bin/jlink" ]; then
		rm -rf "$DIR" "$DIR.part"
		mkdir -p "$DIR.part"
		FILE=OpenJDK${VERSION%%.*}U-jdk_aarch64_mac_hotspot_$(echo "$VERSION" | tr + _).tar.gz
		fetch "https://github.com/adoptium/temurin${VERSION%%.*}-binaries/releases/download/jdk-${VERSION%+*}%2B${VERSION#*+}/$FILE" "$SHA256" "$DIR.part/jdk.tar.gz"
		tar -xzf "$DIR.part/jdk.tar.gz" -C "$DIR.part" --strip-components 1
		rm "$DIR.part/jdk.tar.gz"
		mv "$DIR.part" "$DIR"
	fi
	echo "$PWD/$DIR/Contents/Home"
	;;
*) fail "usage: scripts/build-tools.sh xcodegen | jdk" ;;
esac
