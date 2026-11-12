# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior. "Debug app check" is the run of a debug build with a password-protected test database against `scripts/fake-fints-helper.sh` and the requests of `SyncDemo`, which pull request #86 records with screenshots.

## 1. Requirements

- [ ] 1.1 PIN sheet names the access. Built for FinTS: the sheet shows "Giro", "Musterbank", and "erika77", verified by SyncCoordinatorTests "A manual refresh asks for the PIN, fetches, and finishes" and the debug app check. The word of an extension for its secret comes with E6.
- [ ] 1.2 Hidden entry. Built: the field is a secure text field without a content type, and it shows five dots for "12345" in the debug app check. The debug app check found an `NSSecureTextField` with the content type nil and no AutoFill window of macOS after two seconds of focus. Open: the app could not become the active app in that check, so a click into the field on a real Mac with the app in front must still confirm that the password manager offers nothing (task 4.6 of add-account-refresh).
- [x] 1.3 Check a PIN against the rules of the bank. Verified by PINRulesTests "Letters in a numeric PIN" and "A PIN that is too long or too short names the limit...", FinTSConnectorTests "Sends the PIN rules of the bank with the PIN request", SetupSessionTests "A PIN that breaks a rule of the bank ends the login with the rule, and the PIN never reaches the bank", FinTSHelper self-test "PIN request with the rules of the bank", and the debug app check, which shows "The PIN must be numeric." for "12a45" and sends nothing.
- [x] 1.4 Save a PIN only on request. Verified by SavedPINTests (Sync) "A PIN with the option off stays in memory and is never saved" and "A PIN is saved only when the user turns saving on...", and the debug app check: "Save PIN" is off when the sheet appears, and on in the login step of "Add Account" only after the user turns it on.
- [x] 1.5 A PIN is saved only after the bank accepted it. Verified by SavedPINTests (Sync) "A PIN is saved only when the user turns saving on, and only after the refresh with it finished" and "A PIN with the option on is not saved when the bank rejects it...", and "Adding the login again replaces its saved PIN with the PIN the bank accepted, also with saving off".
- [x] 1.6 Saved PINs live in the encrypted database. Verified by SavedPINTests (Storage) "No byte of the database file or of its backup shows the PIN, and the backup opens on another Mac with the database password" and "A saved PIN comes back after the database opens again...", and "v9 adds the table of saved PINs to a v7 database with an access...", and by the debug app check, after which `security dump-keychain` shows no entry of the test folder. No code writes a PIN to the Keychain or the settings.
- [x] 1.7 An unsaved PIN stays in memory until the app locks or quits. Verified by SyncCoordinatorTests "A PIN in memory is used again, until the app locks".
- [x] 1.8 Remove a saved PIN. Verified by SavedPINTests (Sync) "Remove saved PIN deletes the PIN of the access, and the next refresh asks for it" and the debug app check of the account settings, which show "Remove saved PIN" for an account whose access has a saved PIN.
- [x] 1.9 TANs are never saved. Verified by FinTSConnectorTests, which show the TAN only in the pipe of the helper, SyncModelTests "A secret never prints its value", and the debug app check, whose log holds no TAN. The app has no export yet.
- [x] 1.10 Secrets stay inside the encrypted database. Verified by SavedPINTests (Sync) "A rejected PIN never reaches the error of the account", FinTSHelper self-test "PIN of the request masked in diagnostics", and SavedPINTests (Storage) for the backup. The app has no export of data yet; the backup is the encrypted database.
- [x] 1.11 No automatic retry after a wrong PIN. Verified by SyncCoordinatorTests "A PIN in memory that the bank rejects is never sent again" and "After a typing error the PIN sheet opens again...", and SavedPINTests (Sync) "A saved PIN that the bank rejects is deleted and never sent again...", "A blocked access loses its saved PIN and the PIN in memory without a new PIN sheet...", and "A PIN in memory that was not saved is forgotten when the access is blocked".
- [x] 1.12 Cancel the PIN sheet. Verified by SyncCoordinatorTests "Canceling the dialog stops only its access".
- [x] 1.13 One PIN sheet at a time. Verified by SyncCoordinatorTests "Two accesses that ask at the same time get one dialog after the other" and "A second click answers nothing, not the next dialog".
- [ ] 1.14 Automatic refresh skips an access without a PIN. Built in the broker: an automatic refresh never opens a sheet, verified by SyncCoordinatorTests "An automatic refresh never asks the user", and uses a saved PIN after a restart, verified by SavedPINTests (Sync) "A saved PIN answers the refreshes after a restart without a sheet, also the automatic one". The automatic refresh and its mark in the sidebar come with issue #40.
- [ ] 1.15 One set of rules for all access kinds. Built in `SessionBroker` for every connector. Extensions and the subscription come later.

## 2. Build

- [x] 2.1 `Storage`: the table `savedPIN` (migration `v9`) and `Store.savedPINs()`, `savePIN(_:for:)`, and `removeSavedPIN(of:)`.
- [x] 2.2 `Sync`: `SessionBroker` saves, loads, and deletes PINs through `SavedPINStore`.
- [x] 2.3 `App`: "Save PIN" in the PIN sheet and in the login step of "Add Account", the check of the rules, and "Remove saved PIN" in the account settings.
- [x] 2.4 `FinTS`: the helper sends the PIN rules of the bank parameters.

## Workflow follow-up

- Archive the change with `openspec archive add-login-credentials` when every task is checked.
