# Proposal: Ship a lowest catalog index version that each release raises

Closes #563.

## Why

A new data folder has no version floor for either catalog key. The app then accepts every signed index whose version is at least the lowest index version of the build. That version is the constant 1 in the code, and no release step raises it. So a server that answers for the catalog host can give a new installation any index that the project ever signed, with package versions that a later index blocked or withdrew. [ADR 0015](../../../docs/decisions/0015-extension-program.md) expects each release to record the lowest index version it accepts (decision 23).

## What Changes

- The lowest index version moves from the code into a file next to the two catalog keys, which the app reads at launch.
- The app refuses an index below that version whatever floors it holds, so the higher of the floor and the version decides.
- Without an index that the build accepts, because the build lacks a readable file or the stored index is below the version, the app shows, installs, and runs nothing from the catalog.
- Each release raises the file to the version of the newest index that the catalog signed before the release. The release checklist names the step.
- `scripts/release.sh` refuses a release whose lowest index version is not a positive number or is lower than that of an earlier release, and checks that the app on the disk image carries the file of the checkout.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `extension-catalog`: "Index version floor" adds the lowest index version of the release. "An app update resets the floor of retired keys" no longer limits that version to data folders without floors. Two new requirements say that each release raises the version, and that the app uses no catalog without an index it accepts.

## Impact

- Milestone: v0.1
- Issues: #563
- Modules: `ExtensionCatalog` reads the lowest index version from its text. `App` loads the file with the keys. `scripts/release.sh` and `docs/releasing.md` hold the release step.
- Decisions: [ADR 0015](../../../docs/decisions/0015-extension-program.md), decisions 10 and 23.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- MoneyMoney has no signed catalog index with a version floor, so there is nothing to compare.

### Decided for Moneten

- A new data folder refuses an index below the lowest index version of the release. Each release raises that version, so an index older than the release cannot be replayed to a new installation.
