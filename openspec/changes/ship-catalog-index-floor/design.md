# Design

## Context

[ADR 0015](../../../docs/decisions/0015-extension-program.md) gives each catalog key its own version floor and lets an app update start from the lowest index version that it ships (decision 23). Its consequences say that each release records that version. The module `ExtensionCatalog` checks an index in `IndexVerifier.check`, which refuses an index below `CatalogKeys.lowestVersion` while neither key has a floor. The app built the keys with the constant 1, so a new data folder accepted every index that the project ever signed.

## Decisions

### The bound is a file next to the keys

`App/Resources/CatalogKeys/lowest-index-version` holds one positive number. The app target copies it into `Contents/Resources` beside `current.pub` and `next.pub`, and `ExtensionLibrary` reads all three at launch. `CatalogKeys.lowestVersion(_:)` in `ExtensionCatalog` turns the text into the number, so the tests check the rule and the shipped file without the app. A missing or unreadable file gives no keys, and the app then uses no catalog, as it does without its keys. A bound of 1 by mistake would accept every old index, so the app never falls back to a default.

The file sits beside the keys because decision 23 pairs the bound with the keys that a build ships. A build setting in `App/project.yml` would work too, but a plain file is easier to read from the checkout, from an earlier tag with `git show`, and from the app on a disk image.

The throwaway keys of a Debug build, which `MONETEN_CATALOG_URL` and `MONETEN_CATALOG_KEYS` name, keep the bound 1. They sign local indexes for the live checks, whose versions follow no release, and they never meet an index of the real catalog.

### The release raises it by hand, and the release check stops a lower one

The newest index version lives in the catalog repository and on `extensions.monetenapp.com`, not in this repository. The release check does not read it:

- A check against the live catalog would trust the same host that the bound protects against. A server that serves an old index would serve the same old version to the check.
- The dry run builds and checks a release without network access to the catalog, and a release must not fail because the catalog host is down.

So raising the bound is a step of the release checklist in [docs/releasing.md](../../../docs/releasing.md): in the release pull request, the owner sets the file to the version of the newest index that the catalog signed. The owner takes the version of an index that exists. A bound above every signed index makes the new app refuse each index until the catalog signs one at least that high.

What the release tooling can check offline is the history of this repository. `scripts/release.sh` checks in `dry-run` and in `preflight` that the file holds one positive number and that no earlier tag `v*` of the app shipped a higher one. `check_dmg` checks that the app on the disk image carries the same file as the checkout. So a release can forget to raise the bound, which the checklist covers, but it can never lower it or ship another value than the checkout.

### What stays open

A new data folder still accepts an index that the catalog signed after the release and before the newest one. Each release narrows that window to the indexes signed since the release before. An existing data folder keeps the floors it holds, which already refuse every older index.
