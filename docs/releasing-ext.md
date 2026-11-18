# Releasing ext

This page explains how a maintainer releases the `ext` tool for extension authors. The [design of add-extension-developer-tools](../openspec/changes/add-extension-developer-tools/design.md#release-of-the-tool) explains why the release works this way.

A release starts with a tag `ext-v<version>`. `.github/workflows/release-ext.yml` then runs `scripts/release-ext.sh`. It builds `ext` as one universal binary for Apple silicon and Intel Macs, links the commit of the tag into it, signs it with the Developer ID, and notarizes it. Then it runs the replay of the example extension with the binary from the zip and publishes the GitHub release `ext-v<version>` with these files:

| File | Content |
|---|---|
| `ext-<version>-macos.zip` | The signed and notarized `ext`, the file that Apple notarized |
| `ext-<version>-macos.zip.sha256` | Its SHA-256 in the format of `shasum -a 256 -c` |

The text of the release names the SHA-256, the commit, and the install steps. `ext --version` of the release prints "ext 0.1.0 (commit <full commit>), API version 1". A build from source prints no commit.

## Dry run

The dry run needs no secrets and contacts no service. It builds the same zip, signs the binary to run locally, and runs the same checks:

```sh
scripts/release-ext.sh dry-run       # writes dist/ext
```

The workflow runs the dry run on each pull request that changes an input of `ext`: `Tools/ext`, the libraries that it links (`Domain`, `CLua`, `ExtensionHost`, and `ExtensionConnector`), `Package.swift`, `Package.resolved`, the packaging, or the example extension that the check replays. A change elsewhere in `Sources`, such as `Storage` or `FinTS`, cannot change the binary and skips the dry run. The `test` job of CI still builds and tests `ext` for it.

## Set up once

The release uses the secrets of the app release, so the owner creates them only once. Without them the workflow fails at its first step and names each missing secret.

1. Create the secrets and the variable of the GitHub environment `build`, as [the release guide of the app](releasing.md#secrets) describes: `DEVELOPER_ID_CERTIFICATE_P12`, `DEVELOPER_ID_CERTIFICATE_PASSWORD`, `NOTARY_API_KEY_P8`, `NOTARY_API_KEY_ID`, `NOTARY_API_ISSUER_ID`, and the variable `APPLE_TEAM_ID`. The release of `ext` does not need `FINTS_PRODUCT_ID` or the update key.
2. Under Settings, Environments, `build`, "Deployment branches and tags", add the tag pattern `ext-v*` next to `main` and `v*` ([ADR 0019](decisions/0019-ext-releases-in-the-build-environment.md)). Without it GitHub refuses to start the job.
3. Under Settings, Rules, add the tags `ext-v*` to the [ruleset](releasing.md#protected-tags) that allows only the owner to create, update, or delete the tags `v*`. A tag starts a signed release, so nobody else may push one.

The job that holds the certificate can only read the repository. A second job without secrets creates the release. The workflow never marks the release as the latest release, because the update feed of the app lives on the latest release. GitHub still reports `ext-v0.1.0` as the latest release while it is the only published release. The release scripts of the app accept that before the first version of the app, which takes the mark when it is published.

## Release a version

1. If the tool changed since the last release, raise `version` in `Tools/ext/Ext.swift` and the expected line of `helpAndVersion` in `Tests/ExtToolTests/CommandTests.swift` in a pull request, and merge it.
2. Tag the merge commit on `main` and push the tag: `git tag ext-v0.1.0 && git push origin ext-v0.1.0`.
3. The workflow checks that the tag names the version of `Tools/ext/Ext.swift` and that the commit lies on `main`. Otherwise it stops before it signs anything.
4. When the run is green, open the release. On a Mac without Xcode, run the install steps from its text, and check that `ext --version` prints the commit of the tag.
5. Update the catalog repository [moneten-extensions](https://github.com/MonetenApp/moneten-extensions): its `tools/ext.lock` pins the version, the commit, and the SHA-256, and the install steps of its author guide name the new version.

To start over after a failed run, delete the release if one exists, and run the failed jobs again under Actions. A tag that points to the wrong commit is deleted and pushed again only before anybody installed the release. Otherwise release a new version.
