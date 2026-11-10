#!/bin/sh
# Writes App/MonetenMoneten.xcodeproj from App/project.yml. Needs XcodeGen: brew install xcodegen
# The project gets the Package.resolved of the repository, so Xcode builds the same versions of
# GRDB and SQLCipher as the package manager.
set -e
cd "$(dirname "$0")/.."
(cd App && xcodegen generate --quiet)
SPM=App/MonetenMoneten.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
mkdir -p "$SPM"
cp Package.resolved "$SPM/Package.resolved"
