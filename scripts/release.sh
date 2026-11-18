#!/bin/sh
# Builds, signs, notarizes, and drafts a release of Moneten. .github/workflows/release.yml runs it,
# and docs/releasing.md explains the secrets and the steps.
#   scripts/release.sh dry-run [version]  every step without secrets and without GitHub: an app signed
#                                         to run locally, an unsigned disk image, the zip of the
#                                         dSYMs checked against the app, and a feed signed
#                                         with the test update key of Fixtures/update, which a Debug
#                                         build reads. Version 0.0.0-beta.1 by default.
#                                         With MONETEN_SIGN=1 it also signs and notarizes.
#   scripts/release.sh preflight <version>  step 1: the changelog section, the tag on main, and the feed
#   scripts/release.sh package <version>    steps 2 to 4: the signed and notarized app on a notarized
#                                           disk image in dist/release, the zip of its dSYMs, and the
#                                           source archives of the GPL and LGPL parts in dist/release/sources
#   scripts/release.sh feed <version>       step 5: the update signature of the disk image and the new
#                                           signed feed dist/release/appcast.xml
#   scripts/release.sh draft <version>      step 6: the GitHub release as a draft with the disk image,
#                                           the dSYMs, the feed, and the source archives
#   scripts/release.sh publish <version>    step 7, run by the owner: checks the feeds with the committed
#                                           update key, publishes the draft, moves the feed
#                                           of a pre-release to the newest stable release, and updates
#                                           the text of earlier releases from CHANGELOG.md
#   scripts/release.sh withdraw <version>   run by the owner with the update key in the login Keychain:
#                                           checks the current feed with the committed update key, takes
#                                           the version out of it, signs and checks the result, and
#                                           replaces the feed with it
# Signing needs the Developer ID certificate in the Keychain and MONETEN_TEAM_ID. Notarization needs
# MONETEN_NOTARY_KEY (the path of the .p8 file), MONETEN_NOTARY_KEY_ID, and MONETEN_NOTARY_ISSUER.
# The feed needs MONETEN_UPDATE_KEY_FILE, the file with the private EdDSA key. A release needs the
# production public key in App/project.yml in place of the placeholder "none" (docs/releasing.md).
set -e
cd "$(dirname "$0")/.."
REPO=MonetenApp/Moneten
FEED_URL="https://github.com/$REPO/releases/latest/download/appcast.xml"
OUT=dist/release
CHANGELOG=${CHANGELOG:-CHANGELOG.md}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

notes() { python3 scripts/release-notes.py --changelog "$CHANGELOG" "$@"; }
fail() { echo "$*" >&2; exit 1; }
plist() { /usr/libexec/PlistBuddy -c "Print $2" "$1/Contents/Info.plist"; }
dmg_url() { echo "https://github.com/$REPO/releases/download/v$1/Moneten-$1.dmg"; }
TEST_KEY_FILE=Fixtures/update/test-update.key

# The public key of the private key in the file $1. Only for the test key and the throwaway keys of
# the dry run: the production key is checked by the signatures it makes, so it never reaches openssl.
public_key() { notes public-key "$1"; }

# MONETEN_UPDATE_PUBLIC_KEY of the target Moneten in App/project.yml: in its base settings, indented by
# 8 spaces, and in its Debug settings, by 10 inside the block "Debug:". The Perf settings hold the
# placeholder at the same indent, so debug_key reads only the Debug block. check_production_key fails
# when this finds no line or two.
committed_key() { sed -n 's/^ \{8\}MONETEN_UPDATE_PUBLIC_KEY: *//p' App/project.yml; }
debug_key() { awk '/^        [A-Za-z]+:$/ { debug = ($1 == "Debug:") } debug && /^ {10}MONETEN_UPDATE_PUBLIC_KEY:/ { sub(/^ +MONETEN_UPDATE_PUBLIC_KEY: */, ""); print }' App/project.yml; }

# A release must carry one production update key: not the placeholder, and not the public test key.
check_production_key() {
	case "$1" in
		none|"") fail "App/project.yml has no production update key yet. docs/releasing.md explains how the owner adds it." ;;
		"$(debug_key)") fail "The update key is the test key of Fixtures/update, which only Debug builds may trust." ;;
		*[!A-Za-z0-9+/=]*) fail "The update key of App/project.yml is not one key in Base64." ;;
	esac
}

# Fails unless the public update key $2 signed the feed $1 and every disk image in it lies in a
# release of the repository.
check_feed() { notes check-feed --feed "$1" --public-key "$2"; }

# current_feed, and the feed must carry the signature of the public update key $1, because a new
# feed keeps its items and gets a new signature.
checked_current_feed() {
	current_feed
	[ "$FEED_ARGS" = --first-release ] || check_feed "$WORK/current.xml" "$1" || fail "The current feed at $FEED_URL failed its check."
}

# Writes the current feed to $WORK/current.xml and sets FEED_ARGS. Only an answer of GitHub that
# no stable release exists makes this the first release, so a network error never starts an empty feed.
current_feed() {
	set -- -sS -o /dev/null -w '%{http_code}'
	[ -z "$GH_TOKEN" ] || set -- "$@" -H "Authorization: Bearer $GH_TOKEN"
	STATUS=$(curl "$@" "https://api.github.com/repos/$REPO/releases/latest")
	case "$STATUS" in
		404) FEED_ARGS=--first-release; echo "No stable release yet: this is the first feed." ;;
		200) curl -fsSL -o "$WORK/current.xml" "$FEED_URL" || fail "The newest stable release has no readable $FEED_URL."
			FEED_ARGS="--feed $WORK/current.xml" ;;
		*) fail "GitHub answered $STATUS for the newest release." ;;
	esac
}

preflight() {
	check_production_key "$(committed_key)"
	notes check
	notes section "$1" >/dev/null
	[ "$(git rev-parse --is-shallow-repository)" = false ] || fail "The checkout is shallow, so the build number would be wrong."
	git merge-base --is-ancestor HEAD origin/main || fail "The tagged commit is not on main."
	checked_current_feed "$(committed_key)"
	notes check-release "$1" --build "$(git rev-list --count HEAD)" $FEED_ARGS
	echo "Version $1 with build $(git rev-list --count HEAD) can be released."
}

# The certificate hash of the app's signature, so the disk image is signed by the same identity.
identity_of() {
	codesign -d --extract-certificates="$WORK/cert" "$1" 2>/dev/null
	shasum -a 1 "$WORK/cert0" | cut -d' ' -f1
}

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

# Unmounts $1. A scan of the system can keep a fresh volume busy for a few seconds, so it tries
# five times and then forces it.
detach() {
	for _ in 1 2 3 4 5; do hdiutil detach -quiet "$1" 2>/dev/null && return 0; sleep 2; done
	hdiutil detach -quiet -force "$1"
}

