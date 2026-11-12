# Design

## Context

Issue #86 builds this change for FinTS on the sync model of [add-account-refresh](../add-account-refresh/design.md) and the bank accesses of [add-account-setup](../add-account-setup/design.md). [ADR 0009](../../../docs/decisions/0009-database-password-as-in-moneymoney.md) decides that a saved PIN lives in the encrypted database. [ADR 0005](../../../docs/decisions/0005-grdb-and-sqlcipher.md) and [ADR 0014](../../../docs/decisions/0014-fints-through-hbci4java.md) apply. Extensions and the subscription use the same path when they exist.

## Decisions

### Where a saved PIN lives

`Storage` keeps a saved PIN in the table `savedPIN`: one row per access, with the primary key `accessID` and the PIN as text. The row goes with its access, so removing the last account of an access deletes the PIN too. Migration `v8` adds the table. A separate table keeps the PIN out of `AccessState`, which only its connector reads, and out of every other row. The database file is encrypted with the database password, so a backup of the file holds the PIN under the same password ("Restore on another Mac"). No code writes a PIN to the Keychain, the settings, or a log.

`Domain` declares `SavedPINStore`, and `Store` implements it. `Sync` sees only the protocol.

### When a PIN is saved

`SessionBroker` owns the PIN of each access in memory and the rule for saving it:

- The PIN sheet has "Save PIN", off each time the sheet appears. The answer `.pin(secret, save:)` carries the choice.
- The broker writes the PIN through `SavedPINStore` when the refresh with it finishes. A finished refresh means that the bank accepted the login. A rejected or failed login saves nothing.
- The login step of "Add Account" has the same option. The bank accepted that PIN when the setup listed the accounts, so `remember(_:for:save:)` saves it when the setup finishes.
- When the database opens, `open(_:)` reads the saved PINs into memory, so the first refresh after a restart or an unlock does not ask. When the app locks, `forgetPINs()` forgets every PIN.
- When the bank rejects a PIN, the broker forgets it and deletes the saved one, so no automatic refresh sends it again. Any other failure keeps a saved PIN and forgets an unsaved one, as before.
- "Remove saved PIN" in the account settings calls `removeSavedPIN(of:)`, which deletes the row and forgets the PIN in memory, for every account of the access.

### The rules of the bank

`PINRules` holds digits only, the minimum length, and the maximum length, and `check(_:secretName:)` names the first broken rule. `PINRequest.rules` brings them to the sheet, which checks the PIN at "OK" and sends nothing while a rule is broken. The FinTS helper reads the minimum and maximum length from the bank parameters (`getPinLengthMin` and `getPinLengthMax` of hbci4java).

### The PIN field

The field is a `SecureField` with no content type, which macOS shows as a secure text field. It hides the characters and does not allow "Copy".

### The PIN of a new dialog

When the user changes the TAN method, the FinTS helper starts a new dialog with the bank (see the [design of add-tan-handling](../add-tan-handling/design.md)). The helper uses the PIN of the run again for it, unless the bank rejected that PIN.

## Deviations from the spec

- FinTS bank parameters state no rule for digits only, so a FinTS PIN is checked only for its length. The rule works for a source that states it.
- "Remove saved PIN" also forgets the PIN in memory, so the next refresh asks at once, not only after a restart.
- A refresh that fails after a successful login does not save the PIN. The next successful refresh with the option on saves it.
- The secret is called "PIN" for every FinTS access, because hbci4java gives no other name. The words of extensions come with E6.

## Risks / Trade-offs

- A saved PIN is as safe as the database password. A database without a password keeps its random key in the Keychain, so there the PIN is as safe as the Keychain of the user.
