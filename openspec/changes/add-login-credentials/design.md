# Design

## Context

Issue #86 builds this change for FinTS on the sync model of [add-account-refresh](../add-account-refresh/design.md) and the bank accesses of [add-account-setup](../add-account-setup/design.md). [ADR 0009](../../../docs/decisions/0009-database-password-as-in-moneymoney.md) decides that a saved PIN lives in the encrypted database. [ADR 0005](../../../docs/decisions/0005-grdb-and-sqlcipher.md) and [ADR 0014](../../../docs/decisions/0014-fints-through-hbci4java.md) apply. Extensions and the subscription use the same path when they exist.

## Decisions

### Where a saved PIN lives

`Storage` keeps a saved PIN in the table `savedPIN`: one row per access, with the primary key `accessID` and the PIN as text. The row goes with its access, so removing the last account of an access deletes the PIN too. Migration `v9` adds the table. A separate table keeps the PIN out of `AccessState`, which only its connector reads, and out of every other row. The database file is encrypted with the database password, so a backup of the file holds the PIN under the same password ("Restore on another Mac"). No code writes a PIN to the Keychain, the settings, or a log.

`Domain` declares `SavedPINStore`, and `Store` implements it. `Sync` sees only the protocol.

### When a PIN is saved

`SessionBroker` owns the PIN of each access in memory and the rule for saving it:

- The PIN sheet has "Save PIN", off each time the sheet appears. The answer `.pin(secret, save:)` carries the choice.
- The broker writes the PIN through `SavedPINStore` when the refresh with it finishes. A finished refresh means that the bank accepted the login. A rejected or failed login saves nothing.
- The login step of "Add Account" has the same option. The bank accepted that PIN when the setup listed the accounts, so `remember(_:for:save:)` saves it when the setup finishes. When the access has a saved PIN already, for example because the user adds the same login again, the new PIN replaces it also with the option off.
- When the database opens, `open(_:)` reads the saved PINs into memory, so the first refresh after a restart or an unlock does not ask. When the app locks, `forgetPINs()` forgets every PIN.
- When the bank rejects a PIN or blocks the access, the broker forgets the PIN and deletes the saved one, so no automatic refresh sends it again. A blocked access opens no PIN sheet. This holds also when the bank reports the rejection or the block for one account of a refresh that finished, and when it comes in the "Add Account" login of a login that the app has already: `SetupSession` names that access with `replacing`. Any other failure keeps a saved PIN and forgets an unsaved one, as before.
- A connector reports a rejection or a block through `SyncSession.rejected(_:)` the moment the answer of the bank arrives, for the access or for one account. The session of a refresh and the session of "Add Account" forget the PIN then, so a cancel while the connector ends cannot keep it. The FinTS connector reads each line for this as it arrives, also a line that the helper writes after a cancel, while it ends. For an account, it takes the error that the account shows: a rejection or a block before any other error, and none when the transactions arrived. A rejection that arrives after the lock marks the access, and the next unlock deletes the row before it loads the saved PINs. The coordinator also reads the rejection from the report and from the error of the connector before it looks at a cancel or delivers the accounts, so an error of the storage cannot hide it either.
- When the database cannot delete a rejected PIN, the broker tries once more. If that fails too, the app shows "Could not remove the rejected PIN." and never uses that saved PIN: the settings keep the ID of the access (not the PIN) under the path of the database, because every data folder shares the settings. `open(_:)` deletes the row again at the next unlock, and only a row that it deletes clears the mark. Until then it does not load that PIN.
- A PIN in memory, saved or not, answers a PIN request only when it keeps the rules of that request. Otherwise a manual refresh shows the sheet, and an automatic refresh stops with `SyncFailure.needsUser(.pin)` without sending it.
- "Remove saved PIN" in the account settings calls `removeSavedPIN(of:)`, which deletes the row and forgets the PIN in memory, for every account of the access.

### The login data of an extension