# Mounts the disk image $1 read-only and checks the app on it as a user would get it. Writes the
# slices of the app on it to $WORK/app-slices for the check of the dSYMs.
check_dmg() {
	hdiutil verify -quiet "$1"
	hdiutil attach -quiet -nobrowse -readonly -mountpoint "$WORK/volume" "$1"
	MOUNTED="$WORK/volume/Moneten.app"
	unmount_and_fail() { detach "$WORK/volume"; fail "$@"; }
	[ -L "$WORK/volume/Applications" ] || unmount_and_fail "The disk image has no link to the Applications folder."
	codesign --verify --strict --deep "$MOUNTED" || unmount_and_fail "The app on the disk image fails its code signature check."
	[ "$(plist "$MOUNTED" CFBundleShortVersionString)" = "${2%%-*}" ] || unmount_and_fail "The app on the disk image has another version."
	python3 scripts/licenses.py check-app "$MOUNTED" >/dev/null || unmount_and_fail "The app on the disk image lacks license notices."
	JDK_VERSION=$(sed -n 's/^jdk:temurin-aarch64-mac:\([^ ]*\) .*/\1/p' Tools/FinTSProbeJava/dependencies.lock)
	env -i "$MOUNTED/Contents/Resources/FinTSHelper/java" -Xshare:off -version 2>&1 | grep -qF "(build $JDK_VERSION," \
		|| unmount_and_fail "The FinTS helper on the disk image does not start with the pinned Java runtime $JDK_VERSION."
	if [ "$3" = signed ]; then
		spctl --assess --type execute -vv "$MOUNTED" 2>&1 | grep -q 'source=Notarized Developer ID' \
			|| unmount_and_fail "Gatekeeper does not accept the app on the disk image as notarized."
		xcrun stapler validate -q "$MOUNTED" || unmount_and_fail "The app on the disk image has no stapled ticket."
	fi
	app_slices "$MOUNTED" "$WORK/app-slices" || unmount_and_fail "The binaries of the app on the disk image cannot be read."
	detach "$WORK/volume"
}

# "UUID architecture name" of each slice of the Mach-O files named in the file $1, sorted.
slices() {
	while read -r f; do dwarfdump --uuid "$f"; done < "$1" | sed -n 's/^UUID: \([0-9A-F-]*\) (\([^)]*\)) .*\/\([^/]*\)$/\1 \2 \3/p' | sort
}

# Writes to $2 the slices of each Mach-O file in the app $1, except the Java runtime of the FinTS
# helper, which has no dSYM.
app_slices() {
	find "$1/Contents" -type f ! -path '*/Contents/Resources/FinTSHelper/*' > "$WORK/files"
	while read -r f; do file -b "$f" | grep -q '^Mach-O' && echo "$f"; done < "$WORK/files" > "$WORK/binaries"
	slices "$WORK/binaries" > "$2"
	[ -s "$2" ]
}

# Fails unless the dSYMs in the folder $2 have exactly the slices in the file $1: each slice of the
# app needs a dSYM with its UUID, and no dSYM may be left over. Writes the list of their DWARF files
# to $WORK/dwarf.
match_symbols() {
	find "$2" -path '*.dSYM/Contents/Resources/DWARF/*' -type f > "$WORK/dwarf"
	slices "$WORK/dwarf" > "$WORK/dsym-slices"
	diff -u "$1" "$WORK/dsym-slices" >&2 || fail "The dSYMs in $2 do not match the binaries of the app (left: app, right: dSYMs)."
}

# The DWARF files of the dSYMs in the folder $1 that this build compiles: the app and the extension
# host. The other dSYMs come unchanged from the packages Sparkle and SQLCipher, with the paths of
# their own build machines.
own_dwarf() {
	echo "$1/Moneten.app.dSYM/Contents/Resources/DWARF/Moneten"
	echo "$1/MonetenExtensionHost.dSYM/Contents/Resources/DWARF/MonetenExtensionHost"
}

# Fails when one of the files named in the file $1 holds a path in a home folder other than
# /Users/runner/ of the GitHub runner. The app and its dSYMs carry the paths of the checkout they were
# built in, so a release built on the Mac of a maintainer would publish the path of a home folder.
# The message never prints the paths.
check_build_paths() {
	while read -r f; do [ -f "$f" ] || fail "$f is missing."; done < "$1"
	while read -r f; do grep -aohE '/Users/[^/[:cntrl:]]+/' "$f" || true; done < "$1" | sort -u | grep -vx '/Users/runner/' > "$WORK/homes" || true
	[ ! -s "$WORK/homes" ] || fail "The release holds paths in $(wc -l < "$WORK/homes" | tr -d ' ') home folder(s) other than /Users/runner/ of the release workflow. Build releases only in the workflow."
}

# Fails when the dSYMs that this build compiles in the zip $1 hold a path in a home folder other than
# /Users/runner/.
check_zip_paths() {
	rm -rf "$WORK/zip-paths"
	mkdir "$WORK/zip-paths"
	ditto -x -k "$1" "$WORK/zip-paths"
	own_dwarf "$WORK/zip-paths/Moneten.dSYMs" > "$WORK/zip-paths.txt"
	check_build_paths "$WORK/zip-paths.txt"
}

# Prints a crash report with one frame in each slice of the DWARF files named in $WORK/dwarf, at its
# main function or else its first function. Each tool writes to a file before awk reads it: in a pipe,
# the shell takes the status of awk, so a failing tool would leave an empty value, and the error
# would name the symbolication instead of the tool. The script runs without pipefail, because grep -q
# and head close their pipe early, and pipefail turns that into a failure.
frames() {
	while read -r f; do
		dwarfdump --uuid "$f" > "$WORK/uuids" || fail "dwarfdump failed on the dSYM $f."
		sed -n 's/^UUID: \([0-9A-F-]*\) (\([^)]*\)).*/\1 \2/p' "$WORK/uuids" > "$WORK/ids"
		while read -r ID ARCH; do
			nm -arch "$ARCH" -U -n "$f" > "$WORK/nm.txt" || fail "nm failed on the dSYM $f for $ARCH."
			FUNCTION=$(awk '$2 ~ /^[Tt]$/ && $3 == "_main" { print $1; exit }' "$WORK/nm.txt")
			[ -n "$FUNCTION" ] || FUNCTION=$(awk '$2 ~ /^[Tt]$/ { print $1; exit }' "$WORK/nm.txt")
			otool -l -arch "$ARCH" "$f" > "$WORK/otool.txt" || fail "otool failed on the dSYM $f for $ARCH."
			TEXT=$(awk '$1 == "segname" && $2 == "__TEXT" { getline; print $2; exit }' "$WORK/otool.txt")
			[ -n "$FUNCTION" ] && [ -n "$TEXT" ] || fail "The dSYM $f has no function or no __TEXT segment for $ARCH."
			printf 'Frame: %s %s 0x%x\n' "${f##*/}" "$ID" $((0x$FUNCTION - TEXT))
		done < "$WORK/ids"
	done < "$WORK/dwarf"
}

