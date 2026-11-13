# Proposal: Install and update extensions from a signed catalog

## Why

A scraper breaks when a website changes, and a fix must reach users within hours, not with the next app release. Users also need a way to tell a reviewed extension from an unknown file. A signed catalog gives both. It is the counterpart of the signature check and the download list that MoneyMoney offers.

## What Changes

- The menu item "Extensions" opens a window that lists the installed extensions and the catalog extensions that can be installed, each with its description. The user installs, updates, and removes extensions there.
- The catalog lives in the public repository `MonetenApp/moneten-extensions`. Checks and one maintainer review every package and every update.
- The app accepts a catalog index only when it is signed with one of two public keys in the app, and only when its version number is higher than the floor of the key that signed it. It checks the digest of every file before an extension runs.
- A catalog package needs a manifest with its hosts, its login field labels, its kinds of data, its API version, and its license.
- An update without a new host or login field installs by itself while the setting "Update extensions automatically" is on, which is the default. An update that adds either waits for the user's confirmation. With the setting off, every update waits.
- The index can mark a package as blocked, withdrawn, or unmaintained.
- An extension installed from a file runs after a warning and stays marked "Unverified". There is no setting that turns a signature check off.
- The app contacts only `extensions.monetenapp.com` for the catalog.

## Capabilities

### New Capabilities

- `extension-catalog`: the signed catalog, the Extensions window, and installing, updating, and removing catalog extensions in the app.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #37, #87, #88
- Modules: `ExtensionCatalog` verifies the index, downloads and checks the packages, and plans updates. `ExtensionConnector` checks the digests before a session. `App` owns the Extensions window. The catalog itself is the separate repository `MonetenApp/moneten-extensions`.
- Depends on the change `add-web-banking-extensions`. The warning and the mark "Unverified" for extensions installed from a file are defined there.
- Depends on the change `add-account-setup` for the add account assistant, which issue #85 builds and which is not built yet. Without it, the user cannot set up an account with an installed extension in the app.
- Decisions: [ADR 0015](../../../../docs/decisions/0015-extension-program.md), [ADR 0004](../../../../docs/decisions/0004-moneymoney-compatible-extension-api.md), [ADR 0006](../../../../docs/decisions/0006-license-gpl-3.md), [ADR 0008](../../../../docs/decisions/0008-payments-only-through-licensed-channels.md), [ADR 0002](../../../../docs/decisions/0002-local-first-no-server.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The settings tab "Extensions" has the setting "Verify digital signatures of extensions" with the note "Deactivate only for self-developed (unsigned) extensions!". See [analysis](../../../../docs/research/moneymoney-analysis.md#settings-u).
- The app runs an unsigned extension only after the user turns the check off. See [analysis](../../../../docs/research/moneymoney-analysis.md#lua-extensions-w).
- Community extensions are reviewed by the vendor before they are published, against a checklist ([Web Banking API page](https://moneymoney.app/api/webbanking/)).
- Users download community extensions by hand from the [extensions page](https://moneymoney.app/extensions/) and copy them into the "Extensions" folder. The page states for each extension what it fetches.
- Built-in bank scripts are updated from the vendor's server without an app update. See [analysis](../../../../docs/research/moneymoney-analysis.md#not-carried-over).

### Decided for Moneten

- The catalog is browsed and installed in the app, in the "Extensions" window, and updates arrive by themselves unless the user turns "Update extensions automatically" off. MoneyMoney has a web page and manual downloads ([ADR 0015](../../../../docs/decisions/0015-extension-program.md)).
- Files from outside the catalog run after a warning and stay marked "Unverified". MoneyMoney refuses unsigned files until the user turns its signature check off. Moneten has no such setting.
- A catalog package needs a manifest with its hosts, its login field labels, its kinds of data, its API version, and its license. MoneyMoney keeps the login labels in its own database.
- One signature covers a catalog index, and the index lists a SHA-256 digest for each file (issue #37). MoneyMoney signs each script.
- The app ships two public keys, current and next, and accepts an index signed with either until it has accepted one signed with the next key. Each key has its own version floor, and an app update drops the floor of a key it no longer ships.
- The index lists the digests of earlier versions that may still run, so an installed version that waits for an update keeps running under the signature.
- The app records whether each extension came from the catalog. A changed catalog package stays blocked and never runs as a file install.
- An update that adds a host or a login field waits for the user's confirmation, and the old version keeps running until then while the index still lists it. Every other update installs by itself, because a fix must arrive within hours.
- Each key has its own version floor. The app rejects an index whose version number is not higher than the floor of its key. The first index of the next key starts a new floor, so a leaked current key that signs a huge version stops updates only until the project rotates.
- The index marks a package as blocked, which stops it at once, as withdrawn, which stops it, or as unmaintained, which keeps it running with a note. A package is unmaintained after 90 days without an answer from its author to a failure that others can reproduce.
- When the catalog cannot be reached, installed extensions keep running with the last accepted index.
- The details show the hosts, the login field labels, and the license before the user installs.
- The app contacts only `extensions.monetenapp.com` for the catalog. A request carries no personal data and no list of installed extensions.
- A catalog package can hold several Lua files. Every MoneyMoney extension is one file.
