#!/bin/sh
# Builds dist/Moneten.app with Xcode.
#   scripts/build-app.sh                 release build, signed with the team in App/Local.xcconfig
#   scripts/build-app.sh debug           debug build
#   scripts/build-app.sh developer-id    release build, archived and signed with the Developer ID
#                                        of the team, for other Macs; not notarized yet
# Without a team in App/Local.xcconfig, Xcode signs to run locally. App/Signing.xcconfig explains it.
# The Developer ID certificate is managed by Xcode in the team account. The Developer ID build
# needs an Xcode account of the team with the Admin or Account Holder role.
# Every build except developer-id adds the FinTS helper (ADR 0014) and needs a JDK 17 or later. It takes the FinTS
# product ID from the login Keychain, item "Moneten FinTS product ID", into Info.plist. Without it
# the app builds, and FinTS refuses to connect.
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

# Adds the FinTS helper to the app $1 and signs both again with the certificate of the app. It runs
# after the export, because the export signs the app with the Developer ID but would leave the
# helper with the signature of the archive. The helper lives in Contents/Resources, because codesign
# takes every file in Contents/Helpers for code, and the Java runtime needs its data files next to
# its libraries. The helper gets the hardened
# runtime when the app has it: an ad hoc signature has no team, and library validation would refuse
# the libraries of the Java runtime. Only the helper gets allow-jit.
embed_fints_helper() {
	HELPER="$1/Contents/Resources/FinTSHelper"
	scripts/build-fints-helper.sh --bundle "$HELPER" >/dev/null
	CERTS=$(mktemp -d)
	codesign -d --extract-certificates="$CERTS/cert" "$1" 2>/dev/null
	IDENTITY=-
	[ -f "$CERTS/cert0" ] && IDENTITY=$(shasum -a 1 "$CERTS/cert0" | cut -d' ' -f1)
	rm -rf "$CERTS"
	# Notarization needs a secure timestamp on every signature, which an ad hoc signature cannot have.
	TIMESTAMP=""
	[ "$IDENTITY" = - ] || TIMESTAMP="--timestamp"
	RUNTIME=""
	codesign -dv "$1" 2>&1 | grep -q '^CodeDirectory.*flags=.*runtime' && RUNTIME="--options runtime"
	# A file list instead of a pipe, so that a failed signature stops the build. codesign needs the
	# private key of the identity in the Keychain; a certificate that only Xcode manages fails here.
	CODE=$(mktemp)
	find "$HELPER/runtime" -type f ! -path '*/bin/java' > "$CODE.all"
	while read -r f; do file -b "$f" | grep -q Mach-O && echo "$f"; done < "$CODE.all" > "$CODE"
	rm "$CODE.all"
	while read -r f; do
		codesign --force $RUNTIME $TIMESTAMP --sign "$IDENTITY" "$f" || { echo "Could not sign $f of the FinTS helper." >&2; exit 1; }
	done < "$CODE"
	codesign --force $RUNTIME $TIMESTAMP --entitlements App/FinTSHelper.entitlements --sign "$IDENTITY" "$HELPER/runtime/bin/java" \
		|| { echo "Could not sign the java of the FinTS helper." >&2; exit 1; }
	# The product ID goes through a pipe, never through an argument, a variable, or a log.
	security find-generic-password -s 'Moneten FinTS product ID' -w 2>/dev/null | python3 -c '
import plistlib, sys
product = sys.stdin.read().strip()
if product:
	with open(sys.argv[1], "rb") as f: info = plistlib.load(f)
	info["MonetenFinTSProductID"] = product
	with open(sys.argv[1], "wb") as f: plistlib.dump(info, f)
else:
	print("No FinTS product ID in the login Keychain. The app builds, and FinTS refuses to connect.", file=sys.stderr)
' "$1/Contents/Info.plist"
	codesign --force --preserve-metadata=identifier,entitlements,requirements,flags,runtime $TIMESTAMP --sign "$IDENTITY" "$1" || { echo "Could not sign the app again after adding the FinTS helper." >&2; exit 1; }
	signer() { codesign -dvv "$1" 2>&1 | grep -E '^(Authority|Signature|TeamIdentifier)='; }
	APP_SIGNER=$(signer "$1")
	echo "$HELPER/runtime/bin/java" >> "$CODE"
	while read -r f; do
		[ "$(signer "$f")" = "$APP_SIGNER" ] || { echo "$f of the FinTS helper is not signed like the app." >&2; exit 1; }
	done < "$CODE"
	rm "$CODE"
}

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
# The export of a Developer ID build signs with a certificate that Xcode may keep in the cloud, and
# codesign cannot sign the helper with it. Until task 3.2 of add-fints-banking lets the export sign
# the helper, a Developer ID build leaves it out. The app does not use FinTS yet.
if [ -z "$ARCHIVE" ]; then
	embed_fints_helper dist/Moneten.app
else
	echo "The Developer ID build leaves out the FinTS helper until task 3.2 of add-fints-banking." >&2
fi
codesign --verify --strict --deep dist/Moneten.app
echo "Built dist/Moneten.app ($CONFIG, build $BUILD), $(codesign -dv --verbose=2 dist/Moneten.app 2>&1 | grep -m1 -E '^(Authority|Signature)=')"
