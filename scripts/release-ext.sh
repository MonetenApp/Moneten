#!/bin/sh
# Builds, signs, notarizes, and checks a release of the ext tool for extension authors.
# .github/workflows/release-ext.yml runs it, and docs/releasing-ext.md explains the secrets and the steps.
#   scripts/release-ext.sh dry-run             the release without secrets: the same zip, signed to run locally
#   scripts/release-ext.sh check-tag <version> the tag names the version of Tools/ext/Ext.swift and lies on main
#   scripts/release-ext.sh package <version>   the universal binary with the commit, signed with the Developer ID,
#                                              notarized, and checked, as a zip with its SHA-256 in dist/ext
# Signing needs the Developer ID certificate in the Keychain and MONETEN_TEAM_ID. Notarization needs
# MONETEN_NOTARY_KEY (the path of the .p8 file), MONETEN_NOTARY_KEY_ID, and MONETEN_NOTARY_ISSUER.
set -e
cd "$(dirname "$0")/.."
REPO=MonetenApp/Moneten
OUT=dist/ext
# The key that Ext.commitKey reads.
COMMIT_KEY=MonetenCommit
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

fail() { echo "$*" >&2; exit 1; }
source_version() { sed -n 's/^[[:space:]]*static let version = "\(.*\)"$/\1/p' Tools/ext/Ext.swift; }
api_version() { sed -n 's/^public let extensionAPIVersion = \([0-9]*\)$/\1/p' Sources/ExtensionHost/Manifest.swift; }

check_version() {
	echo "$1" | grep -Eqx '[0-9]+\.[0-9]+\.[0-9]+' || fail "The version $1 is not of the form 1.2.3."
	[ "$1" = "$(source_version)" ] || fail "The tag names ext $1, but Tools/ext/Ext.swift has the version $(source_version)."
}

check_tag() {
	check_version "$1"
	git merge-base --is-ancestor HEAD origin/main 2>/dev/null || fail "The commit of the tag is not on main."
	echo "The tag ext-v$1 matches the tool and lies on main."
}

# The same notarization as notarize() of scripts/release.sh. It is a copy, because that script runs one command
# per call and cannot be sourced. Both can move to a shared script.
notarize() {
	[ -n "$MONETEN_NOTARY_KEY" ] && [ -n "$MONETEN_NOTARY_KEY_ID" ] && [ -n "$MONETEN_NOTARY_ISSUER" ] \
		|| fail "Notarization needs MONETEN_NOTARY_KEY, MONETEN_NOTARY_KEY_ID, and MONETEN_NOTARY_ISSUER."
	FILE="$1"
	set -- --key "$MONETEN_NOTARY_KEY" --key-id "$MONETEN_NOTARY_KEY_ID" --issuer "$MONETEN_NOTARY_ISSUER"
	xcrun notarytool submit "$FILE" "$@" --wait --timeout 1h --output-format json > "$WORK/notary.json" || true
	RESULT=$(python3 -c 'import json, sys; r = json.load(open(sys.argv[1])); print(r.get("id", ""), r.get("status", ""))' "$WORK/notary.json" 2>/dev/null || true)
	if [ "${RESULT#* }" != Accepted ]; then
		[ -z "${RESULT%% *}" ] || xcrun notarytool log "${RESULT%% *}" "$@" >&2 || true
		fail "Apple did not notarize $FILE: ${RESULT:-no answer}."
	fi
	echo "Notarized $FILE."
}

# The SHA-1 of the Developer ID Application identity of the team in the Keychain.
developer_id() {
	[ -n "$MONETEN_TEAM_ID" ] || fail "Signing needs MONETEN_TEAM_ID."
	IDENTITY=$(security find-identity -v -p codesigning \
		| sed -n "s/^ *[0-9]*) \([0-9A-F]\{40\}\) \"Developer ID Application: .*($MONETEN_TEAM_ID)\"$/\1/p" | head -n 1)
	[ -n "$IDENTITY" ] || fail "The Keychain has no Developer ID Application certificate of the team $MONETEN_TEAM_ID."
	echo "$IDENTITY"
}

# Runs the binary $1 as an author would: its version line with the commit $2, and the replay of the example
# extension, which also starts the binary again as its host process.
check_binary() {
	"$1" --version | grep -qxF "ext $VERSION (commit $2), API version $(api_version)" \
		|| fail "ext --version prints \"$("$1" --version)\", without version $VERSION and commit $2."
	"$1" test Extensions/Example Fixtures/example/fixture.json Fixtures/example/expected.json >/dev/null \
		|| fail "The replay of the example extension fails with the built binary."
	# A Mac with Rosetta also runs the Intel half.
	if arch -x86_64 /usr/bin/true 2>/dev/null; then
		arch -x86_64 "$1" --version | grep -qF "(commit $2)" || fail "The Intel part of the binary does not start."
	fi
}

