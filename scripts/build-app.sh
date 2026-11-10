#!/bin/sh
# Builds dist/MonetenMoneten.app with Xcode.
#   scripts/build-app.sh          release build
#   scripts/build-app.sh debug    debug build
# Without a team in App/Local.xcconfig, Xcode signs to run locally. App/Signing.xcconfig explains it.
set -e
cd "$(dirname "$0")/.."
CONFIG=Release
[ "$1" = debug ] && CONFIG=Debug
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

scripts/generate-project.sh
xcodebuild -project App/MonetenMoneten.xcodeproj -scheme MonetenMoneten -configuration "$CONFIG" \
	-derivedDataPath .build/xcode -disableAutomaticPackageResolution -quiet \
	CURRENT_PROJECT_VERSION="$BUILD" build

rm -rf dist/MonetenMoneten.app
mkdir -p dist
cp -R ".build/xcode/Build/Products/$CONFIG/MonetenMoneten.app" dist/
codesign --verify --strict --deep dist/MonetenMoneten.app
echo "Built dist/MonetenMoneten.app ($CONFIG, build $BUILD), $(codesign -dv dist/MonetenMoneten.app 2>&1 | grep -m1 -E '^(Authority|Signature)=')"
