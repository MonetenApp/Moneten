#!/bin/sh
# Runs every repository check: documentation links and paths, the window chrome rule, OpenSpec,
# unused code, the tests, and the replays of the example extension and of three published extensions.
set -e
cd "$(dirname "$0")/.."
python3 scripts/check-docs.py
python3 scripts/check-ui.py
openspec validate --all --strict --no-interactive
scripts/generate-project.sh
# Periphery builds every checkout of the project into the same folder under ~/Library/Caches, so a check
# in another worktree would add its files to the index. Each checkout builds into its own folder instead.
index=.build/periphery
for scheme in Moneten ext; do
	xcodebuild -project App/Moneten.xcodeproj -scheme "$scheme" -parallelizeTargets -derivedDataPath "$index" -quiet build-for-testing \
		CODE_SIGNING_ALLOWED=NO ENABLE_BITCODE=NO DEBUG_INFORMATION_FORMAT=dwarf COMPILER_INDEX_STORE_ENABLE=YES INDEX_ENABLE_DATA_STORE=YES
done
periphery scan --skip-build --index-store-path "$index/Index.noindex/DataStore"
scripts/test.sh
swift run --disable-keychain ext test Extensions/Example Fixtures/example/fixture.json Fixtures/example/expected.json
for extension in "permanent-tsb-business/Permanent TSB Business.lua" monzo/Monzo.lua amazon-bestellungen/amazon-bestellungen.lua; do
	folder="Fixtures/extensions/${extension%%/*}"
	swift run --disable-keychain ext test "Fixtures/extensions/$extension" "$folder/fixture.json" "$folder/expected.json"
done