# The frames of the dSYMs of this run stop with a message that names the tool when nm or otool fails,
# and when dwarfdump exits 0 without the UUID of one dSYM or of every dSYM. A stub in front of PATH
# stands in for the tool.
check_frame_tools() {
	mkdir "$WORK/stub"
	for TOOL in nm otool; do
		rm -f "$WORK/stub/"*
		printf '#!/bin/sh\necho "%s: stub failure" >&2\nexit 1\n' "$TOOL" > "$WORK/stub/$TOOL"
		chmod +x "$WORK/stub/$TOOL"
		(PATH="$WORK/stub:$PATH"; resolve_frames > /dev/null) 2>"$WORK/error" && fail "The frames of the dSYMs passed with a failing $TOOL."
		grep -q "^$TOOL failed on the dSYM " "$WORK/error" || fail "A failing $TOOL stopped the frames of the dSYMs with another message: $(cat "$WORK/error")"
	done
	DWARFDUMP=$(command -v dwarfdump)
	for SKIP in MonetenExtensionHost '*'; do
		rm -f "$WORK/stub/"*
		printf '#!/bin/sh\ncase "${2##*/}" in %s) exit 0 ;; esac\nexec "%s" "$@"\n' "$SKIP" "$DWARFDUMP" > "$WORK/stub/dwarfdump"
		chmod +x "$WORK/stub/dwarfdump"
		(PATH="$WORK/stub:$PATH"; resolve_frames > /dev/null) 2>"$WORK/error" \
			&& fail "The frames of the dSYMs passed with a dwarfdump that printed no UUID for $SKIP."
		grep -q "^The crash report of the dSYMs lacks or repeats a slice of them" "$WORK/error" \
			|| fail "A dwarfdump without the UUID of $SKIP stopped the frames of the dSYMs with another message: $(cat "$WORK/error")"
	done
	echo "The check of the dSYMs stops with the name of the tool when nm or otool fails, and stops when dwarfdump prints no UUID for one dSYM or for every dSYM."
}

# Writes to $WORK/report.txt the frames of the dSYMs in $WORK/symbols, and fails unless the report has
# one frame for each slice in $WORK/dsym-slices and scripts/symbolicate-crash.sh resolves each frame to
# a function and its source file, as it does for the report of a user (docs/releasing.md). A dwarfdump
# that exits 0 without a UUID line gives no frame for its dSYM, and the count of resolved frames
# alone would pass a report that lacks them.
resolve_frames() {
	frames > "$WORK/report.txt"
	awk '{ print $3, $2 }' "$WORK/report.txt" | sort > "$WORK/report-slices"
	awk '{ print $1, $3 }' "$WORK/dsym-slices" | sort > "$WORK/want-slices"
	cmp -s "$WORK/report-slices" "$WORK/want-slices" \
		|| fail "The crash report of the dSYMs lacks or repeats a slice of them (left: dSYMs, right: report): $(diff "$WORK/want-slices" "$WORK/report-slices")"
	scripts/symbolicate-crash.sh "$WORK/report.txt" "$WORK/symbols" > "$WORK/symbolicated.txt" \
		|| fail "scripts/symbolicate-crash.sh failed on the dSYMs of the release."
	[ "$(grep -cE '^Frame: .* -> [^0 ].* \(in [^)]+\) \([^)]+:[0-9]+\)$' "$WORK/symbolicated.txt")" = "$(wc -l < "$WORK/report.txt" | tr -d ' ')" ] \
		|| fail "scripts/symbolicate-crash.sh did not resolve every frame to a function and its source file: $(cat "$WORK/symbolicated.txt")"
}

# Zips dist/Moneten.dSYMs to $OUT/Moneten-$1-dSYMs.zip and checks the zip against the slices of the
# app on the disk image, which check_dmg wrote. Then scripts/symbolicate-crash.sh must resolve a report
# with one frame in each slice, at its main function or else its first function, to a function and
# its source file.
symbols() {
	ZIP="$OUT/Moneten-$1-dSYMs.zip"
	[ -d dist/Moneten.dSYMs ] || fail "The build wrote no dist/Moneten.dSYMs."
	ditto -c -k --keepParent dist/Moneten.dSYMs "$ZIP"
	mkdir "$WORK/symbols"
	ditto -x -k "$ZIP" "$WORK/symbols"
	match_symbols "$WORK/app-slices" "$WORK/symbols"
	resolve_frames
	echo "The dSYMs of $(wc -l < "$WORK/dsym-slices" | tr -d ' ') slices match the app on the disk image, and scripts/symbolicate-crash.sh resolves them:"
	sed 's/^/  /' "$WORK/symbolicated.txt"
}

# Steps 2 to 4. $2 is "unsigned" for a dry run without the Developer ID. $3 is "dry-run" for a
# signed dry run, which may still have the placeholder of the update key.
package() {
	MODE=${2:-signed}
	rm -rf "$OUT"
	mkdir -p "$OUT"
	# Every shipped part needs its notice before anything is built, and each GPL or LGPL part its source.
	python3 scripts/licenses.py check
	python3 scripts/licenses.py sources "$OUT/sources" >/dev/null
	# The pinned tools of scripts/build-tools.sh. The jlink runtime of this JDK ships inside the app.
	JAVA_HOME=$(scripts/build-tools.sh jdk)
	PATH="$(scripts/build-tools.sh xcodegen):$PATH"
	export JAVA_HOME PATH
	if [ "$MODE" = signed ]; then
		MONETEN_VERSION="$1" scripts/build-app.sh developer-id
		APP=dist/Moneten.app
		codesign -dvv "$APP" 2>&1 | grep -q '^Authority=Developer ID Application' || fail "The app is not signed with the Developer ID."
		codesign -dv "$APP" 2>&1 | grep -q 'flags=.*runtime' || fail "The app has no hardened runtime."
		plist "$APP" MonetenFinTSProductID >/dev/null 2>&1 || fail "The app has no FinTS product ID. See docs/releasing.md."
		if [ "$3" != dry-run ]; then
			check_production_key "$(plist "$APP" SUPublicEDKey)"
			[ "$(plist "$APP" SUPublicEDKey)" = "$(committed_key)" ] || fail "The app carries another update key than App/project.yml."
			{ echo "$APP/Contents/MacOS/Moneten"; echo "$APP/Contents/Helpers/MonetenExtensionHost"; own_dwarf dist/Moneten.dSYMs; } > "$WORK/built.txt"
			check_build_paths "$WORK/built.txt"
		fi
		# The dSYMs must match before the app goes to Apple. symbols checks them again on the disk image.
		app_slices "$APP" "$WORK/built-slices" || fail "The binaries of $APP cannot be read."
		match_symbols "$WORK/built-slices" dist/Moneten.dSYMs
		ditto -c -k --keepParent "$APP" "$WORK/Moneten.zip"
		notarize "$WORK/Moneten.zip"
		xcrun stapler staple -q "$APP"
	else
		MONETEN_VERSION="$1" scripts/build-app.sh
		APP=dist/Moneten.app
	fi
	DMG="$OUT/Moneten-$1.dmg"
	mkdir "$WORK/stage"
	ditto "$APP" "$WORK/stage/Moneten.app"
	ln -s /Applications "$WORK/stage/Applications"
	hdiutil create -quiet -volname Moneten -srcfolder "$WORK/stage" -fs HFS+ -format ULFO -ov "$DMG"
	if [ "$MODE" = signed ]; then
		codesign --sign "$(identity_of "$APP")" --timestamp "$DMG"
		notarize "$DMG"
		xcrun stapler staple -q "$DMG"
		spctl --assess --type open --context context:primary-signature -vv "$DMG" 2>&1 | grep -q 'source=Notarized Developer ID' \
			|| fail "Gatekeeper does not accept the disk image as notarized."
	fi
	check_dmg "$DMG" "$1" "$MODE"
	symbols "$1"
	cat > "$OUT/build.env" <<-EOF
	VERSION=$1
	BUILD=$(plist "$APP" CFBundleVersion)
	MIN_MACOS=$(plist "$APP" LSMinimumSystemVersion)
	UPDATE_KEY=$(plist "$APP" SUPublicEDKey)
	EOF
	echo "Packaged $DMG ($MODE, build $(plist "$APP" CFBundleVersion))."
}

