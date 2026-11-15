#!/bin/sh
# Runs every repository check: documentation links and paths, the window chrome rule, OpenSpec,
# unused code, the tests, and the replays of the example extension and of three published extensions.
set -e
cd "$(dirname "$0")/.."
python3 scripts/check-docs.py
python3 scripts/check-ui.py
openspec validate --all --strict --no-interactive
scripts/generate-project.sh
# Periphery's own build folder is named after the project, not the checkout, so all worktrees would
# share one index store and report each other's unused code. The schemes are those of .periphery.yml.
for scheme in Moneten ext; do
	log=$(xcodebuild -project App/Moneten.xcodeproj -scheme "$scheme" -derivedDataPath .build/periphery -parallelizeTargets -quiet build-for-testing \
		CODE_SIGNING_ALLOWED=NO DEBUG_INFORMATION_FORMAT=dwarf COMPILER_INDEX_STORE_ENABLE=YES INDEX_ENABLE_DATA_STORE=YES 2>&1) || { printf '%s\n' "$log"; exit 1; }
done
periphery scan --skip-build --index-store-path .build/periphery/Index.noindex/DataStore
scripts/test.sh
scripts/check-export-sync.sh
swift run --disable-keychain ext test Extensions/Example Fixtures/example/fixture.json Fixtures/example/expected.json
for extension in "permanent-tsb-business/Permanent TSB Business.lua" monzo/Monzo.lua amazon-bestellungen/amazon-bestellungen.lua; do
	folder="Fixtures/extensions/${extension%%/*}"
	swift run --disable-keychain ext test "Fixtures/extensions/$extension" "$folder/fixture.json" "$folder/expected.json"
done
