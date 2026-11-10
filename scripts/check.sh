#!/bin/sh
# Runs every repository check: documentation links and paths, OpenSpec, unused code, and the tests.
set -e
cd "$(dirname "$0")/.."
python3 scripts/check-docs.py
openspec validate --all --strict --no-interactive
scripts/generate-project.sh
periphery scan
scripts/test.sh