# Step 5. $2 is "first" for a dry run, which reads no feed from GitHub.
feed() {
	[ -f "$MONETEN_UPDATE_KEY_FILE" ] || fail "The feed needs MONETEN_UPDATE_KEY_FILE, the private update key."
	. "./$OUT/build.env"
	[ "$VERSION" = "$1" ] || fail "dist/release holds version $VERSION, not $1."
	SPARKLE=$(scripts/sparkle-tools.sh)
	DMG="$OUT/Moneten-$1.dmg"
	SIGNATURE=$("$SPARKLE/sign_update" --ed-key-file "$MONETEN_UPDATE_KEY_FILE" -p "$DMG")
	"$SPARKLE/sign_update" --verify --ed-key-file "$MONETEN_UPDATE_KEY_FILE" "$DMG" "$SIGNATURE"
	if [ "$2" = first ]; then FEED_ARGS=--first-release; else checked_current_feed "$UPDATE_KEY"; fi
	notes appcast "$1" --build "$BUILD" --min-macos "$MIN_MACOS" --url "$(dmg_url "$1")" \
		--length "$(stat -f%z "$DMG")" --signature "$SIGNATURE" $FEED_ARGS --out "$OUT/appcast.xml"
	"$SPARKLE/sign_update" --ed-key-file "$MONETEN_UPDATE_KEY_FILE" "$OUT/appcast.xml" >/dev/null
	"$SPARKLE/sign_update" --verify --ed-key-file "$MONETEN_UPDATE_KEY_FILE" "$OUT/appcast.xml"
	# A feed that the installed apps cannot check would stop every update. A dry run builds Release with
	# the production key in its Info.plist, but signs its feed with the test key and checks it in check_feeds.
	if [ "$2" != first ]; then
		check_feed "$OUT/appcast.xml" "$UPDATE_KEY" || fail "MONETEN_UPDATE_KEY_FILE is not the private half of the update key in the app."
	fi
	echo "Wrote the signed feed $OUT/appcast.xml."
}

# Writes $WORK/withdrawn/appcast.xml: the current feed without version $1. remove checks first that
# the public update key $2 signed the current feed, so the new signature never covers a forged item.
# sign_update signs the result with the private key in the file $3, or without $3 with the key in the
# login Keychain, and the result passes the same check before anything uploads it.
withdrawn_feed() {
	current_feed
	[ "$FEED_ARGS" != --first-release ] || fail "No stable release carries a feed yet."
	mkdir -p "$WORK/withdrawn"
	notes remove "$1" --feed "$WORK/current.xml" --public-key "$2" --out "$WORK/withdrawn/appcast.xml" \
		|| fail "The current feed at $FEED_URL failed its check, so nothing was signed."
	"$(scripts/sparkle-tools.sh)/sign_update" ${3:+--ed-key-file "$3"} "$WORK/withdrawn/appcast.xml" >/dev/null
	check_feed "$WORK/withdrawn/appcast.xml" "$2" || fail "The feed without $1 failed its check, so nothing was uploaded."
}

# The id of the asset appcast.xml of the release with the tag $1.
feed_asset() { gh api "repos/$REPO/releases/tags/$1" -q '.assets[] | select(.name == "appcast.xml") | .id'; }

# Writes the asset with the id $1 to the file $2.
release_feed() { gh api -H 'Accept: application/octet-stream' "repos/$REPO/releases/assets/$1" > "$2"; }

# Sets ASSET to the id of appcast.xml of the release $1, and fails unless that asset is still
# $WORK/current.xml, byte for byte, the feed that the command read. A publish or a withdrawal in
# between replaced that feed, or made another release the newest. A new feed made from the old one
# would then drop what the other command did, and carry the revision of a feed that apps already read.
check_unchanged_feed() {
	ASSET=$(feed_asset "$1") || ASSET=""
	rm -f "$WORK/live.xml"
	[ -n "$ASSET" ] && release_feed "$ASSET" "$WORK/live.xml" && cmp -s "$WORK/current.xml" "$WORK/live.xml"
}

# Replaces the asset $2, appcast.xml of the release $1 that check_unchanged_feed compared, with the
# file $3, which is named appcast.xml. The delete names the asset by its id, so it fails when a publish
# or a withdrawal replaced that asset after the comparison, and the upload without --clobber fails when
# one of them uploaded a feed after the delete. So of a publish and a withdrawal at the same time, only
# one replaces the feed that both read, and the other one stops without overwriting it. When the
# upload fails, it tries to upload the feed that it deleted again. It prints why it failed, and returns
# 1 when the feed of $1 is the one it read, and 2 when that try failed too. The release then holds no
# feed, an asset that a failed upload left half written, the new feed whose upload reported an error
# but arrived, or the feed of a command at the same time. The exit trap deletes $WORK, so it keeps
# both feeds in $OUT and prints how to recover.
replace_feed() {
	if ! gh api -X DELETE "repos/$REPO/releases/assets/$2" > /dev/null; then
		echo "The feed of $1 changed after it was read: a publish or a withdrawal ran at the same time. Nothing was uploaded." >&2
		return 1
	fi
	gh release upload "$1" --repo "$REPO" "$3" && return 0
	mkdir -p "$WORK/restore"
	cp "$WORK/current.xml" "$WORK/restore/appcast.xml"
	if gh release upload "$1" --repo "$REPO" "$WORK/restore/appcast.xml"; then
		echo "The upload of the new feed to $1 failed, so the feed that was there before is back." >&2
		return 1
	fi
	KEPT="$OUT/feeds-$1"
	mkdir -p "$KEPT/before" "$KEPT/new" && KEPT=$(cd "$KEPT" && pwd) \
		&& cp "$WORK/current.xml" "$KEPT/before/appcast.xml" && cp "$3" "$KEPT/new/appcast.xml" \
		|| echo "The copies of both feeds could not be written to $KEPT." >&2
	cat >&2 <<-EOF
	The upload of the new feed to $1 failed, and so did the try to upload the feed that was there before.
	The release may hold no appcast.xml, an asset that a failed upload left half written, the new feed
	if its upload arrived in spite of the error, or the feed of a publish or a withdrawal at the same time.
	The folder of this run is deleted when it ends, so both feeds are kept here:
	  the feed before:  $KEPT/before/appcast.xml
	  the new feed:     $KEPT/new/appcast.xml
	To recover:
	1. List the feed of $1:
	   gh api repos/$REPO/releases/tags/$1 -q '.assets[] | select(.name == "appcast.xml") | "\(.id) \(.state)"'
	2. An asset in the state "uploaded" is a whole feed. Compare it with both copies, for example:
	   gh api -H 'Accept: application/octet-stream' repos/$REPO/releases/assets/<id> | cmp - $KEPT/new/appcast.xml
	   If it is the new feed, its upload arrived. If it is the feed before, the try to upload it again
	   arrived. Any other feed comes from a publish or a withdrawal at the same time: leave it in place.
	3. An asset in another state is the rest of a failed upload. Delete it, so that it frees the name:
	   gh api -X DELETE repos/$REPO/releases/assets/<id>
	4. When $1 holds no appcast.xml, upload one of the two copies, never with --clobber. The new feed
	   finishes this command, and the feed before returns to the state before it:
	   gh release upload $1 --repo $REPO $KEPT/new/appcast.xml
	5. Check that $FEED_URL answers.
	EOF
	return 2
}

