# 0017. Give every Release build the hardened runtime

Status: Accepted

This decision replaces the sentence "Without a team, Xcode signs to run locally and leaves out the hardened runtime" of [ADR 0011](0011-app-target-in-an-xcode-project.md).

## Context

`scripts/build-app.sh` without an argument builds the Release configuration. Without a team in `App/Local.xcconfig`, Xcode signs it to run locally. Such a build had no hardened runtime, and Xcode added the entitlement `get-task-allow`, which lets another process of the same user attach to the app. The app holds the database key, the database password while it is unlocked, and the PINs that the user typed, so a Release build must not allow that.

The hardened runtime turns on library validation, which loads only libraries signed by Apple or by the team of the app. An ad hoc signature has no team, so library validation refuses `SQLCipher.framework`, `Sparkle.framework`, and the libraries of the Java runtime of the FinTS helper, which all carry ad hoc signatures in such a build.

## Decision

- Every build of the Release configuration has the hardened runtime and no `get-task-allow`: the app, the extension host, and the java of the FinTS helper. `App/Signing.xcconfig` sets this for the configuration Release, and `scripts/build-app.sh` refuses a Release build that lacks it.
- A Release build without a team turns off library validation, with `App/MonetenLocal.entitlements` for the app and `App/FinTSHelperLocal.entitlements` for the java of the helper. The hardened runtime still refuses the variables of the dynamic linker that load other libraries, and it still refuses debuggers.
- A build with a team, and every Developer ID build of a release, keeps library validation and uses `App/Moneten.entitlements` and `App/FinTSHelper.entitlements`.
- The Debug configuration keeps `get-task-allow` and has no hardened runtime, so that the debugger can attach. The configuration Perf of `scripts/perf-check.sh` is a Debug build in this respect.

## Consequences

- A Release build signed to run locally behaves like a release in what it allows other processes, apart from library validation.
- A contributor who signs with a team no longer sets `MONETEN_HARDENED_RUNTIME` in `App/Local.xcconfig`. The team alone is enough.
- A new framework or a new helper in the app needs a signature that the hardened runtime accepts, or the check of `scripts/build-app.sh` fails.

## Alternatives

- **Turn off library validation in every build.** Simpler, but a Developer ID release would then load a library with any signature. Rejected.
- **Sign local builds with a self-signed certificate.** It keeps library validation, but every contributor would have to create and trust a certificate. Rejected.
