#!/bin/sh
# Builds, signs, notarizes, and drafts a release of Moneten. .github/workflows/release.yml runs it,
# and docs/releasing.md explains the secrets and the steps.
#   scripts/release.sh dry-run [version]  every step without secrets and without GitHub: an app signed
#                                         to run locally, an unsigned disk image, and a feed signed
#                                         with the test update key of Fixtures/update, which a Debug
#                                         build reads. Version 0.0.0-beta.1 by default.
#                                         With MONETEN_SIGN=1 it also signs and notarizes.
#   scripts/release.sh preflight <version>  step 1: the changelog section, the tag on main, and the feed
#   scripts/release.sh package <version>    steps 2 to 4: the signed and notarized app on a notarized
#                                           disk image in dist/release
#   scripts/release.sh feed <version>       step 5: the update signature of the disk image and the new
#                                           signed feed dist/release/appcast.xml
#   scripts/release.sh draft <version>      step 6: the GitHub release as a draft with both files
#   scripts/release.sh publish <version>    step 7, run by the owner: publishes the draft, moves the feed
#                                           of a pre-release to the newest stable release, and updates
#                                           the text of earlier releases from CHANGELOG.md
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

# The public key of the private EdDSA key in the file $1: Sparkle keeps the 32 byte seed, which
# becomes an Ed25519 key in PKCS#8 for openssl. The key never appears in an argument or a log.
public_key() {
	{ printf '\060\056\002\001\000\060\005\006\003\053\145\160\004\042\004\040'; base64 -d < "$1" | head -c 32; } \
		| openssl pkey -inform DER -pubout -outform DER | tail -c 32 | base64
}

# The public update key that App/project.yml gives a Release build.
committed_key() { sed -n 's/^ *MONETEN_UPDATE_PUBLIC_KEY: *//p' App/project.yml | head -1; }

# A release must carry the production update key: not the placeholder, and not the public test key.
check_production_key() {
	case "$1" in
		none|"") fail "App/project.yml has no production update key yet. docs/releasing.md explains how the owner adds it." ;;
		"$(public_key "$TEST_KEY_FILE")") fail "The update key is the test key of Fixtures/update, which only Debug builds may trust." ;;
	esac
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
	current_feed
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

# Mounts the disk image $1 read-only and checks the app on it as a user would get it.
check_dmg() {
	hdiutil verify -quiet "$1"
	hdiutil attach -quiet -nobrowse -readonly -mountpoint "$WORK/volume" "$1"
	MOUNTED="$WORK/volume/Moneten.app"
	unmount_and_fail() { hdiutil detach -quiet "$WORK/volume"; fail "$@"; }
	[ -L "$WORK/volume/Applications" ] || unmount_and_fail "The disk image has no link to the Applications folder."
	codesign --verify --strict --deep "$MOUNTED" || unmount_and_fail "The app on the disk image fails its code signature check."
	[ "$(plist "$MOUNTED" CFBundleShortVersionString)" = "${2%%-*}" ] || unmount_and_fail "The app on the disk image has another version."
	env -i "$MOUNTED/Contents/Resources/FinTSHelper/runtime/bin/java" -Xshare:off -version 2>/dev/null \
		|| unmount_and_fail "The FinTS helper on the disk image does not start."
	if [ "$3" = signed ]; then
		spctl --assess --type execute -vv "$MOUNTED" 2>&1 | grep -q 'source=Notarized Developer ID' \
			|| unmount_and_fail "Gatekeeper does not accept the app on the disk image as notarized."
		xcrun stapler validate -q "$MOUNTED" || unmount_and_fail "The app on the disk image has no stapled ticket."
	fi
	hdiutil detach -quiet "$WORK/volume"
}

# Steps 2 to 4. $2 is "unsigned" for a dry run without the Developer ID.
package() {
	MODE=${2:-signed}
	rm -rf "$OUT"
	mkdir -p "$OUT"
	if [ "$MODE" = signed ]; then
		MONETEN_VERSION="$1" scripts/build-app.sh developer-id
		APP=dist/Moneten.app
		codesign -dvv "$APP" 2>&1 | grep -q '^Authority=Developer ID Application' || fail "The app is not signed with the Developer ID."
		codesign -dv "$APP" 2>&1 | grep -q 'flags=.*runtime' || fail "The app has no hardened runtime."
		plist "$APP" MonetenFinTSProductID >/dev/null 2>&1 || fail "The app has no FinTS product ID. See docs/releasing.md."
		check_production_key "$(plist "$APP" SUPublicEDKey)"
		[ "$(plist "$APP" SUPublicEDKey)" = "$(committed_key)" ] || fail "The app carries another update key than App/project.yml."
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
	# A feed that the installed apps cannot check would stop every update. A dry run builds without
	# the production key and signs with the test key.
	[ "$2" = first ] || [ "$(public_key "$MONETEN_UPDATE_KEY_FILE")" = "$UPDATE_KEY" ] \
		|| fail "MONETEN_UPDATE_KEY_FILE is not the private half of the update key in the app."
	SPARKLE=$(scripts/sparkle-tools.sh)
	DMG="$OUT/Moneten-$1.dmg"
	SIGNATURE=$("$SPARKLE/sign_update" --ed-key-file "$MONETEN_UPDATE_KEY_FILE" -p "$DMG")
	"$SPARKLE/sign_update" --verify --ed-key-file "$MONETEN_UPDATE_KEY_FILE" "$DMG" "$SIGNATURE"
	if [ "$2" = first ]; then FEED_ARGS=--first-release; else current_feed; fi
	notes appcast "$1" --build "$BUILD" --min-macos "$MIN_MACOS" --url "$(dmg_url "$1")" \
		--length "$(stat -f%z "$DMG")" --signature "$SIGNATURE" $FEED_ARGS --out "$OUT/appcast.xml"
	"$SPARKLE/sign_update" --ed-key-file "$MONETEN_UPDATE_KEY_FILE" "$OUT/appcast.xml" >/dev/null
	"$SPARKLE/sign_update" --verify --ed-key-file "$MONETEN_UPDATE_KEY_FILE" "$OUT/appcast.xml"
	echo "Wrote the signed feed $OUT/appcast.xml."
}