# Fails unless the feed at the feed URL no longer lists $1, carries the signature of the public update
# key $3, and comes from the release $2, whose feed the withdrawal replaced. A stable version published
# at the same time makes another release the newest, and its feed may list $1 again, while the feed
# URL can still lead to the feed of $2 for a while. So the latest release must still be $2.
check_withdrawn() {
	curl -fsSL -o "$WORK/published.xml" "$FEED_URL" || fail "The feed at $FEED_URL cannot be read."
	LATEST=$(gh api "repos/$REPO/releases/latest" -q .tag_name) \
		|| fail "GitHub does not answer for the latest release, so withdraw cannot tell whether a publish at the same time listed $1 again. Check that $FEED_URL no longer lists $1."
	[ "$LATEST" = "$2" ] || fail "The latest release is ${LATEST:-none}, not $2: a publish at the same time made another release the newest, and its feed may list $1 again. Run withdraw again."
	check_feed "$WORK/published.xml" "$3" || fail "The feed at $FEED_URL failed its check."
	! grep -q "<sparkle:shortVersionString>$1</sparkle:shortVersionString>" "$WORK/published.xml" \
		|| fail "The feed at $FEED_URL still lists $1."
}

# The check of the signed result with the committed key stops a wrong key in the login Keychain: a
# feed that no installed app can check would stop every update. check_unchanged_feed and replace_feed
# stop the withdrawal when a pre-release was published at the same time, before it overwrites the
# feed of the pre-release. A stable version published at the same time makes another release the
# newest: check_unchanged_feed stops the withdrawal when that came first, check_withdrawn when it came
# before that check, and publish checks the old feed again after the change.
withdraw() {
	KEY=$(committed_key)
	check_production_key "$KEY"
	withdrawn_feed "$1" "$KEY"
	STABLE=$(gh api "repos/$REPO/releases/latest" -q .tag_name)
	check_unchanged_feed "$STABLE" || fail "The feed of $STABLE is not the feed that withdraw read: a publish ran at the same time, or GitHub did not answer. Nothing was uploaded. Run withdraw again."
	replace_feed "$STABLE" "$ASSET" "$WORK/withdrawn/appcast.xml" || case $? in
		2) fail "Withdraw stopped, and the feed of $STABLE is unknown. Follow the steps above, then run withdraw again if $FEED_URL still lists $1." ;;
		*) fail "$1 is still in the feed. Run withdraw again." ;;
	esac
	check_withdrawn "$1" "$STABLE" "$KEY"
	echo "Took $1 out of the feed at $FEED_URL. Mark its release page as withdrawn, and release the fixed version."
}

heading() { grep -m1 "^## $1 (" "$CHANGELOG" | sed 's/^## //'; }

