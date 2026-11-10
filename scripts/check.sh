#!/bin/sh
# Runs every repository check: documentation links and paths, OpenSpec, unused code, and the tests.
# Periphery needs an index store. The default build system of Swift 6.2 and later writes none,
# so the unused-code check builds once with the native build system into its own folder.
set -e
cd "$(dirname "$0")/.."
python3 scripts/check-docs.py
openspec validate --all --strict --no-interactive
swift build --disable-keychain --build-tests --build-system native --scratch-path .build/periphery 2>&1 | grep -E "error:|Build complete" || true
periphery scan --skip-build --index-store-path .build/periphery/debug/index/store
scripts/test.sh
