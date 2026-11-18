# 0021. Let the catalog checks run the signed release of ext

Status: Accepted

This decision amends one sentence of point 11 of [ADR 0015](0015-extension-program.md): "The checks of the catalog repository build `ext` from the app repository at a pinned commit, so nobody uploads a binary." The checks now run the signed release of `ext` that the app repository publishes.

## Context

ADR 0015 kept binaries out of the catalog: its checks built `ext` with Swift at a commit that `tools/ext.lock` named, and authors did the same with Xcode. [ADR 0019](0019-ext-releases-in-the-build-environment.md) and issue #105 added a release of `ext`. A tag `ext-v<version>` on `main` of the app repository starts `.github/workflows/release-ext.yml`. The workflow builds one universal binary, signs it with the Developer ID of the project, and notarizes it. Then it publishes the zip with its SHA-256. The first release is `ext-v0.1.0`. The catalog checks and the author guide now use that release (MonetenApp/moneten-extensions#10).

## Decision

- `tools/ext.lock` of the catalog repository pins the release by its version, its commit in the app repository, the URL of its zip, and the SHA-256 of the zip.
- The job `ext test` of the catalog downloads that zip and checks its SHA-256. It requires one regular file `ext` in the zip and checks the Developer ID signature of the project before it runs the binary. It checks that `ext --version` names the pinned version and commit, and that the tag `ext-v<version>` names that commit on `main` of the app repository. Then it replays the packages with that binary.
- The catalog accepts only the zip whose SHA-256 a reviewed `tools/ext.lock` names. By policy, only `release-ext.yml` publishes it.

## Consequences

- Authors install `ext` without Xcode, and the checks need no Swift toolchain.
- The catalog trusts a binary instead of a build from source. Nothing in the checks proves that the binary was built from the pinned commit. The binary prints its own version line, the tag check never reads the binary, and the SHA-256 comes from the release itself. The build is not reproducible, so a build from the same commit gives another binary with another signature.
- The trust now lies in three places: `release-ext.yml`, the ruleset of ADR 0019 that lets only the owner create `ext-v*` tags, and the Developer ID secrets in the environment `build`. Whoever controls an `ext-v*` tag or that environment can publish any binary signed with the Developer ID of the project. That binary passes `ext test` once a reviewed pull request pins its SHA-256.
- The SHA-256 protects only against a zip that someone swaps after the lock was reviewed, for example with `gh release upload --clobber`. The version and tag checks catch a wrong pin, not a hostile binary. The signature check catches a binary that the project did not sign.
- A hostile binary can run any code on the job runner and fake the result of the replay. The job gets no secrets and no write permission on the repository, and the index signing key stays in a separate job. The review of a maintainer still applies to every package.
- A new version of `ext` reaches the catalog only through a pull request that changes `tools/ext.lock`.

## Alternatives

- **Keep building from source in the catalog.** It keeps the old rule, but the checks then test another binary than the one authors install, and every check run needs the Swift toolchain.
- **Build provenance attestations.** `release-ext.yml` could attest the zip with `actions/attest-build-provenance`, and the catalog could check it with `gh attestation verify`. This is the one option that binds the binary to its commit and its workflow. It is not part of this decision, because the trust of the signature and the reviewed lock is enough for a tool that only replays recordings. A later decision can add it.