draft() {
	check_zip_paths "$OUT/Moneten-$1-dSYMs.zip"
	notes section "$1" > "$WORK/notes.md"
	case "$1" in *-*) KIND="--prerelease --latest=false" ;; *) KIND="" ;; esac
	gh release create "v$1" --repo "$REPO" --draft --verify-tag --title "$(heading "$1")" --notes-file "$WORK/notes.md" $KIND \
		"$OUT/Moneten-$1.dmg" "$OUT/Moneten-$1-dSYMs.zip" "$OUT/appcast.xml" "$OUT"/sources/*
	echo "Created the draft of v$1. Check it, then run scripts/release.sh publish $1."
}

# Writes the files of the commit $1 that scripts/licenses.py reads into $WORK/tag.
tag_notices() {
	rm -rf "$WORK/tag" "$WORK/tag.tar"
	mkdir "$WORK/tag"
	git archive -o "$WORK/tag.tar" "$1" $(python3 scripts/licenses.py inputs) || fail "The license notices of $1 cannot be read."
	tar -xf "$WORK/tag.tar" -C "$WORK/tag"
}

# Fails unless the list $2, one "name sha256:digest" per asset, holds each source archive that the
# notices in the folder $1 name, with its pinned SHA-256. Notices that cannot be read, or that name no
# archive, fail as well, so that a broken check never passes a release without its source.
check_sources() {
	SOURCES=$(python3 scripts/licenses.py --root "$1" source-names) || fail "The license notices in $1 fail their check."
	[ -n "$SOURCES" ] || fail "The license notices in $1 name no source archive."
	printf '%s\n' "$SOURCES" > "$WORK/sources.txt"
	while read -r NAME SHA; do
		grep -qxF "$NAME sha256:$SHA" "$2" || fail "The release lacks the source archive $NAME with the SHA-256 $SHA."
	done < "$WORK/sources.txt"
}

publish() {
	# The release texts below come from CHANGELOG.md, so a stale checkout would undo fixes on main.
	git fetch -q origin main
	git diff --quiet origin/main -- "$CHANGELOG" || fail "$CHANGELOG differs from origin/main. Run publish on an up-to-date main."
	gh release view "v$1" --repo "$REPO" --json isDraft,assets -q '.isDraft, (.assets[].name)' > "$WORK/draft"
	[ "$(head -1 "$WORK/draft")" = true ] || fail "v$1 is not a draft."
	grep -qx "Moneten-$1.dmg" "$WORK/draft" && grep -qx appcast.xml "$WORK/draft" && grep -qx "Moneten-$1-dSYMs.zip" "$WORK/draft" \
		|| fail "The draft of v$1 lacks its disk image, its dSYMs, or appcast.xml."
	# The source archives that the tagged commit pins, never those of a main that moved on to a new JDK.
	git fetch -q origin "refs/tags/v$1:refs/tags/v$1"
	gh release view "v$1" --repo "$REPO" --json assets -q '.assets[] | "\(.name) \(.digest)"' > "$WORK/assets"
	tag_notices "v$1"
	check_sources "$WORK/tag" "$WORK/assets"
	gh release download "v$1" --repo "$REPO" -p appcast.xml -D "$WORK/draft-feed"
	# Every copy of the app refuses a feed that the committed update key did not sign, so no other feed may go out.
	KEY=$(committed_key)
	check_production_key "$KEY"
	check_feed "$WORK/draft-feed/appcast.xml" "$KEY" || fail "The feed of the draft of v$1 failed its check. Delete the draft and run the release again."
	checked_current_feed "$KEY"
	# A release or a withdrawal after this draft was made changed the current feed. An app that read
	# it refuses the draft's feed, and the draft's feed would bring a withdrawn version back.
	STABLE=""
	if [ "$FEED_ARGS" != --first-release ]; then
		notes check-newer --feed "$WORK/draft-feed/appcast.xml" --current "$WORK/current.xml" \
			|| fail "The feed of the draft is older than the current feed. Delete the draft and run the release again."
		STABLE=$(gh api "repos/$REPO/releases/latest" -q .tag_name)
		check_unchanged_feed "$STABLE" || fail "The feed of $STABLE is not the feed that publish read: a withdrawal or another publish ran at the same time, or GitHub did not answer. Nothing was published. Run publish again."
	fi
	case "$1" in
	*-*)
		[ -n "$STABLE" ] || fail "A pre-release needs a stable release that carries the feed."
		gh release edit "v$1" --repo "$REPO" --draft=false --prerelease --latest=false
		# Replacing the asset takes a few seconds, in which a check for updates fails and is tried again later.
		replace_feed "$STABLE" "$ASSET" "$WORK/draft-feed/appcast.xml" || case $? in
			2) fail "v$1 is public as a pre-release, and the feed of $STABLE is unknown. Follow the steps above, then decide by the feed that $STABLE holds. The new feed lists v$1, so keep v$1 public, and update the texts of earlier releases with gh release edit as publish does. With the feed from before, turn v$1 back into a draft with gh release edit v$1 --repo $REPO --draft, then run publish again." ;;
			*) fail "v$1 is public as a pre-release, but the upload of its feed to $STABLE failed. An upload that reports an error can still arrive, so check $FEED_URL first. If it lists $1, keep v$1 public, and update the texts of earlier releases with gh release edit as publish does. Otherwise turn v$1 back into a draft with gh release edit v$1 --repo $REPO --draft, then run publish again." ;;
		esac
		;;
	*)
		gh release edit "v$1" --repo "$REPO" --draft=false --latest
		# The feed of v$1 was made before a withdrawal that replaced the feed of $STABLE meanwhile, so it
		# lists the withdrawn version again.
		[ -z "$STABLE" ] || check_unchanged_feed "$STABLE" \
			|| fail "The feed of $STABLE changed while v$1 was published: a withdrawal at the same time may have taken out a version that the feed of v$1 lists again, or GitHub did not answer. Check $FEED_URL, and run withdraw again for a version that it still lists."
		;;
	esac
	# The text of every earlier release follows its section in CHANGELOG.md, as the feed does. One
	# listing reads every text, and only a release whose text differs is edited.
	gh api --paginate "repos/$REPO/releases?per_page=100" -q '.[] | select(.draft | not) | {tag: .tag_name, body: (.body // "")}' \
		> "$WORK/releases.jsonl"
	notes stale-releases < "$WORK/releases.jsonl" > "$WORK/stale"
	while read -r TAG; do
		notes section "${TAG#v}" > "$WORK/section.md"
		gh release edit "$TAG" --repo "$REPO" --notes-file "$WORK/section.md"
	done < "$WORK/stale"
	curl -fsSL -o "$WORK/published.xml" "$FEED_URL" || fail "The feed at $FEED_URL cannot be read."
	check_feed "$WORK/published.xml" "$KEY" || fail "The feed at $FEED_URL failed its check."
	grep -q "<sparkle:shortVersionString>$1</sparkle:shortVersionString>" "$WORK/published.xml" \
		|| fail "The feed at $FEED_URL does not list $1 yet."
	echo "Published v$1. The feed at $FEED_URL lists it, signed with the update key."
}

# The paths of a release and of a withdrawal of version $2 with the new feed $OUT/appcast.xml, which
# the private update key in the file $1 signed, in place of the current feed on GitHub.
# scripts/test-release-notes.py tests each refusal of check-feed and remove on its own. The dry run
# checks that Sparkle and check-feed agree on the signature, and that both paths stop at a feed
# that fails the check.
check_feeds() {
	SPARKLE=$(scripts/sparkle-tools.sh)
	KEY=$(public_key "$1")
	check_feed "$OUT/appcast.xml" "$KEY" || fail "check-feed refused the feed that Sparkle signed."
	sed 's/Moneten/Monetem/' "$OUT/appcast.xml" > "$WORK/changed.xml"
	if "$SPARKLE/sign_update" --verify --ed-key-file "$1" "$WORK/changed.xml" >/dev/null 2>&1; then
		fail "A changed feed passed the signature check of Sparkle."
	fi
	# A feed with a disk image over http that the update key signed, and the unsigned feed.
	sed 's#url="https://#url="http://#' "$OUT/appcast.xml" > "$WORK/http.xml"
	"$SPARKLE/sign_update" --ed-key-file "$1" "$WORK/http.xml" >/dev/null
	"$SPARKLE/sign_update" --verify --ed-key-file "$1" "$WORK/http.xml" || fail "Sparkle did not sign the feed with the http disk image."
	sed '/<!-- sparkle-signatures:/,$d' "$OUT/appcast.xml" > "$WORK/unsigned.xml"
	"$(notes openssl)" genpkey -algorithm ed25519 -outform DER -out "$WORK/other.der"
	tail -c 32 "$WORK/other.der" | base64 > "$WORK/other.key"
	CURRENT="$OUT/appcast.xml"
	current_feed() { cp "$CURRENT" "$WORK/current.xml"; FEED_ARGS="--feed $WORK/current.xml"; }
	checked_current_feed "$KEY"
	(checked_current_feed "$(public_key "$WORK/other.key")") 2>/dev/null && fail "A release accepted a current feed of another key."
	# remove keeps the last version, so the withdrawal takes 0.0.2 out of a feed with two versions.
	mkdir "$WORK/two"
	printf '# Changelog\n\n## Unreleased\n\n## 0.0.3 (2026-01-03)\n\n- Three.\n\n## 0.0.2 (2026-01-02)\n\n- Two.\n\n## 0.0.1 (2026-01-01)\n\n- One.\n' > "$WORK/two/CHANGELOG.md"
	for BUILD in 1 2 3; do
		[ "$BUILD" = 1 ] && FEED_ARGS=--first-release || FEED_ARGS="--feed $WORK/two/$((BUILD - 1)).xml"
		python3 scripts/release-notes.py --changelog "$WORK/two/CHANGELOG.md" appcast "0.0.$BUILD" --build "$BUILD" --min-macos 15.0 \
			--url "$(dmg_url "0.0.$BUILD")" --length 1 --signature "c2lnbmF0dXJl" $FEED_ARGS --out "$WORK/two/$BUILD.xml"
		"$SPARKLE/sign_update" --ed-key-file "$1" "$WORK/two/$BUILD.xml" >/dev/null
	done
	CURRENT="$WORK/two/2.xml"
	(CHANGELOG="$WORK/two/CHANGELOG.md"; withdrawn_feed 0.0.2 "$KEY" "$1")
	grep -q '<moneten:revision>3</moneten:revision>' "$WORK/withdrawn/appcast.xml" && ! grep -q '>0\.0\.2<' "$WORK/withdrawn/appcast.xml" \
		|| fail "The withdrawal did not take 0.0.2 out of the feed with a revision one above the current one."
	check_feed_race
	check_withdrawn_rule "$KEY"
	for CASE in "unsigned.xml:has no signature" "http.xml:has a disk image outside"; do
		CURRENT="$WORK/${CASE%%:*}"
		rm -rf "$WORK/withdrawn"
		(withdrawn_feed "$2" "$KEY" "$1") 2>"$WORK/error" && fail "A withdrawal accepted the current feed ${CASE%%:*}."
		grep -qF "${CASE#*:}" "$WORK/error" || fail "A withdrawal refused the current feed ${CASE%%:*} for another reason: $(cat "$WORK/error")"
		[ ! -e "$WORK/withdrawn/appcast.xml" ] || fail "A withdrawal wrote a feed from the current feed ${CASE%%:*}."
	done
	echo "A release refuses a current feed of another key, and a withdrawal raises the revision, and refuses an unsigned feed and a forged disk image."
}

# The withdrawal of 0.0.2 from the feed $WORK/two/2.xml of check_feeds, while a publish of 0.0.3
# replaces that feed at each step, as gh release upload --clobber does. A stub of gh keeps the asset
# appcast.xml of v0.0.2 in $WORK/release: its id in the file "id" and its bytes in "feed". The file
# "race" names the call of the withdrawal before which the publish uploads its feed: the read of the
# id, the read of the asset, the first write after both, or the upload. "broken" is an upload of the
# withdrawal that fails for another reason, and "both" fails the try to upload the old feed again too,
# so the release holds no feed and both feeds must be kept in $OUT. A publish uses the same functions.
check_feed_race() { (
	R="$WORK/release"
	OUT="$WORK/out"
	gh() {
		CALL=$*
		case "$CALL" in
		"api repos/$REPO/releases/tags/v0.0.2 -q "*) race id; cat "$R/id" 2>/dev/null ;;
		"api -H Accept: application/octet-stream repos/$REPO/releases/assets/"*) race read
			[ "$(cat "$R/id" 2>/dev/null)" = "${CALL##*/}" ] || { echo "gh: Not Found (HTTP 404)" >&2; return 1; }
			cat "$R/feed" ;;
		"api -X DELETE repos/$REPO/releases/assets/"*) race write
			[ "$(cat "$R/id" 2>/dev/null)" = "${CALL##*/}" ] || { echo "gh: Not Found (HTTP 404)" >&2; return 1; }
			rm "$R/id" "$R/feed" ;;
		"release upload v0.0.2 --repo $REPO "*) race write; race upload
			case "$(cat "$R/race")" in
			broken) echo broken-done > "$R/race"; echo "gh: Bad Gateway (HTTP 502)" >&2; return 1 ;;
			both) echo "gh: Bad Gateway (HTTP 502)" >&2; return 1 ;;
			esac
			case "$CALL" in *" --clobber "*) ;; *) [ ! -e "$R/id" ] || { echo "gh: asset under the same name already exists" >&2; return 1; } ;; esac
			upload "${CALL##* }" ;;
		*) echo "gh: the stub knows no call $CALL" >&2; return 1 ;;
		esac
	}
	upload() { echo $(($(cat "$R/count") + 1)) > "$R/count"; cp "$R/count" "$R/id"; cp "$1" "$R/feed"; }
	race() { [ "$(cat "$R/race")" != "$1" ] || { echo done > "$R/race"; upload "$WORK/two/3.xml"; }; }
	cp "$WORK/two/2.xml" "$WORK/current.xml"
	for CASE in none:withdrawn id:3 read:3 write:3 upload:3 broken:2 both:none; do
		rm -rf "$R" "$OUT"
		mkdir "$R"
		echo 0 > "$R/count"
		upload "$WORK/two/2.xml"
		echo "${CASE%%:*}" > "$R/race"
		case "${CASE#*:}" in
		withdrawn) WANT="$WORK/withdrawn/appcast.xml" ;;
		none) WANT="" ;;
		*) WANT="$WORK/two/${CASE#*:}.xml" ;;
		esac
		STATUS=0
		(check_unchanged_feed v0.0.2 && replace_feed v0.0.2 "$ASSET" "$WORK/withdrawn/appcast.xml") 2>"$WORK/error" || STATUS=$?
		[ "$STATUS" = 0 ] && [ "${CASE%%:*}" != none ] && fail "A withdrawal succeeded although a publish replaced the feed at the step ${CASE%%:*}."
		[ "$STATUS" = 0 ] || [ "${CASE%%:*}" != none ] || fail "A withdrawal without a publish at the same time failed: $(cat "$WORK/error")"
		if [ -n "$WANT" ]; then
			cmp -s "$R/feed" "$WANT" || fail "In the case ${CASE%%:*}, the release holds another feed than ${WANT#"$WORK"/}."
		else
			[ ! -e "$R/feed" ] || fail "In the case ${CASE%%:*}, the release still holds a feed."
		fi
	done
	# The last case left the release without a feed, so the run must keep both feeds and name them.
	[ "$STATUS" = 2 ] || fail "A withdrawal whose two uploads failed returned $STATUS, not 2."
	cmp -s "$OUT/feeds-v0.0.2/before/appcast.xml" "$WORK/two/2.xml" && cmp -s "$OUT/feeds-v0.0.2/new/appcast.xml" "$WORK/withdrawn/appcast.xml" \
		|| fail "A withdrawal whose two uploads failed did not keep both feeds in $OUT/feeds-v0.0.2."
	KEPT=$(cd "$OUT/feeds-v0.0.2" && pwd)
	grep -qF "$KEPT/before/appcast.xml" "$WORK/error" && grep -qF "$KEPT/new/appcast.xml" "$WORK/error" \
		|| fail "A withdrawal whose two uploads failed did not name the kept feeds: $(cat "$WORK/error")"
	echo "Of a withdrawal and a publish at the same time, only one replaces the feed that both read, and the other one stops. When both uploads fail, both feeds stay in the output folder."
); }

