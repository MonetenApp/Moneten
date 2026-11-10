#!/bin/sh
# Build MonetenMoneten.app into dist/.
#   scripts/build-app.sh            release build
#   scripts/build-app.sh debug      debug build
# Without a Developer ID the app is signed ad hoc. It runs on this Mac.
set -e
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
VERSION="$(cat VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

# --disable-keychain keeps the package manager from waiting for a Keychain prompt about GitHub.
swift build --disable-keychain -c "$CONFIG" --product MonetenMoneten
BIN="$(swift build --disable-keychain -c "$CONFIG" --show-bin-path)"

APP=dist/MonetenMoneten.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/MonetenMoneten" "$APP/Contents/MacOS/"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" scripts/bundle/Info.plist > "$APP/Contents/Info.plist"
[ -f scripts/bundle/AppIcon.icns ] && cp scripts/bundle/AppIcon.icns "$APP/Contents/Resources/"
for bundle in "$BIN"/*.bundle; do
	case "$bundle" in *Tests.bundle) continue ;; esac
	[ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done
printf 'APPL????' > "$APP/Contents/PkgInfo"

# SQLCipher comes as a dynamic framework. The app loads it from Contents/Frameworks.
mkdir -p "$APP/Contents/Frameworks"
for framework in "$BIN"/*.framework; do
	[ -e "$framework" ] && cp -R "$framework" "$APP/Contents/Frameworks/"
done
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/MonetenMoneten" 2>/dev/null || true

IDENTITY="${CODESIGN_IDENTITY:--}"
# The hardened runtime is for notarized builds. An ad hoc signature has no team, and the
# library validation of the hardened runtime would then refuse to load SQLCipher.
RUNTIME=""
[ "$IDENTITY" != "-" ] && RUNTIME="--options runtime"
for framework in "$APP"/Contents/Frameworks/*.framework; do
	[ -e "$framework" ] && codesign --force $RUNTIME --timestamp=none --sign "$IDENTITY" "$framework"
done
codesign --force $RUNTIME --timestamp=none --entitlements scripts/bundle/MonetenMoneten.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP $VERSION ($BUILD), signed with ${IDENTITY}"
