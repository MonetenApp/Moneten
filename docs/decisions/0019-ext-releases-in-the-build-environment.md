# 0019. Sign releases of ext in the environment build

Status: Accepted

This decision amends one point of [ADR 0016](0016-developer-id-certificate-in-ci.md): the GitHub environment `build` "allows only the branch `main` and the tags `v*`". It now also allows the tags `ext-v*`.

## Context

Extension authors build `ext` from a pinned commit with Xcode, and the checks of the catalog repository do the same (issue #105). A signed and notarized binary removes the Swift toolchain from their path and gives them a SHA-256 to check. `.github/workflows/release-ext.yml` builds that binary when a maintainer pushes a tag `ext-v<version>`. It needs the Developer ID certificate and the notary key, which live only in the environment `build`. GitHub refuses to start a job of an environment for a tag that the environment does not allow, so with the rule of ADR 0016 every release of `ext` stops before it starts.

## Decision

- The environment `build` allows the branch `main`, the tags `v*` of the app, and the tags `ext-v*` of the `ext` tool.
- The tags `ext-v*` are protected like the tags `v*`: only the owner can create, update, or delete them.
- A release of `ext` uses the same Developer ID certificate and App Store Connect API key as the app. It never uses the private update key in the environment `release`, and it never becomes the latest release, which carries the update feed of the app.
- The job that holds the certificate can only read the repository. A second job without secrets creates the release.

## Consequences

- The owner sets up the signing secrets once for both releases. [docs/releasing.md](../releasing.md) and [docs/releasing-ext.md](../releasing-ext.md) name the third tag pattern.
- A second workflow can now use the certificate. The job receives the secrets as soon as it starts, before the workflow checks that the tag lies on `main`, so the protection of the tags `ext-v*` is what keeps the secrets safe. With that ruleset, the exposure stays the same as before: only the owner can start a job that signs.
- A signed `ext` that leaks or misbehaves is handled like a signed app: revoke the certificate as ADR 0016 describes.

## Alternatives

- **A separate environment for `ext` with its own copy of the secrets.** It keeps the rule of ADR 0016, but the owner must keep two copies of the certificate and the key in step, and a revoked certificate must be replaced twice.
- **An unsigned `ext`.** Gatekeeper then blocks a downloaded binary, and each author must remove the quarantine flag by hand, which teaches authors to trust unsigned code.