# check_withdrawn with stubs of curl and gh: it passes only when the latest release is still v0.0.2,
# whose feed the withdrawal of 0.0.2 replaced, and the feed URL leads to a feed without 0.0.2 that the
# public update key $1 signed. STUB_LATEST is the tag of the latest release, or "!" for no answer.
check_withdrawn_rule() { (
	curl() { [ "$2" = -o ] && [ "$4" = "$FEED_URL" ] || return 7; cp "$STUB_FEED" "$3"; }
	gh() {
		[ "$*" = "api repos/$REPO/releases/latest -q .tag_name" ] || { echo "gh: the stub knows no call $*" >&2; return 1; }
		[ "$STUB_LATEST" != "!" ] || { echo "gh: Bad Gateway (HTTP 502)" >&2; return 1; }
		echo "$STUB_LATEST"
	}
	while IFS='|' read -r STUB_LATEST STUB_FEED WANT; do
		CASE="latest $STUB_LATEST, feed ${STUB_FEED#"$WORK"/}"
		if (check_withdrawn 0.0.2 v0.0.2 "$1") 2>"$WORK/error"; then
			[ -z "$WANT" ] || fail "The check after a withdrawal passed in the case $CASE."
		else
			[ -n "$WANT" ] || fail "The check after a withdrawal failed in the case $CASE: $(cat "$WORK/error")"
			grep -qF "$WANT" "$WORK/error" || fail "The check after a withdrawal failed in the case $CASE with another message: $(cat "$WORK/error")"
		fi
	done <<-EOF
	v0.0.2|$WORK/withdrawn/appcast.xml|
	v0.0.3|$WORK/withdrawn/appcast.xml|The latest release is v0.0.3, not v0.0.2
	!|$WORK/withdrawn/appcast.xml|GitHub does not answer for the latest release
	v0.0.2|$WORK/two/2.xml|still lists 0.0.2
	EOF
	echo "The check after a withdrawal fails when another release became the newest, or the feed still lists the version."
); }

