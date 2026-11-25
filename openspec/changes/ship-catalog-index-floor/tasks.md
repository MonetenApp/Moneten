# Tasks

## 1. Requirements

- [x] 1.1 A new data folder refuses an index below the shipped bound and accepts one at the bound. Verified by `IndexVerifierTests/aNewDataFolderRefusesAnIndexOlderThanTheRelease` (bound 140: 139 refused, 140 accepted).
- [x] 1.2 The higher of floor and bound decides. Verified by `IndexVerifierTests/theHigherOfFloorAndBoundDecides` (floor 50, bound 140: 60 refused for both keys, 140 accepted; floor 200: 150 refused as replayed) and `IndexVerifierTests/theShippedBoundAppliesToEveryKey` (first index 130 of the next key refused).
- [x] 1.3 The keys need every shipped file, and only a positive number counts. Verified by `IndexVerifierTests/shippedKeysNeedEveryFile`, `IndexVerifierTests/lowestVersionFromText`, and `IndexVerifierTests/shippedFilesGiveKeys`.
- [x] 1.4 A stored index below the bound is not restored, and its floors stay. Verified by `IndexVerifierTests/aStoredIndexBelowTheBoundIsNotRestored`.
- [x] 1.5 Without an accepted index, no catalog package runs. Verified by `UpdatePlanTests/noAcceptedIndexStopsEveryCatalogPackage`.

## 2. App and release

- [x] 2.1 `ExtensionLibrary` builds the keys with `CatalogKeys.shipped`, restores the stored index with `IndexVerifier.restored` only with keys, and stops catalog packages without an index.
- [x] 2.2 `scripts/release.sh` checks the bound in `dry-run` and `preflight`: a lowered value, a tag whose file cannot be read, a shallow checkout, and in `preflight` a published version without its tag. `check_dmg` checks the file in the app on the disk image.
- [x] 2.3 The checklist in `docs/releasing.md` names the step that raises the bound.

## 3. The first check at launch (issue #579)

- [x] 3.1 A refresh waits for the check that runs and returns when it ends, two requests share one check, the wait ends at its limit or at a cancel, and a canceled check lets the next request start its own. Verified by `IndexCheckTests`.
- [x] 3.2 The limit counts from the start of the check, so a refresh that starts late does not wait once more. Verified by `IndexCheckTests/theLimitCountsFromTheStartOfTheCheck`. Without an index, a catalog package stops with "Moneten has no list…" after the wait, as `UpdatePlanTests/noAcceptedIndexStopsEveryCatalogPackage` verifies.
- [x] 3.3 `ExtensionLibrary` runs each check through `IndexCheck`, waits in the connector of a catalog package while it holds no index, and cancels the check at the lock. The app has no unit tests, so this wiring is checked by review and by the build, not by a test.
