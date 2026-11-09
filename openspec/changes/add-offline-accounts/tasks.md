# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 Create an offline account. Verified by "Add Account..." sheet; the debug harness creates two.
- [x] 1.2 An offline account has no bank functions. Verified by no refresh in this build.
- [x] 1.3 Add a transaction by hand. Verified by transaction sheet.
- [ ] 1.4 Manual transactions are validated. Built in part: the amount must be a number. Finish it and verify it with a test or in the app.
- [ ] 1.5 Suggestions while typing. Build it and verify it with a test or in the app.
- [ ] 1.6 A selected transaction is the template. Build it and verify it with a test or in the app.
- [x] 1.7 Edit and delete manual transactions. Verified by transaction sheet and delete command.
- [x] 1.8 The balance follows the transactions. Verified by LedgerTests "Balances leave out pending transactions".
- [ ] 1.9 Hint for the first transaction. Built in part: the empty list offers "Add Transaction...". Finish it and verify it with a test or in the app.
- [ ] 1.10 Create an offsetting entry. Build it and verify it with a test or in the app.
- [x] 1.11 Manual transactions behave like fetched ones. Verified by rules run on save.
- [x] 1.12 An offline account can be closed. Verified by "The account has been closed" in the settings.
- [ ] 1.13 Manual transactions in an account with bank access. Build it and verify it with a test or in the app.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-offline-accounts` when every task is checked.
