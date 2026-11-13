# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior. The issue in brackets builds it.

## 1. Requirements

- [x] 1.1 Refresh all accounts. Verified by BankAccessTests "Refresh All Accounts fetches every account with an access that is not closed..." and the debug app check of "Refresh All Accounts". The interval "never" comes with #40 (#85).
- [x] 1.2 Refresh one account or one group. Verified by BankAccessTests "Refresh Account fetches only the selected account..." and "Refresh Accounts on a group fetches the accounts of the group and of its subgroups", and the debug app check of "Refresh All Accounts" and "Refresh Account" (#85).
- [ ] 1.3 Cancel a refresh. Built: "Cancel Refresh" stops every access, and a canceled access keeps its last state without an error, verified by SyncCoordinatorTests "A failed access marks all its requested accounts, and a canceled one marks none..." and the debug app check. Open: with FinTS no account of a canceled access is complete yet, see task 1.25 of add-fints-banking (#85).
- [ ] 1.4 Automatic refresh. Build it and verify it with a test or in the app (#40).
- [ ] 1.5 Refresh interval for each account. Build it and verify it with a test or in the app (#40).
- [ ] 1.6 Accounts that are refreshed only by hand. Build it and verify it with a test or in the app (#40).
- [ ] 1.7 Accounts that are never refreshed with the others. Build it and verify it with a test or in the app (#40).
- [ ] 1.8 Refresh after launch and after wake. Build it and verify it with a test or in the app (#40).
- [ ] 1.9 No automatic refresh while the app is locked. Build it and verify it with a test or in the app (#40).
- [ ] 1.10 No automatic refresh during Power Nap. Build it and verify it with a test or in the app (#40).
- [ ] 1.11 An automatic refresh never asks the user. Build it and verify it with a test or in the app (#6).
- [x] 1.12 One session for the accounts of one login. Verified by BankAccessTests "Refresh All Accounts fetches ... one request per access" and FinTSConnectorTests "Asks for the full history first..." (#85).
- [x] 1.13 A failure affects only its own access. Verified by BankAccessTests "The end of a refresh gives each requested account its outcome..." and SyncCoordinatorTests "The end of a refresh brings the new state of the access and the outcome of each account" (#85).
- [x] 1.14 Show progress. Verified by SyncCoordinatorTests, which check `refreshingAccounts` during and after a refresh, and the debug app check of the indicator on the rows and the text in the status line (#85).
- [x] 1.15 Show the time of the last refresh. Verified by BankAccessTests "A refresh records its time and clears the error..." and the debug app check, which shows "Last updated: Today, 17:43" (#85).
- [x] 1.16 Show an error on the account. Verified by BankAccessTests "The end of a refresh gives each requested account its outcome...", AccessStoreTests "A refresh stores the new state and the status of its accounts...", and the debug app check of the error text in the sidebar and the popover with "Zugang vorübergehend gesperrt" (9010) and its date and time (#85). The view of an account whose first refresh failed shows the error text in place of "Not refreshed yet", verified in the debug app with the "Fondsdepot" of the fake helper (#110).
- [x] 1.17 An error ends with the next success. Verified by BankAccessTests "A refresh records its time and clears the error..." and the debug app check, in which the third refresh shows the balance of "Tagesgeld" again. Saving the account settings keeps the status of a refresh that ended while they were open, verified by BankAccessTests "Saving the account settings keeps the balance and the status of a refresh..." (#85).
- [x] 1.18 Keep the history for good. Build it and verify it with a test or in the app (#7).
- [x] 1.19 Do not store a transaction twice. Build it and verify it with a test or in the app (#7).
- [x] 1.20 Update a transaction that the source changed. Build it and verify it with a test or in the app (#7).
- [x] 1.21 Keep real identical transactions. Build it and verify it with a test or in the app (#7).
- [x] 1.22 Replace a pending transaction by its booked version. Build it and verify it with a test or in the app (#7).
- [x] 1.23 Do not guess between several pending transactions. Build it and verify it with a test or in the app (#7).
- [x] 1.24 Remove a pending transaction that the bank dropped. Build it and verify it with a test or in the app (#7).
- [x] 1.25 Deleted transactions stay deleted. Build it and verify it with a test or in the app (#7).
- [x] 1.26 Mark new transactions. Build it and verify it with a test or in the app (#7).
- [x] 1.27 Update the balance at every refresh. Build it and verify it with a test or in the app (#7).
- [ ] 1.28 Refresh after a payment. Build it and verify it with a test or in the app (#28, v0.2).
- [ ] 1.29 Behavior without an Internet connection. Build it and verify it with a test or in the app (#40).

## 2. Sync model (issue #6)

The design explains each step. The requirements 1.1 to 1.17 stayed open until an app command started a refresh of real accounts, which issue #85 builds. Tests prove 1.18 to 1.27 through `reconcile`, `Store.merge`, and the coordinator with `ScriptedConnector`, and task 3.1 checks them again with real banks.

- [x] 2.1 `Domain`: `Access`, `BankConnector`, `RefreshRequest`, `ConnectorReport`, `AccountOutcome`, `RefreshResult`, and `AccessState`.
- [x] 2.2 `Domain`: `SyncSession`, `UserRequest`, `SecondFactorRequest`, `Challenge`, `UserAnswer`, and `Secret`, whose description never shows the value.
- [x] 2.3 `Domain`: `SyncState`, `SyncEvent`, and the pure transition function, with a test for every allowed and every refused transition.
- [x] 2.4 `Domain`: `SyncFailure` and `BankMessage`, with the message the app shows for each case.
- [x] 2.5 Test support: `ScriptedConnector`, which plays requests, answers, progress, results, and failures.
- [x] 2.6 `Sync`: `SessionBroker`, with one queue for all dialogs, unattended sessions for the automatic refresh, and the PIN from memory. The saved PINs of add-login-credentials join it when the database opens (#86).
- [x] 2.7 `Sync`: `SyncCoordinator`, with one `SyncState` per access, up to three accesses at a time, and "Cancel Refresh".
- [x] 2.8 `App`: the PIN sheet and the dialog "Two-Factor Authentication" for every `Challenge` case, with previews driven by `ScriptedConnector`.
- [x] 2.9 Tests: every state, cancellation in every state, an automatic refresh that meets a request, two accesses that ask at the same time, and an approval dialog that closes when the connector cancels its request.
- [x] 2.10 `Sync` and `App`: after the bank rejects a PIN, a manual refresh shows the PIN sheet again with the message of the bank and the warning, and an automatic refresh fails with `pinRejected`. The broker never answers with that PIN again.

## 3. Integration

- [ ] 3.1 Check every scenario of the spec in a release build with the FinTS connector of issue #13, and record the result in the pull request.

## 4. Parts that come later

Tasks 4.1 to 4.6 are requirements of add-tan-handling and add-login-credentials that the dialogs of task 2.8 do not have yet. Task 4.7 keeps the merge of 1.19 correct once fetched rows can be edited.

- [x] 4.1 Change the TAN method inside the open dialog, and show the progress text while a challenge is requested. Verified by TANDialogTests, FinTSConnectorTests "Offers the other TAN methods in the dialog of a challenge...", and the FinTSHelper self-test, see tasks 1.6, 1.8, and 1.17 of add-tan-handling (#86).
- [x] 4.2 Enlarge a photoTAN or QR image. Verified by the debug app check of pull request #86, see task 1.15 of add-tan-handling (#86).
- [x] 4.3 Make the flicker code smaller and larger, remember the size, and warn about seizures before the first enlargement. Verified by FlickerCodeSizeTests and the debug app check, see task 1.19 of add-tan-handling (#86).
- [x] 4.4 Say that the bank responded with an invalid challenge when the flicker data is not valid. Verified by FinTSConnectorTests "A flicker code that does not read fails the access with an invalid challenge and opens no dialog" and FinTSHelper self-test "challenge data without a flicker code" (#86).
- [x] 4.5 Check a PIN against the rules of the bank, and offer the option to save it with the storage of saved PINs. Verified by PINRulesTests, SavedPINTests of Sync and Storage, and the debug app check, see tasks 1.3 to 1.8 of add-login-credentials (#86).
- [ ] 4.6 Check that the PIN field is not offered to the password manager of macOS on a real Mac (#13). Checked in part by pull request #86: in a debug build the field is an `NSSecureTextField` with the content type nil, and after two seconds of focus the app has no AutoFill window. macOS did not let the app become active during that check, so a click into the field with the app in front is still open.
- [ ] 4.7 Before transaction-list "Edit a transaction" allows editing the bank fields of a fetched or migrated row, add a migration that copies the fields of the fingerprint of every row into columns of their own, and let `reconcile` and `DeletedTransaction` read those. Until then no such edit is possible, so the copy is exact (#7).

## Workflow follow-up

- Archive the change with `openspec archive add-account-refresh` when every task is checked.
