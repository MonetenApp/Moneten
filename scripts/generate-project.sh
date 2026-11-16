#!/bin/sh
# Writes App/Moneten.xcodeproj from App/project.yml. Needs XcodeGen: brew install xcodegen
# The project gets the Package.resolved of the repository, so Xcode builds the same versions of
# GRDB and SQLCipher as the package manager, and the pin of Sparkle, which only the app uses.
set -e
cd "$(dirname "$0")/.."
(cd App && xcodegen generate --quiet)
SPM=App/Moneten.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
mkdir -p "$SPM"
# App/project.yml names the version of Sparkle. The revision below must be the commit of that version.
SPARKLE_VERSION=2.10.1
SPARKLE_REVISION=ab7d71291238df6e0492143b120c9b696a35f603
[ "$(sed -n '/^  Sparkle:$/,/^  [^ ]/s/^ *exactVersion: *//p' App/project.yml)" = "$SPARKLE_VERSION" ] || {
	echo "App/project.yml names another version of Sparkle than scripts/generate-project.sh ($SPARKLE_VERSION). Change both, and scripts/sparkle-tools.sh." >&2; exit 1; }
python3 - Package.resolved "$SPM/Package.resolved" "$SPARKLE_REVISION" "$SPARKLE_VERSION" <<'EOF'
import json, sys
resolved = json.load(open(sys.argv[1]))
resolved["pins"].append({"identity": "sparkle", "kind": "remoteSourceControl", "location": "https://github.com/sparkle-project/Sparkle",
	"state": {"revision": sys.argv[3], "version": sys.argv[4]}})
json.dump(resolved, open(sys.argv[2], "w"), indent=2)
EOF
