#!/bin/sh
# Runs every repository check: documentation links and paths, the window chrome rule, OpenSpec,
# unused code, the tests, and the replay of the example extension.
set -e
cd "$(dirname "$0")/.."
python3 scripts/check-docs.py
python3 scripts/check-ui.py
openspec validate --all --strict --no-interactive
scripts/generate-project.sh
periphery scan
scripts/test.sh
swift run --disable-keychain ext test Extensions/Example Fixtures/example/fixture.json Fixtures/example/expected.json