heading() { grep -m1 "^## $1 (" "$CHANGELOG" | sed 's/^## //'; }

draft() {
	notes section "$1" > "$WORK/notes.md"
	case "$1" in *-*) KIND="--prerelease --latest=false" ;; *) KIND="" ;; esac
	gh release create "v$1" --repo "$REPO" --draft --verify-tag --title "$(heading "$1")" --notes-file "$WORK/notes.md" $KIND \
		"$OUT/Moneten-$1.dmg" "$OUT/appcast.xml"
	echo "Created the draft of v$1. Check it, then run scripts/release.sh publish $1."
}

publish() {
	# The release texts below come from CHANGELOG.md, so a stale checkout would undo fixes on main.
	git fetch -q origin main
	git diff --quiet origin/main -- "$CHANGELOG" || fail "$CHANGELOG differs from origin/main. Run publish on an up-to-date main."
	gh release view "v$1" --repo "$REPO" --json isDraft,assets -q '.isDraft, (.assets[].name)' > "$WORK/draft"
	[ "$(head -1 "$WORK/draft")" = true ] || fail "v$1 is not a draft."
	grep -qx "Moneten-$1.dmg" "$WORK/draft" && grep -qx appcast.xml "$WORK/draft" || fail "The draft of v$1 lacks its disk image or appcast.xml."
	gh release download "v$1" --repo "$REPO" -p appcast.xml -D "$WORK/draft-feed"
	current_feed
	# A release that was published after this draft was made must be in the draft's feed too.
	if [ "$FEED_ARGS" != --first-release ]; then
		python3 - "$WORK/current.xml" "$WORK/draft-feed/appcast.xml" <<-'EOF' || fail "The feed of the draft misses a published version. Delete the draft and run the release again."
		import sys, xml.etree.ElementTree as ET
		key = "{http://www.andymatuschak.org/xml-namespaces/sparkle}shortVersionString"
		versions = lambda path: {i.findtext(key) for i in ET.parse(path).getroot().iter("item")}
		sys.exit(0 if versions(sys.argv[1]) <= versions(sys.argv[2]) else 1)
		EOF
	fi
	case "$1" in
	*-*)
		[ "$FEED_ARGS" != --first-release ] || fail "A pre-release needs a stable release that carries the feed."
		STABLE=$(gh api "repos/$REPO/releases/latest" -q .tag_name)
		gh release edit "v$1" --repo "$REPO" --draft=false --prerelease --latest=false
		# Replacing the asset takes a few seconds, in which a check for updates fails and is tried again later.
		gh release upload "$STABLE" --repo "$REPO" --clobber "$WORK/draft-feed/appcast.xml"
		;;
	*)
		gh release edit "v$1" --repo "$REPO" --draft=false --latest
		;;
	esac
	# The text of every earlier release follows its section in CHANGELOG.md, as the feed does.
	gh release list --repo "$REPO" --limit 200 --json tagName,isDraft -q '.[] | select(.isDraft | not) | .tagName' | while read -r TAG; do
		notes section "${TAG#v}" > "$WORK/section.md" 2>/dev/null || continue
		gh release view "$TAG" --repo "$REPO" --json body -q .body > "$WORK/body.md"
		cmp -s "$WORK/section.md" "$WORK/body.md" || gh release edit "$TAG" --repo "$REPO" --notes-file "$WORK/section.md"
	done
	curl -fsSL "$FEED_URL" | grep -q "<sparkle:shortVersionString>$1</sparkle:shortVersionString>" \
		|| fail "The feed at $FEED_URL does not list $1 yet."
	echo "Published v$1. The feed at $FEED_URL lists it."
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
	if [ "$MONETEN_SIGN" = 1 ]; then package "$VERSION" signed; else package "$VERSION" unsigned; fi
	# The test key, so a Debug build can read this feed (Fixtures/update/README.md).
	MONETEN_UPDATE_KEY_FILE="$TEST_KEY_FILE" feed "$VERSION" first
	# One changed byte must break the signature of the feed.
	sed 's/Moneten/Monetem/' "$OUT/appcast.xml" > "$WORK/changed.xml"
	if "$(scripts/sparkle-tools.sh)/sign_update" --verify --ed-key-file "$TEST_KEY_FILE" "$WORK/changed.xml" >/dev/null 2>&1; then
		fail "The changed feed passed the signature check."
	fi
	echo "Dry run of $VERSION passed: $(ls "$OUT" | tr '\n' ' ')"
}

case "$1" in
	dry-run) dry_run "$2" ;;
	preflight|package|feed|draft|publish)
		[ -n "$2" ] || fail "usage: scripts/release.sh $1 <version>"
		"$1" "$2" ;;
	*) fail "usage: scripts/release.sh dry-run [version] | preflight | package | feed | draft | publish <version>" ;;
esac
