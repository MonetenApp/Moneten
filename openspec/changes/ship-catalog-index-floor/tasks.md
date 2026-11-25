# Tasks

## 1. Requirements

- [x] 1.1 A new data folder refuses an index below the shipped bound and accepts one at the bound. Verified by `IndexVerifierTests/aNewDataFolderRefusesAnIndexOlderThanTheRelease` (bound 140: 139 refused, 140 accepted).
- [x] 1.2 A higher floor still decides. Verified by `IndexVerifierTests/aHigherFloorStillDecides` (bound 140, floor 200: 150 refused as replayed).
- [x] 1.3 The bound is read from text, and only a positive number counts. Verified by `IndexVerifierTests/lowestVersionFromText` and `IndexVerifierTests/shippedLowestIndexVersionIsReadable`.

## 2. App and release

- [x] 2.1 `ExtensionLibrary` reads `lowest-index-version` from `Contents/Resources` with the keys, and uses no catalog without it.
- [x] 2.2 `scripts/release.sh` checks the bound in `dry-run` and `preflight`, refuses a value lower than an earlier tag, and checks the file in the app on the disk image.
- [x] 2.3 The checklist in `docs/releasing.md` names the step that raises the bound.