# The update keys of App/project.yml: a Debug build trusts the test key of Fixtures/update, and the
# check of a release refuses that key and the placeholder.
check_keys() {
	TEST_KEY=$(public_key "$TEST_KEY_FILE")
	[ "$(debug_key)" = "$TEST_KEY" ] || fail "The Debug key of App/project.yml is not the public half of $TEST_KEY_FILE."
	(check_production_key "$TEST_KEY") 2>/dev/null && fail "The check of a release accepts the test key."
	(check_production_key none) 2>/dev/null && fail "The check of a release accepts the placeholder."
	[ "$(committed_key)" = none ] || check_production_key "$(committed_key)"
	echo "The test key is the Debug key, and the check of a release refuses it and the placeholder."
}

# The check of draft: it accepts paths in /Users/runner/ and refuses another home folder. On the
# zip of this run, it must pass in a checkout of the GitHub runner and refuse a checkout in another
# home folder, such as the one of a maintainer.
check_path_rule() {
	printf 'x /Users/runner/work/Moneten/Moneten/App/Sources/AppModel.swift y' > "$WORK/runner-path"
	echo "$WORK/runner-path" > "$WORK/path-list"
	check_build_paths "$WORK/path-list" || fail "The check of build paths refused a path of the GitHub runner."
	printf 'x /Users/someone/Moneten/App/Sources/AppModel.swift y' >> "$WORK/runner-path"
	(check_build_paths "$WORK/path-list") 2>/dev/null && fail "The check of build paths accepted a path in another home folder."
	case "$PWD" in
	/Users/runner/*) check_zip_paths "$OUT/Moneten-$1-dSYMs.zip"
		echo "The dSYMs of this build hold no path in a home folder other than /Users/runner/." ;;
	/Users/*) (check_zip_paths "$OUT/Moneten-$1-dSYMs.zip") 2>/dev/null && fail "The check of draft accepted dSYMs built in another home folder."
		echo "The check of draft refuses the dSYMs of this build, which hold the path of a home folder other than /Users/runner/." ;;
	esac
}

# The check of publish must read the notices of a commit, accept the source archives that this run
# downloaded with the notices of the checkout, and refuse a missing archive, another digest, and
# notices that cannot be read.
check_source_rule() {
	tag_notices HEAD
	python3 scripts/licenses.py --root "$WORK/tag" check >/dev/null || fail "The license notices of HEAD fail their check."
	rm -rf "$WORK/tag"
	mkdir "$WORK/tag"
	tar -cf - $(python3 scripts/licenses.py inputs) | tar -xf - -C "$WORK/tag"
	for f in "$OUT"/sources/*; do echo "${f##*/} sha256:$(shasum -a 256 "$f" | cut -d' ' -f1)"; done > "$WORK/assets-good"
	(check_sources "$WORK/tag" "$WORK/assets-good") || fail "The check of publish refuses the source archives of this commit."
	tail -n +2 "$WORK/assets-good" > "$WORK/assets-short"
	(check_sources "$WORK/tag" "$WORK/assets-short") 2>/dev/null && fail "The check of publish accepts a release without a source archive."
	sed '1s/sha256:./sha256:x/' "$WORK/assets-good" > "$WORK/assets-wrong"
	(check_sources "$WORK/tag" "$WORK/assets-wrong") 2>/dev/null && fail "The check of publish accepts a source archive with another digest."
	rm "$WORK/tag/Licenses/notices.json"
	(check_sources "$WORK/tag" "$WORK/assets-good") 2>/dev/null && fail "The check of publish accepts notices that cannot be read."
	echo "publish refuses a release without its source archives or with other ones."
}

dry_run() {
	VERSION=${1:-0.0.0-beta.1}
	cp CHANGELOG.md "$WORK/CHANGELOG.md"
	CHANGELOG="$WORK/CHANGELOG.md"
	notes check
	if ! notes section "$VERSION" >/dev/null 2>&1; then
		# An empty "Unreleased" section cannot be cut, so the copy gets one entry.
		python3 - "$CHANGELOG" <<-'EOF'
		import sys
		path = sys.argv[1]
		text = open(path, encoding="utf-8").read()
		head, rest = text.split("## Unreleased\n", 1)
		entry = "" if rest.lstrip("\n").startswith("- ") else "\n- Dry run of the release pipeline.\n"
		open(path, "w", encoding="utf-8").write(head + "## Unreleased\n" + entry + rest)
		EOF
		notes cut "$VERSION"
	fi
	notes check-release "$VERSION" --build "$(git rev-list --count HEAD)" --first-release
	if [ "$MONETEN_SIGN" = 1 ]; then package "$VERSION" signed dry-run; else package "$VERSION" unsigned; fi
	check_path_rule "$VERSION"
	check_frame_tools
	check_keys
	check_source_rule
	# The test key, so a Debug build can read this feed (Fixtures/update/README.md).
	MONETEN_UPDATE_KEY_FILE="$TEST_KEY_FILE" feed "$VERSION" first
	check_feeds "$TEST_KEY_FILE" "$VERSION"
	echo "Dry run of $VERSION passed: $(ls "$OUT" | tr '\n' ' ')"
}

case "$1" in
	dry-run) dry_run "$2" ;;
	preflight|package|feed|draft|publish|withdraw)
		[ -n "$2" ] || fail "usage: scripts/release.sh $1 <version>"
		"$1" "$2" ;;
	*) fail "usage: scripts/release.sh dry-run [version] | preflight | package | feed | draft | publish | withdraw <version>" ;;
esac
