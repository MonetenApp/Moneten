#!/bin/sh
# Writes App/Moneten.xcodeproj from App/project.yml. Needs XcodeGen: brew install xcodegen
# The project gets the Package.resolved of the repository, so Xcode builds the same versions of
# GRDB and SQLCipher as the package manager. HBCI4Swift is built first, see scripts/build-hbci4swift.sh.
set -e
cd "$(dirname "$0")/.."
scripts/build-hbci4swift.sh
(cd App && xcodegen generate --quiet)
SPM=App/Moneten.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
mkdir -p "$SPM"
cp Package.resolved "$SPM/Package.resolved"