An extension asks for its login data in one dialog with the fields of its manifest, else "Username" and "Password" (issue #536). The dialog has the save option of the PIN sheet: "Save" and the name of the secret, which is the label of the first secret field, else "Password", so the default dialog shows "Save Password". The option is off each time the dialog appears, as in the PIN sheet. The answer `.login(values, save:)` carries the choice. The login data is saved as a whole, with every field, because a refresh needs all of them to log in.

- `Storage` keeps saved login data in the table `savedLogin`: one row per access, with the primary key `accessID`, the values as a JSON list of text in the column `values`, and the fields that the values answered in the column `fields`: the key and the secrecy of each field, in order (`SavedLogin.Field`). Migration `v32` adds the table, and its rows go with their access, as the rows of `savedPIN` do. The saved PINs of FinTS stay in `savedPIN` and do not move, so no saved PIN is lost and no shipped migration changes. An access has a row in at most one of the two tables, because a FinTS access never asks for login data and an extension never asks for a PIN.
- `SavedPINStore` has `savedLogins()` and `saveLogin(_:for:)` beside the calls for PINs. `removeSavedPIN(of:)` deletes the saved secret of the access from both tables in one transaction, so "Remove saved PIN", a rejection, and the second deletion at the next unlock need no second path.
- `SessionBroker` keeps the login data of each access in memory beside the PINs and applies the same rules to both. `savedPINs` holds every access with a saved secret, PIN or login data, so "Remove saved PIN" is enabled for an extension account with saved login data. The broker saves the login data when the refresh with it finishes; a rejected or failed login saves nothing. `open(_:)` reads the saved login data into memory, so an automatic refresh after a restart or an unlock logs in without a dialog. A failed refresh keeps saved login data and forgets unsaved login data. A rejection (`SyncFailure.loginRejected`, or a login request with `rejected`) forgets the login data and deletes the saved one, with the same second try and mark as a rejected PIN.
- Login data answers a login request only when its fields equal those of the request: the same keys in the same order, each as secret as before (`SavedLogin.fits(_:)`). A count alone is not enough: an update of the extension that swaps "Username" and "Password" would send the password as the user ID, which the connector stores and shows as the login name. The key of a field is the label of the manifest, which is not localized, or for the fields without a manifest the fixed words "Username" and "Password", so a change of the language of the app never changes it.
- Saved data that no longer fits is never sent: the broker forgets it and deletes the saved row, so the access leaves `savedPINs`. Then a new answer with saving off follows the rule of unsaved data, and a failed refresh forgets it. Without the deletion the new values would stay in memory beside the old row, and the next automatic refresh would send them. A saved PIN that breaks the rules of the bank follows the same rule. The broker deletes the row as it deletes a rejected one: it tries twice, and when both fail it reports "Could not remove the saved PIN." or "Could not remove the saved login data.", marks the access, never loads the row again, and deletes it at the next unlock. A marked access never counts as saved, neither in `savedPINs` nor at the end of a refresh, also after a restart, so a failed refresh forgets an unsaved answer of that access and no automatic refresh sends it.
- The setup of an extension access runs as a refresh of the access that the setup makes. When the login joins an access that the app has already, `adoptLogin(of:into:)` notes that access. The broker writes nothing then: only when the refresh of the setup finished, after the accounts and their rows are stored, does that access take the login data, saved when the user asked to save it or when that access has saved login data already, as `remember(_:for:save:)` does for a PIN. A setup that fails or is canceled after the join saves nothing. When the setup stores no account, the broker forgets the login data of the setup.
- `Secret` prints "•••", and no log line of the broker, the connector, or the debug harness carries a value of the login data.
- The account settings of an extension access name the secret as the login dialog does: the label "Password" and the button "Remove saved Password", with the question "Remove the saved login data of “Demo TAN”?". A FinTS access keeps "Remove saved PIN". The words come from the manifest of the installed extension, else "Password".

### The rules of the bank

`PINRules` holds digits only, the minimum length, and the maximum length, and `check(_:secretName:)` names the first broken rule. `PINRequest.rules` brings them to the sheet, which checks the PIN at "OK" and sends nothing while a rule is broken. The login step of "Add Account" has no PIN sheet: `SetupSession` checks the PIN of the step against the rules of the request, and a broken rule ends the login with its text before the PIN is sent. The FinTS helper reads the minimum and maximum length from the bank parameters (`getPinLengthMin` and `getPinLengthMax` of hbci4java).

### The PIN field

The field is a `SecureField` with no content type, which macOS shows as a secure text field. It hides the characters and does not allow "Copy".

### The PIN of a new dialog

When the user changes the TAN method, the FinTS helper starts a new dialog with the bank (see the [design of add-tan-handling](../add-tan-handling/design.md)). The helper uses the PIN of the run again for it, unless the bank rejected that PIN.

## Deviations from the spec

- FinTS bank parameters state no rule for digits only, so a FinTS PIN is checked only for its length. The rule works for a source that states it.
- "Remove saved PIN" also forgets the PIN in memory, so the next refresh asks at once, not only after a restart.
- A refresh that fails after a successful login does not save the PIN. The next successful refresh with the option on saves it.
- The secret is called "PIN" for every FinTS access, because hbci4java gives no other name. An extension names its secret with the label of its login field in the manifest, else "Password", and the login dialog of an extension shows that label.
- The login data of an extension is saved as a whole, also its username, because the script needs every field to log in. "Remove saved PIN" removes it, so the button keeps one name for every access kind.

## Risks / Trade-offs

- A backup of the database, also the copy `Moneten-Backup.sqlite` before an upgrade of the layout, is a copy of its moment. It keeps the saved PINs and login data of that moment, also those that the user removed later or that a service rejected later, protected by the database password of that moment.

- A saved PIN is as safe as the database password. A database without a password keeps its random key in the Keychain, so there the PIN is as safe as the Keychain of the user.
- Before an upgrade of the layout the app copies the database to `Moneten-Backup.sqlite`, encrypted with the same key. That copy keeps the saved PINs of that moment until the next upgrade replaces it, also a PIN that the user removes or the bank rejects later. Restoring the copy brings such a PIN back, and a PIN that the bank rejected then costs one more wrong attempt before it is deleted again.