# $2 is "signed" for a release, or "unsigned" for a dry run.
package() {
	VERSION="$1"
	MODE="$2"
	COMMIT=$(git rev-parse HEAD)
	if [ "$MODE" = signed ]; then
		[ -z "$(git status --porcelain --untracked-files=no)" ] || fail "The checkout has changes, so the binary would not match the commit $COMMIT."
		IDENTITY=$(developer_id)
	fi
	rm -rf "$OUT"
	mkdir -p "$OUT"
	cat > "$WORK/Info.plist" <<-EOF
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0">
	<dict>
		<key>CFBundleIdentifier</key>
		<string>io.github.alexander-schneider.Moneten.ext</string>
		<key>CFBundleShortVersionString</key>
		<string>$VERSION</string>
		<key>$COMMIT_KEY</key>
		<string>$COMMIT</string>
	</dict>
	</plist>
	EOF
	# The path of the Info.plist is new on each run, so the build links the binary again with the current commit.
	set -- --disable-keychain -c release --arch arm64 --arch x86_64 --product ext
	swift build "$@" -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$WORK/Info.plist"
	BIN="$WORK/ext"
	cp "$(swift build "$@" --show-bin-path)/ext" "$BIN"
	ARCHS=$(lipo -archs "$BIN")
	case " $ARCHS " in *" arm64 "*) ;; *) fail "The binary has no arm64 part: $ARCHS." ;; esac
	case " $ARCHS " in *" x86_64 "*) ;; *) fail "The binary has no x86_64 part: $ARCHS." ;; esac
	if [ "$MODE" = signed ]; then
		codesign --force --sign "$IDENTITY" --options runtime --timestamp "$BIN"
		codesign -dvv "$BIN" 2>&1 | grep -q '^Authority=Developer ID Application' || fail "ext is not signed with the Developer ID."
		codesign -dv "$BIN" 2>&1 | grep -q 'flags=.*runtime' || fail "ext has no hardened runtime."
		codesign -dv "$BIN" 2>&1 | grep -q '^Timestamp=' || fail "ext has no secure timestamp."
	else
		codesign --force --sign - "$BIN"
	fi
	codesign -dv "$BIN" 2>&1 | grep -qx 'Identifier=io.github.alexander-schneider.Moneten.ext' || fail "ext has another identifier."
	codesign --verify --strict "$BIN"
	ZIP="ext-$VERSION-macos.zip"
	ditto -c -k "$BIN" "$OUT/$ZIP"
	[ "$MODE" != signed ] || notarize "$OUT/$ZIP"
	# The author's view: the binary from the zip.
	mkdir "$WORK/unpacked"
	ditto -x -k "$OUT/$ZIP" "$WORK/unpacked"
	[ "$(ls "$WORK/unpacked")" = ext ] || fail "The zip holds more than ext."
	codesign --verify --strict "$WORK/unpacked/ext"
	check_binary "$WORK/unpacked/ext" "$COMMIT"
	SHA=$(cd "$OUT" && shasum -a 256 "$ZIP" | tee "$ZIP.sha256" | cut -d' ' -f1)
	cat > "$OUT/notes.md" <<-EOF
	The \`ext\` tool for authors of web banking extensions, version $VERSION, built from the commit $COMMIT. It is one universal binary for Apple silicon and Intel Macs with macOS 15 or later, signed with the Developer ID of the project and notarized by Apple.

	SHA-256 of \`$ZIP\`: \`$SHA\`

	\`\`\`sh
	curl -fLO https://github.com/$REPO/releases/download/ext-v$VERSION/$ZIP
	echo "$SHA  $ZIP" | shasum -a 256 -c
	unzip $ZIP
	./ext --version
	\`\`\`

	\`ext --version\` prints "ext $VERSION (commit $COMMIT), API version $(api_version)".
	EOF
	echo "Packaged $OUT/$ZIP ($MODE, commit $COMMIT, SHA-256 $SHA)."
}

case "$1" in
	dry-run) package "$(source_version)" unsigned ;;
	check-tag) [ -n "$2" ] || fail "Usage: scripts/release-ext.sh check-tag <version>"; check_tag "$2" ;;
	package) [ -n "$2" ] || fail "Usage: scripts/release-ext.sh package <version>"; check_version "$2"; package "$2" signed ;;
	*) fail "Usage: scripts/release-ext.sh dry-run | check-tag <version> | package <version>" ;;
esac
