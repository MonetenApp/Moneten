#!/bin/sh
# Builds HBCI4Swift.framework from the unchanged sources in Vendor/HBCI4Swift into
# .build/hbci4swift/HBCI4Swift.framework, for Apple silicon and Intel.
# The Xcode project of HBCI4Swift sets macOS 10.13, which Xcode 27 no longer builds, so this script
# sets the deployment target of the app instead. ADR 0011 explains why the project does it this way.
# The script skips the build when the framework matches the commit of the submodule.
set -e
cd "$(dirname "$0")/.."
[ -f Vendor/HBCI4Swift/HBCI4Swift/HBCI4Swift.xcodeproj/project.pbxproj ] || git submodule update --init Vendor/HBCI4Swift
OUT=.build/hbci4swift
COMMIT="$(git -C Vendor/HBCI4Swift rev-parse HEAD)"
if [ -d "$OUT/HBCI4Swift.framework" ] && [ "$(cat "$OUT/commit" 2>/dev/null)" = "$COMMIT" ]; then
	exit 0
fi

rm -rf "$OUT"
xcodebuild -project Vendor/HBCI4Swift/HBCI4Swift/HBCI4Swift.xcodeproj -scheme HBCI4Swift -configuration Release \
	-derivedDataPath "$OUT/derived" -quiet \
	MACOSX_DEPLOYMENT_TARGET=15.0 ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
	SWIFT_SUPPRESS_WARNINGS=YES GCC_WARN_INHIBIT_ALL_WARNINGS=YES build
# PCSCard holds only the module map of the PC/SC headers. The compiler needs it to import HBCI4Swift.
cp -R "$OUT/derived/Build/Products/Release/HBCI4Swift.framework" "$OUT/derived/Build/Products/Release/PCSCard.framework" "$OUT/"
echo "$COMMIT" > "$OUT/commit"
echo "Built $OUT/HBCI4Swift.framework from HBCI4Swift $(echo "$COMMIT" | cut -c1-7)"
