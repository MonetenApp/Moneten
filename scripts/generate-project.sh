#!/bin/sh
# Writes App/Moneten.xcodeproj from App/project.yml. Needs XcodeGen: brew install xcodegen
# The project gets the Package.resolved of the repository, so Xcode builds the same versions of
# GRDB and SQLCipher as the package manager, and the pin of Sparkle, which only the app uses.
set -e
cd "$(dirname "$0")/.."
(cd App && xcodegen generate --quiet)
SPM=App/Moneten.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
mkdir -p "$SPM"
# scripts/sparkle-tools.sh holds the pin of Sparkle and fails when App/project.yml names another version.
PIN=$(scripts/sparkle-tools.sh pin)
python3 - Package.resolved "$SPM/Package.resolved" "${PIN#* }" "${PIN% *}" <<'EOF'
import json, sys
resolved = json.load(open(sys.argv[1]))
resolved["pins"].append({"identity": "sparkle", "kind": "remoteSourceControl", "location": "https://github.com/sparkle-project/Sparkle",
	"state": {"revision": sys.argv[3], "version": sys.argv[4]}})
json.dump(resolved, open(sys.argv[2], "w"), indent=2)
EOF
