#!/bin/sh
# Runs every repository check: documentation links and paths, the window chrome rule, OpenSpec,
# unused code, the tests, and the replays of the example extension and of three published extensions.
set -e
cd "$(dirname "$0")/.."
python3 scripts/check-docs.py
python3 scripts/check-ui.py
openspec validate --all --strict --no-interactive
scripts/generate-project.sh
periphery scan
scripts/test.sh
swift run --disable-keychain ext test Extensions/Example Fixtures/example/fixture.json Fixtures/example/expected.json
for extension in "permanent-tsb-business/Permanent TSB Business.lua" monzo/Monzo.lua amazon-bestellungen/amazon-bestellungen.lua; do
	folder="Fixtures/extensions/${extension%%/*}"
	swift run --disable-keychain ext test "Fixtures/extensions/$extension" "$folder/fixture.json" "$folder/expected.json"
done
