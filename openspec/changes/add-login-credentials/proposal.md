# Proposal: Ask for PINs and save them only on request

## Why

The PIN of an online banking access is the most sensitive value the app handles. Users who switch from MoneyMoney know one rule. The app saves a PIN only when they say so, and it asks otherwise. [ADR 0009](../../../docs/decisions/0009-database-password-as-in-moneymoney.md) adopts that rule. This change turns it into behavior that can be tested, for FinTS, for extensions, and for the subscription alike.

## What Changes

- The app asks for a PIN or password in one sheet that names the account, the bank, and the user ID.
- The user can turn on saving for each access. A saved PIN lives in the encrypted database.
- Without saving, the app keeps the PIN in memory until it locks or quits.
- "Remove saved PIN" in the account settings deletes a saved PIN.
- The app never saves a TAN.
- After a wrong PIN the app drops the PIN and asks again. It never repeats a failed login by itself.
- The automatic refresh skips an access whose PIN is not available and marks it.

## Capabilities

### New Capabilities

- `login-credentials`: how the app asks for, keeps, saves, and removes the PINs and passwords of all access kinds.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #4, #13
- Modules: `Storage` keeps saved secrets in the encrypted database. `Domain` owns the rule for when a secret is available. `App` owns the PIN sheet and the button in the account settings. `FinTSConnector`, `ExtensionConnector`, and later `FinAPIConnector` ask for secrets through the same path.
- Depends on the change `add-encrypted-database` for the storage and on `add-app-lock` for the moment when the app locks.
- Decisions: [ADR 0009](../../../docs/decisions/0009-database-password-as-in-moneymoney.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- MoneyMoney saves PINs and passwords only on request and asks at each launch otherwise (https://moneymoney.app/security/).
- The PIN sheet shows the user ID next to the account name (version history).
- The account settings have the button "Remove saved PIN". See [analysis](../../../docs/research/moneymoney-analysis.md#account-settings-u-s).
- Strings show checks of a PIN against rules of the bank before it is sent, for example that it must be numeric, its minimum and maximum length, and characters that a server does not accept.
- Strings show the bank's own names for secrets, for example "online banking PIN", "password", and "API key".
- The app no longer uses the macOS password manager for its fields, because that caused network connections (version history 2.4.49 and 2.4.50).
- While the app is locked, no account is refreshed in the background (version history 2.4.49).

### Decided for MonetenMoneten

- A saved PIN is stored in the encrypted database and not in the Keychain. This follows ADR 0009. Where MoneyMoney stores it was not observed.
- Saving is off when the sheet first appears for an access.
- A PIN that is not saved is forgotten when the app locks, not only when it quits. This follows ADR 0009.
- After a wrong PIN the app deletes the saved PIN and warns that more wrong attempts can block the access. MoneyMoney's behavior was not observed.
- The automatic refresh skips an access without an available PIN and marks it in the sidebar. This follows issue #40.
- When several accesses need a PIN in one manual refresh, the app asks for one PIN at a time. The order in MoneyMoney was not observed.
- Extension passwords and subscription tokens follow the same rules as FinTS PINs.
