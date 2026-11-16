# 0016. Sign releases with a Developer ID certificate that CI holds

Status: Partly superseded by 0019

[ADR 0019](0019-ext-releases-in-the-build-environment.md) also allows the tags `ext-v*` in the environment `build`, for the signed releases of `ext`.

This decision replaces the signing points of [ADR 0011](0011-app-target-in-an-xcode-project.md): "Xcode manages that certificate in the team account, so no private key leaves Apple", the Xcode account that `scripts/build-app.sh developer-id` needed, and "CI will need an App Store Connect API key for the same".

## Context

ADR 0011 signed releases through the cloud-managed Developer ID certificate of Xcode. Xcode signs the app and the code that it builds, but the private key never reaches the Mac, so `codesign` cannot sign anything with it.

[ADR 0014](0014-fints-through-hbci4java.md) puts hbci4java and a Java runtime from `jlink` into `Contents/Resources/FinTSHelper`. The runtime has about 30 Mach-O files that Xcode does not build. Notarization refuses an app with one Mach-O file that lacks the Developer ID, the hardened runtime, or a secure timestamp. So `scripts/build-app.sh developer-id` left the FinTS helper out (task 3.2 of add-fints-banking), and a release could not use FinTS. Moving the runtime to a place where the export of Xcode signs it relies on behavior that Apple does not document.

## Decision

- Releases are signed with a Developer ID Application certificate of the team Adanos Software GmbH whose private key the owner exports as a `.p12` file.
- The `.p12` file and its password are secrets of the GitHub environment `build`, which allows only the branch `main` and the tags `v*`. The release workflow imports them into a temporary Keychain on the runner and deletes it at the end of the job.
- `scripts/build-app.sh developer-id` archives and exports the app with manual signing and this certificate, with the hardened runtime and a secure timestamp. Then it signs the FinTS helper and its Java runtime with the same certificate. The same command works on a Mac of the owner that has the certificate in its Keychain.
- `notarytool` notarizes with an App Store Connect API key with the Developer role, also a secret of the environment `build`. The key cannot create certificates.
- The private update key of Sparkle stays in the environment `release` (design of add-software-update). The Developer ID alone cannot sign an update that the app installs, because the app requires a feed signed with the update key.

## Consequences

- A private key of the Developer ID exists outside Apple: in the GitHub secret and in the backups of the owner. If it leaks, an attacker can sign apps in the name of the project, but not updates of installed copies. The owner then revokes the certificate in the Apple Developer account, creates a new one, and replaces the secret. Apps that were notarized before the revocation keep working.
- Each Developer ID certificate is valid for five years. [docs/releasing.md](../releasing.md) has the steps to renew it.
- The FinTS helper ships in every release, and task 3.2 of add-fints-banking can be checked on a release build.
- Contributors without the certificate build as before, signed to run locally or with their own team.

## Alternatives

- **The cloud-managed certificate, and the runtime where the export signs it.** No private key outside Apple, but it depends on how Xcode treats unknown Mach-O files in a bundle, which Apple does not document. A change in Xcode would break releases at notarization.
- **A release Mac of the owner.** The key stays on one Mac, but every release then needs that Mac, and the build is not reproducible in CI.
