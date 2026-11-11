#!/bin/sh
# Builds dist/Moneten.app with Xcode.
#   scripts/build-app.sh                 release build, signed with the team in App/Local.xcconfig
#   scripts/build-app.sh debug           debug build
#   scripts/build-app.sh developer-id    release build, archived and signed with the Developer ID
#                                        of the team, for other Macs; not notarized yet
# Without a team in App/Local.xcconfig, Xcode signs to run locally. App/Signing.xcconfig explains it.
# The Developer ID certificate is managed by Xcode in the team account. The Developer ID build
# needs an Xcode account of the team with the Admin or Account Holder role.
set -e
cd "$(dirname "$0")/.."
CONFIG=Release
case "$1" in
	"") ;;
	debug) CONFIG=Debug ;;
	developer-id) ARCHIVE=.build/xcode/Moneten.xcarchive ;;
	*) echo "usage: scripts/build-app.sh [debug | developer-id]" >&2; exit 2 ;;
esac
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

scripts/generate-project.sh
XCODEBUILD="xcodebuild -project App/Moneten.xcodeproj -scheme Moneten -configuration $CONFIG -derivedDataPath .build/xcode -disableAutomaticPackageResolution -quiet"
if [ -z "$ARCHIVE" ]; then
	$XCODEBUILD CURRENT_PROJECT_VERSION="$BUILD" build
	PRODUCT=".build/xcode/Build/Products/$CONFIG/Moneten.app"
else
	rm -rf "$ARCHIVE" .build/xcode/export
	$XCODEBUILD -archivePath "$ARCHIVE" -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD" archive
	cat > .build/xcode/ExportOptions.plist <<-EOF
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0"><dict>
	<key>method</key><string>developer-id</string>
	<key>signingStyle</key><string>automatic</string>
	</dict></plist>
	EOF
	xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist .build/xcode/ExportOptions.plist \
		-exportPath .build/xcode/export -allowProvisioningUpdates >/dev/null
	PRODUCT=.build/xcode/export/Moneten.app
fi

rm -rf dist/Moneten.app
mkdir -p dist
cp -R "$PRODUCT" dist/
codesign --verify --strict --deep dist/Moneten.app
echo "Built dist/Moneten.app ($CONFIG, build $BUILD), $(codesign -dv --verbose=2 dist/Moneten.app 2>&1 | grep -m1 -E '^(Authority|Signature)=')"
