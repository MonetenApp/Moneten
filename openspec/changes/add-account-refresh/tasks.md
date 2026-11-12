# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior. The issue in brackets builds it.

## 1. Requirements

- [ ] 1.1 Refresh all accounts. Build it and verify it with a test or in the app (#6).
- [ ] 1.2 Refresh one account or one group. Build it and verify it with a test or in the app (#6).
- [ ] 1.3 Cancel a refresh. Build it and verify it with a test or in the app (#6).
- [ ] 1.4 Automatic refresh. Build it and verify it with a test or in the app (#40).
- [ ] 1.5 Refresh interval for each account. Build it and verify it with a test or in the app (#40).
- [ ] 1.6 Accounts that are refreshed only by hand. Build it and verify it with a test or in the app (#40).
- [ ] 1.7 Accounts that are never refreshed with the others. Build it and verify it with a test or in the app (#40).
- [ ] 1.8 Refresh after launch and after wake. Build it and verify it with a test or in the app (#40).
- [ ] 1.9 No automatic refresh while the app is locked. Build it and verify it with a test or in the app (#40).
- [ ] 1.10 No automatic refresh during Power Nap. Build it and verify it with a test or in the app (#40).
- [ ] 1.11 An automatic refresh never asks the user. Build it and verify it with a test or in the app (#6).
- [ ] 1.12 One session for the accounts of one login. Build it and verify it with a test or in the app (#6).
- [ ] 1.13 A failure affects only its own access. Build it and verify it with a test or in the app (#6).
- [ ] 1.14 Show progress. Build it and verify it with a test or in the app (#6).
- [ ] 1.15 Show the time of the last refresh. Build it and verify it with a test or in the app (#6).
- [ ] 1.16 Show an error on the account. Build it and verify it with a test or in the app (#6).
- [ ] 1.17 An error ends with the next success. Build it and verify it with a test or in the app (#6).
- [ ] 1.18 Keep the history for good. Build it and verify it with a test or in the app (#7).
- [ ] 1.19 Do not store a transaction twice. Build it and verify it with a test or in the app (#7).
- [ ] 1.20 Update a transaction that the source changed. Build it and verify it with a test or in the app (#7).
- [ ] 1.21 Keep real identical transactions. Build it and verify it with a test or in the app (#7).
- [ ] 1.22 Replace a pending transaction by its booked version. Build it and verify it with a test or in the app (#7).
- [ ] 1.23 Do not guess between several pending transactions. Build it and verify it with a test or in the app (#7).
- [ ] 1.24 Remove a pending transaction that the bank dropped. Build it and verify it with a test or in the app (#7).
- [ ] 1.25 Deleted transactions stay deleted. Build it and verify it with a test or in the app (#7).
- [ ] 1.26 Mark new transactions. Build it and verify it with a test or in the app (#7).
- [ ] 1.27 Update the balance at every refresh. Build it and verify it with a test or in the app (#7).
- [ ] 1.28 Refresh after a payment. Build it and verify it with a test or in the app (#28, v0.2).
- [ ] 1.29 Behavior without an Internet connection. Build it and verify it with a test or in the app (#40).

## 2. Sync model (issue #6)

The design explains each step. The requirements of section 1 stay open until an app command starts a refresh of real accounts, which needs the accesses of issue #13.

- [x] 2.1 `Domain`: `Access`, `BankConnector`, `RefreshRequest`, `ConnectorReport`, `AccountOutcome`, `RefreshResult`, and `AccessState`.
- [x] 2.2 `Domain`: `SyncSession`, `UserRequest`, `SecondFactorRequest`, `Challenge`, `UserAnswer`, and `Secret`, whose description never shows the value.
- [x] 2.3 `Domain`: `SyncState`, `SyncEvent`, and the pure transition function, with a test for every allowed and every refused transition.
- [x] 2.4 `Domain`: `SyncFailure` and `BankMessage`, with the message the app shows for each case.
- [x] 2.5 Test support: `ScriptedConnector`, which plays requests, answers, progress, results, and failures.
- [x] 2.6 `Sync`: `SessionBroker`, with one queue for all dialogs, unattended sessions for the automatic refresh, and the PIN from memory. The saved PIN joins it with the storage of add-login-credentials.
- [x] 2.7 `Sync`: `SyncCoordinator`, with one `SyncState` per access, up to three accesses at a time, and "Cancel Refresh".
- [x] 2.8 `App`: the PIN sheet and the dialog "Two-Factor Authentication" for every `Challenge` case, with previews driven by `ScriptedConnector`.
- [x] 2.9 Tests: every state, cancellation in every state, an automatic refresh that meets a request, two accesses that ask at the same time, and an approval dialog that closes when the connector cancels its request.
- [x] 2.10 `Sync` and `App`: after the bank rejects a PIN, a manual refresh shows the PIN sheet again with the message of the bank and the warning, and an automatic refresh fails with `pinRejected`. The broker never answers with that PIN again.

## 3. Integration

- [ ] 3.1 Check every scenario of the spec in a release build with the FinTS connector of issue #13, and record the result in the pull request.

## 4. Parts of the dialogs that come later

These requirements of add-tan-handling and add-login-credentials are not in the dialogs of task 2.8 yet.

- [ ] 4.1 Change the TAN method inside the open dialog, and show the progress text while a challenge is requested (#13).
- [ ] 4.2 Enlarge a photoTAN or QR image (#13).
- [ ] 4.3 Make the flicker code smaller and larger, remember the size, and warn about seizures before the first enlargement (#13).
- [ ] 4.4 Say that the bank responded with an invalid challenge when the flicker data is not valid (#13).
- [ ] 4.5 Check a PIN against the rules of the bank, and offer the option to save it with the storage of saved PINs (#13).
- [ ] 4.6 Check that the PIN field is not offered to the password manager of macOS on a real Mac (#13).

## Workflow follow-up

- Archive the change with `openspec archive add-account-refresh` when every task is checked.
