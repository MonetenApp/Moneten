#!/bin/sh
# Builds dist/Moneten.app with Xcode.
#   scripts/build-app.sh                 release build, signed with the team in App/Local.xcconfig
#   scripts/build-app.sh debug           debug build
#   scripts/build-app.sh developer-id    release build, archived and signed with the Developer ID
#                                        Application certificate in the Keychain, with the hardened
#                                        runtime and a secure timestamp, for notarization (ADR 0016)
# A Release build also writes dist/Moneten.dSYMs with the dSYMs of the binaries in the app, which
# scripts/release.sh zips and checks against the app.
# Without a team in App/Local.xcconfig, Xcode signs to run locally. App/Signing.xcconfig explains it.
# The Developer ID build takes the team from MONETEN_TEAM_ID or else from App/Local.xcconfig, and
# needs the certificate with its private key in the Keychain. docs/releasing.md explains both.
# MONETEN_VERSION, for example 0.2.0-beta.1, sets the version: 0.2.0 as the marketing version and
# beta.1 as MonetenPreRelease in Info.plist. Without it the build has the version of App/project.yml.
# Every build adds the FinTS helper (ADR 0014) and needs a JDK 17 or later. It takes the FinTS
# product ID from the file that MONETEN_FINTS_PRODUCT_ID_FILE names, or else from the login
# Keychain, item "Moneten FinTS product ID", into Info.plist. Without it the app builds, and FinTS
# refuses to connect.
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
VERSION_SETTINGS=""
if [ -n "$MONETEN_VERSION" ]; then
	echo "$MONETEN_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$' \
		|| { echo "MONETEN_VERSION must look like 1.2.3 or 1.2.3-beta.4, not $MONETEN_VERSION." >&2; exit 2; }
	VERSION_SETTINGS="MARKETING_VERSION=${MONETEN_VERSION%%-*} MONETEN_PRE_RELEASE=$(echo "$MONETEN_VERSION" | sed -n 's/^[^-]*-//p')"
fi

# Adds the FinTS helper to the app $1 after the build and signs both again with the certificate of
# the app, which must be in the Keychain with its private key. The helper lives in Contents/Resources, because codesign
# takes every file in Contents/Helpers for code, and the Java runtime needs its data files next to
# its libraries. The helper gets the hardened runtime when the app has it. Only the helper gets
# allow-jit. Signed to run locally, it also turns off library validation, as the app does: an ad
# hoc signature has no team, and library validation would refuse the libraries of the Java runtime.
# Its java runs in the app sandbox with the signing identifier <app>.FinTSHelper, which names its
# container (ADR 0018).
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
	# A Developer ID build signs with the imported certificate of ADR 0016, so it never fails here.
	CODE=$(mktemp)
	find "$HELPER/runtime" -type f > "$CODE.all"
	while read -r f; do file -b "$f" | grep -q Mach-O && echo "$f"; done < "$CODE.all" > "$CODE"
	rm "$CODE.all"
	while read -r f; do
		codesign --force $RUNTIME $TIMESTAMP --sign "$IDENTITY" "$f" || { echo "Could not sign $f of the FinTS helper." >&2; exit 1; }
	done < "$CODE"
	ENTITLEMENTS=App/FinTSHelper.entitlements
	[ "$IDENTITY" = - ] && [ -n "$RUNTIME" ] && ENTITLEMENTS=App/FinTSHelperLocal.entitlements
	codesign --force $RUNTIME $TIMESTAMP --entitlements "$ENTITLEMENTS" \
		--identifier "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$1/Contents/Info.plist").FinTSHelper" --sign "$IDENTITY" "$HELPER/java" \
		|| { echo "Could not sign the java of the FinTS helper." >&2; exit 1; }
	# The product ID goes through a pipe, never through an argument, a variable, or a log.
	if [ -n "$MONETEN_FINTS_PRODUCT_ID_FILE" ]; then
		cat "$MONETEN_FINTS_PRODUCT_ID_FILE"
	else
		security find-generic-password -s 'Moneten FinTS product ID' -w 2>/dev/null
	fi | python3 -c '
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
	echo "$HELPER/java" >> "$CODE"
	while read -r f; do
		[ "$(signer "$f")" = "$APP_SIGNER" ] || { echo "$f of the FinTS helper is not signed like the app." >&2; exit 1; }
	done < "$CODE"
	rm "$CODE"
}

