# Proposal: Install and update extensions from a signed catalog

## Why

A scraper breaks when a website changes, and a fix must reach users within hours, not with the next app release. Users also need a way to tell a reviewed extension from an unknown file. A signed catalog gives both. It is the counterpart of the signature check and the download list that MoneyMoney offers.

## What Changes

- The settings tab "Extensions" shows a catalog of reviewed extensions. The user installs, updates, and removes extensions there.
- The app checks the signature of the catalog index and the digest of each script and manifest before an extension runs.
- A setting "Verify digital signatures of extensions" is on by default. While it is on, only catalog extensions run.
- The app looks for updates of installed catalog extensions and installs them.
- An extension that the user approved before the catalog existed needs a decision from the user after the update to this version.

## Capabilities

### New Capabilities

- `extension-catalog`: the signed catalog, the signature check and its setting, and installing, updating, and removing catalog extensions in the app.

### Modified Capabilities

None.

## Impact

- Milestone: v0.3
- Issues: #37
- Modules: `ExtensionConnector` verifies the index and the digests. `App` owns the catalog list in the settings. The catalog itself is a separate repository in which every change is reviewed.
- Depends on the change `add-web-banking-extensions`. The warning for extensions from outside the catalog is defined there and stays in force.
- Decisions: [ADR 0004](../../../docs/decisions/0004-moneymoney-compatible-extension-api.md), [ADR 0008](../../../docs/decisions/0008-payments-only-through-licensed-channels.md), [ADR 0002](../../../docs/decisions/0002-local-first-no-server.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The settings tab "Extensions" has the setting "Verify digital signatures of extensions" with the note "Deactivate only for self-developed (unsigned) extensions!". See [analysis](../../../docs/research/moneymoney-analysis.md#settings-u).
- The app runs an unsigned extension only after the user turns the check off. See [analysis](../../../docs/research/moneymoney-analysis.md#lua-extensions-w).
- Community extensions are reviewed by the vendor before they are published, against a checklist ([Web Banking API page](https://moneymoney.app/api/webbanking/)).
- Users download community extensions by hand from the [extensions page](https://moneymoney.app/extensions/) and copy them into the "Extensions" folder. The page states for each extension what it fetches.
- Built-in bank scripts are updated from the vendor's server without an app update. See [analysis](../../../docs/research/moneymoney-analysis.md#not-carried-over).

### Decided for MonetenMoneten

- The catalog can be browsed inside the app. MoneyMoney has a web page for this.
- The signature covers a catalog index, and the index lists a SHA-256 digest for each file (issue #37). MoneyMoney signs each script.
- The app installs updates of catalog extensions by itself, and a setting turns that off. The reason is that a fix must arrive within hours.
- The app rejects an index that is older than the newest index it has accepted.
- After the update to the first version with a catalog, the app asks once what to do with installed extensions that are not in the catalog.
- When the catalog cannot be reached, installed extensions keep running with the last accepted index.
- The catalog entry shows the hosts from the manifest before the user installs.
- A request to the catalog carries no personal data and no list of installed extensions.
