# 0021. Let the catalog checks run the signed release of ext

Status: Accepted

This decision amends one sentence of point 11 of [ADR 0015](0015-extension-program.md): "The checks of the catalog repository build `ext` from the app repository at a pinned commit, so nobody uploads a binary." The checks now run the signed release of `ext` that the app repository publishes.

## Context

ADR 0015 kept binaries out of the catalog: its checks built `ext` with Swift at a commit that `tools/ext.lock` named, and authors did the same with Xcode. [ADR 0019](0019-ext-releases-in-the-build-environment.md) and issue #105 added a release of `ext`: a tag `ext-v<version>` on `main` of the app repository builds one universal binary in `.github/workflows/release-ext.yml`, signs it with the Developer ID of the project, notarizes it, and publishes it with its SHA-256. The first release is `ext-v0.1.0`. The catalog checks and the author guide now use that release (MonetenApp/moneten-extensions#10).

## Decision

- `tools/ext.lock` of the catalog repository pins the release by its version, its commit in the app repository, the URL of its zip, and the SHA-256 of the zip.
- The job `ext test` of the catalog downloads that zip, checks the SHA-256 before it unpacks it, checks that `ext --version` names the pinned version and commit, and checks that the commit lies on `main` of the app repository and that the tag `ext-v<version>` points at it. Then it replays the packages with that binary.
- Nobody uploads a binary by hand: only the release workflow of the app repository builds and publishes `ext`, from a protected tag on `main`.

## Consequences

- Authors install `ext` without Xcode, and the checks need no Swift toolchain.
- The catalog trusts a binary instead of a build from source. The binary is bound to its source by the pinned commit that `ext --version` prints, by the tag that the check reads, and by the SHA-256. A reader who doubts the binary can still build the same commit from source.
- A new version of `ext` reaches the catalog only through a pull request that changes `tools/ext.lock`.

## Alternatives

- **Keep building from source in the catalog.** It keeps the old rule, but the checks then test another binary than the one authors install, and every check run needs the Swift toolchain.