# Xcode builds the extension host of ADR 0015 into Contents/Helpers and signs it like the app. This
# check stops a build whose host could do more than reach the network, or is signed by someone else.
check_extension_host() {
	HOST="$1/Contents/Helpers/MonetenExtensionHost"
	[ -x "$HOST" ] || { echo "The extension host is missing in $1." >&2; exit 1; }
	codesign -d --entitlements - --xml "$HOST" 2>/dev/null | python3 -c '
import plistlib, sys
entitlements = plistlib.loads(sys.stdin.buffer.read())
if entitlements != {"com.apple.security.app-sandbox": True, "com.apple.security.network.client": True}:
	sys.exit("The extension host has the entitlements %s instead of the app sandbox and the network client." % sorted(entitlements))
' || exit 1
	signer() { codesign -dvv "$1" 2>&1 | grep -E '^(Authority|Signature|TeamIdentifier)='; }
	[ "$(signer "$HOST")" = "$(signer "$1")" ] || { echo "The extension host is not signed like the app." >&2; exit 1; }
}

# The java of the FinTS helper holds the PIN and parses the answers of the bank (ADR 0018). This check
# stops a build whose java could do more than reach the network or has another container, and runs one
# login over TLS in the sandbox against a made-up bank on 127.0.0.1, so that a file or a connection the
# sandbox refuses fails the build on this Mac and not a refresh. Only an ad hoc signature with the
# hardened runtime may also turn library validation off (ADR 0017), never a signature with a team.
check_fints_helper() {
	HELPER="$1/Contents/Resources/FinTSHelper"
	ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$1/Contents/Info.plist").FinTSHelper"
	[ "$(codesign -dv "$HELPER/java" 2>&1 | sed -n 's/^Identifier=//p')" = "$ID" ] \
		|| { echo "The java of the FinTS helper is not signed with the identifier $ID, which names its container." >&2; exit 1; }
	LOCAL=no
	codesign -dv "$HELPER/java" 2>&1 | grep -q '^CodeDirectory.*flags=.*adhoc.*runtime' && LOCAL=yes
	codesign -d --entitlements - --xml "$HELPER/java" 2>/dev/null | python3 -c '
import plistlib, sys
entitlements = plistlib.loads(sys.stdin.buffer.read())
expected = {"com.apple.security.app-sandbox": True, "com.apple.security.network.client": True, "com.apple.security.cs.allow-jit": True}
local = dict(expected, **{"com.apple.security.cs.disable-library-validation": True})
if entitlements != expected and not (sys.argv[1] == "yes" and entitlements == local):
	sys.exit("The java of the FinTS helper has the entitlements %s instead of the app sandbox, the network client, and JIT." % sorted(entitlements))
' "$LOCAL" || exit 1
	python3 scripts/fints-helper-smoke.py "$HELPER" || exit 1
}

# A Release build is hardened (ADR 0017): the app, the extension host, and the java of the FinTS
# helper have the hardened runtime, and none of them lets another process attach.
check_hardened() {
	# Only a build without a team may turn library validation off (App/Signing.xcconfig).
	TEAM_OF_APP=$(codesign -dv "$1" 2>&1 | sed -n 's/^TeamIdentifier=//p')
	for code in "$1" "$1/Contents/Helpers/MonetenExtensionHost" "$1/Contents/Resources/FinTSHelper/java"; do
		codesign -dv "$code" 2>&1 | grep -q '^CodeDirectory.*flags=.*runtime' || { echo "$code has no hardened runtime." >&2; exit 1; }
		codesign -d --entitlements - --xml "$code" 2>/dev/null | grep -q get-task-allow && { echo "$code lets other processes attach." >&2; exit 1; }
		if [ -n "$TEAM_OF_APP" ] && [ "$TEAM_OF_APP" != "not set" ]; then
			codesign -d --entitlements - --xml "$code" 2>/dev/null | grep -q disable-library-validation \
				&& { echo "$code turns library validation off, which only a build without a team may do." >&2; exit 1; }
		fi
	done
	return 0
}

