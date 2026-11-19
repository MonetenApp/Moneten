# Proposal: Explain an installed version that is newer than the listed one

Closes #186.

## Why

The catalog can list an older version than the installed one, for example after the publisher withdrew a release. The installed version then does not run, because the index does not list it. The message said "Open Extensions and install the update", but there is no update: the app never installs an older version as an update. The user followed advice that leads nowhere.

## What Changes

- When the listed version is older than the installed one, the refreshes of the extension stop with a message that says the catalog lists an older version and that there is no update to install.
- The "Extensions" window shows the extension with the badge "Stopped" and without the button "Update" or "Review Update".
- When the listed version is newer, nothing changes.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `extension-catalog`: the requirement "Only the listed version runs" names the case of an older listed version.

## Impact

- Milestone: v0.1
- Issues: #186
- Modules: `ExtensionCatalog` decides the standing of an installed package and its message. `App` shows the badge and the button.
- Decisions: [ADR 0015](../../../docs/decisions/0015-extension-program.md), decisions 13 and 24.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- MoneyMoney has no signed catalog with one listed version per package, so there is nothing to compare.

### Decided for Moneten

- An installed version that is newer than the listed one stops like a blocked extension: a running session ends when the index arrives, and the window offers no update. The user can remove the extension and install the listed version from the catalog.
