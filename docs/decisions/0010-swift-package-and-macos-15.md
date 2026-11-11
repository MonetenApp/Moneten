# 0010. Build the app as a Swift package and require macOS 15

Status: Accepted

## Context

The first build of the app had to run on a Mac with only the Command Line Tools. They contain the Swift 6.3 compiler, the macOS 26.5 SDK with SwiftUI and Swift Charts, and Swift Testing. They contain no Xcode, no `xcodebuild`, and no asset catalog compiler.

Xcode opens a `Package.swift` directly. A package therefore works with and without Xcode.

Several SwiftUI features that the specs need arrive with macOS 15. Examples are table columns that appear only in some views, focus for the search field, and a main window that opens at launch. No document of the project named a minimum version.

## Decision

- The repository is one Swift package. `Domain`, `Storage`, and `Import` are library targets. `App` is the executable `Moneten`.
- `scripts/build-app.sh` builds `dist/Moneten.app`. It writes `Info.plist`, embeds `SQLCipher.framework`, and signs the bundle. Without `CODESIGN_IDENTITY` it signs ad hoc and leaves out the hardened runtime, because its library validation refuses a framework with an ad hoc signature.
- `scripts/test.sh` runs the tests. With only the Command Line Tools it adds the search paths of Swift Testing.
- Both scripts call the package manager with `--disable-keychain`. Without it, the package manager waits for a Keychain prompt about GitHub before it downloads SQLCipher.
- The app requires macOS 15 or newer.

## Consequences

- Contributors need a Mac, but not Xcode. This replaces the consequence "Contributors need a Mac and Xcode" of [ADR 0001](0001-native-mac-app-in-swift.md).
- There is no Xcode project file to keep in sync. An Xcode project can still come later for notarization, an asset catalog, or string catalogs.
- [HBCI4Swift](https://github.com/macemmi/HBCI4Swift) is an Xcode framework. It must become a Swift package before the app can use it, which issue #12 already plans.
- Each ad hoc build has a new signature. The Keychain does not give the entries of an earlier build to a new one. A database without a password keeps its key in the Keychain, so a developer who rebuilds should set a database password, or sign with one stable identity.
- Users of macOS 14 cannot run the app.
