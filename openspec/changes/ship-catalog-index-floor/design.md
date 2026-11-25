# Design

## Context

[ADR 0015](../../../docs/decisions/0015-extension-program.md) gives each catalog key its own version floor and lets an app update start from the lowest index version that it ships (decision 23). Its consequences say that each release records that version. The module `ExtensionCatalog` checks an index in `IndexVerifier.check`, which refuses an index below `CatalogKeys.lowestVersion` while neither key has a floor. The app built the keys with the constant 1, so a new data folder accepted every index that the project ever signed.

## Decisions

### The bound is a file next to the keys

`App/Resources/CatalogKeys/lowest-index-version` holds one positive number. The app target copies it into `Contents/Resources` beside `current.pub` and `next.pub`, and `ExtensionLibrary` reads all three at launch. `CatalogKeys.shipped` in `ExtensionCatalog` turns the three texts into the keys, so the tests check the rule and the shipped files without the app. When one of them is missing or cannot be read, there are no keys, and the app never falls back to a bound of 1, which would accept every old index.

The file sits beside the keys because decision 23 pairs the bound with the keys that a build ships. A build setting in `App/project.yml` would work too, but a plain file is easier to read from the checkout, from an earlier tag with `git show`, and from the app on a disk image.

The throwaway keys of a Debug build, which `MONETEN_CATALOG_URL` and `MONETEN_CATALOG_KEYS` name, keep the bound 1. They sign local indexes for the live checks, whose versions follow no release, and they never meet an index of the real catalog.

### The bound applies with every floor

`IndexVerifier.check` refuses an index below the bound before it looks at the floors. So the higher of the floor and the bound decides. A data folder that accepted only index 50 refuses index 60 after an update to a release that ships 140, and so does the first index of the next key while only the current key has a floor. Decision 23 lets an update start from the bound when it drops the floors of retired keys. Applying the bound to kept floors too is stricter and follows from the consequence that each release records the lowest index version it accepts.

### No accepted index, no catalog

Without keys, the app restores no stored index. With keys, `IndexVerifier.restored` drops a stored index below the bound and keeps the floors. In both cases the app holds no index, and nothing from the catalog shows, installs, or runs. `Standing(of:in:)` with no index stops every catalog package. Before this change, a catalog package without an index ran without a check of its standing. That was only possible when the stored index could not be read, but with the bound it happens after each update that raises it, so it must fail closed. A package installed from a file is not affected. The app downloads the index at launch, so a Mac that is online runs the catalog packages again within seconds.

### The release raises it by hand, and the release check stops a lower one

The newest index version lives in the catalog repository and on `extensions.monetenapp.com`, not in this repository. The release check does not read it:

- A check against the live catalog would trust the same host that the bound protects against. A server that serves an old index would serve the same old version to the check.
- The dry run builds and checks a release without network access to the catalog, and a release must not fail because the catalog host is down.

So raising the bound is a step of the release checklist in [docs/releasing.md](../../../docs/releasing.md): in the release pull request, the owner sets the file to the version of the newest index that the catalog signed. The owner takes the version of an index that exists. A bound above every signed index makes the new app refuse each index until the catalog signs one at least that high.

What the release tooling can check is the history of this repository. `scripts/release.sh` checks in `dry-run` and in `preflight` that the file holds one positive number and that no earlier tag `v*` of the app shipped a higher one. A tag from before the file is skipped, but a tag whose file cannot be read stops the release. Both refuse a shallow checkout, and `preflight`, which reads the releases from GitHub anyway, refuses a checkout that lacks the tag of a published version, so a clone without tags cannot pass. `check_dmg` checks that the app on the disk image carries the same file as the checkout. So a release can forget to raise the bound, which the checklist covers, but it can never lower it or ship another value than the checkout.

### What stays open

The app still accepts an index that the catalog signed after the bound of the release and before the newest one, when its floor is lower. Each release narrows that window to the indexes signed since the release before. Real protection starts with the first release that raises the file above 1.

### A refresh waits for the check of the catalog

After an update that raised the bound, the app holds no index until the first check at launch accepts one. The automatic refresh starts with the unlock, before that check ends, so without a wait every account of a catalog extension that is due would fail its refresh with "Moneten has no list…", even on a Mac that is online, and the next refresh could be hours away (issue #579).

So a refresh of a catalog extension that starts without an accepted index waits for the check that runs, and starts one when none runs. The second part covers a Mac that was offline at launch: the automatic refresh waits for the connection anyway, and the first refresh after it then checks the catalog instead of failing until the daily check. The wait ends 30 seconds after the check started, not 30 seconds after the refresh started. The refresh coordinator runs three accesses at a time, so with five due accesses of catalog extensions and a catalog that does not answer, a limit per refresh would let the last two wait another 30 seconds, and a FinTS access behind them about 60 seconds. With the limit counted from the start of the check, every refresh that waits for one check stops waiting at the same time, and the rest of the line goes on. A canceled refresh stops waiting at once. After the wait, the refresh checks the standing of the package as before, so a failed check ends in the existing message. A manual refresh waits the same way. A package installed from a file never waits, and neither does a catalog package while the app holds an index.

`IndexCheck` in the module `ExtensionCatalog` runs one check at a time: a second request joins the check that runs, and a refresh waits for it until the limit after its start. It keeps its state under a lock and runs its timer off the main actor, so the limit and a cancel end a wait on time also while the main actor is busy. `ExtensionLibrary` in the app runs each check through it and waits before it builds the connector of a session. The lock cancels the check that runs, so the next unlock starts its own. The updates that a check finds install after the check ends, so a refresh does not also wait for their downloads.