# Copies each dSYM in the folder $1 that belongs to a binary of the app dist/Moneten.app to
# dist/Moneten.dSYMs: the app, the extension host, SQLCipher, and Sparkle with its helpers. The Java
# runtime of the FinTS helper has none. scripts/release.sh checks that every other binary has one.
copy_symbols() {
	mkdir dist/Moneten.dSYMs
	UUIDS=$(mktemp)
	find dist/Moneten.app/Contents -type f ! -path '*/Contents/Resources/FinTSHelper/*' | while read -r f; do
		file -b "$f" | grep -q '^Mach-O' && dwarfdump --uuid "$f"
	done | awk '{ print $2 }' > "$UUIDS"
	for dsym in "$1"/*.dSYM; do
		[ -d "$dsym" ] || continue
		dwarfdump --uuid "$dsym" | awk '{ print $2 }' | grep -qxFf "$UUIDS" && ditto "$dsym" "dist/Moneten.dSYMs/${dsym##*/}"
	done
	rm "$UUIDS"
	[ -d dist/Moneten.dSYMs/Moneten.app.dSYM ] \
		|| { echo "The build wrote no dSYM of the app. App/project.yml must keep DWARF with dSYM File for Release." >&2; exit 1; }
}

scripts/generate-project.sh
# SWIFT_EMIT_LOC_STRINGS also for the libraries, so that scripts/check-localization.py can read their texts.
XCODEBUILD="xcodebuild -project App/Moneten.xcodeproj -scheme Moneten -configuration $CONFIG -derivedDataPath .build/xcode -disableAutomaticPackageResolution -quiet SWIFT_EMIT_LOC_STRINGS=YES"
if [ -z "$ARCHIVE" ]; then
	$XCODEBUILD CURRENT_PROJECT_VERSION="$BUILD" $VERSION_SETTINGS build
	PRODUCT=".build/xcode/Build/Products/$CONFIG/Moneten.app"
	SYMBOLS=".build/xcode/Build/Products/$CONFIG"
else
	TEAM="$MONETEN_TEAM_ID"
	[ -n "$TEAM" ] || TEAM=$(sed -n 's/^DEVELOPMENT_TEAM *= *\([A-Z0-9]*\).*/\1/p' App/Local.xcconfig 2>/dev/null | tail -1)
	[ -n "$TEAM" ] || { echo "The Developer ID build needs a team in MONETEN_TEAM_ID or App/Local.xcconfig." >&2; exit 2; }
	security find-identity -v -p codesigning | grep -q "Developer ID Application: .*($TEAM)" \
		|| { echo "No Developer ID Application certificate of team $TEAM with its private key in the Keychain. See docs/releasing.md." >&2; exit 1; }
	# Manual signing with the certificate in the Keychain, so that codesign can sign the FinTS helper
	# with the same identity after the export (ADR 0016). No entitlement of the app needs a profile.
	SIGNING="CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=$TEAM MONETEN_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp"
	rm -rf "$ARCHIVE" .build/xcode/export
	$XCODEBUILD -archivePath "$ARCHIVE" $SIGNING CODE_SIGN_IDENTITY="Developer ID Application" \
		CURRENT_PROJECT_VERSION="$BUILD" $VERSION_SETTINGS archive
	cat > .build/xcode/ExportOptions.plist <<-EOF
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0"><dict>
	<key>method</key><string>developer-id</string>
	<key>signingStyle</key><string>manual</string>
	<key>signingCertificate</key><string>Developer ID Application</string>
	<key>teamID</key><string>$TEAM</string>
	</dict></plist>
	EOF
	xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist .build/xcode/ExportOptions.plist \
		-exportPath .build/xcode/export >/dev/null
	PRODUCT=.build/xcode/export/Moneten.app
	SYMBOLS="$ARCHIVE/dSYMs"
fi

rm -rf dist/Moneten.app dist/Moneten.dSYMs
mkdir -p dist
cp -R "$PRODUCT" dist/
[ "$CONFIG" = Debug ] || copy_symbols "$SYMBOLS"
embed_fints_helper dist/Moneten.app
check_fints_helper dist/Moneten.app
check_extension_host dist/Moneten.app
[ "$CONFIG" = Debug ] || check_hardened dist/Moneten.app
codesign --verify --strict --deep dist/Moneten.app
echo "Built dist/Moneten.app ($CONFIG, build $BUILD), $(codesign -dv --verbose=2 dist/Moneten.app 2>&1 | grep -m1 -E '^(Authority|Signature)=')"
