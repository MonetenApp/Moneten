#!/bin/sh
# Runs every repository check: documentation links and paths, OpenSpec, unused code, and the tests.
# Periphery needs an index store. The default build system of Swift 6.2 and later writes none,
# so the unused-code check builds once with the native build system into its own folder.
set -e
cd "$(dirname "$0")/.."
python3 scripts/check-docs.py
openspec validate --all --strict --no-interactive
if ! swift build --disable-keychain --build-tests --build-system native --scratch-path .build/periphery > .build/periphery.log 2>&1; then
	cat .build/periphery.log
	exit 1
fi
periphery scan --skip-build --index-store-path .build/periphery/debug/index/store
scripts/test.sh
