# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 Account types. Verified by account settings.
- [ ] 1.2 Derive a missing account type. Build it and verify it with a test or in the app.
- [x] 1.3 Change the account type. Verified by account settings.
- [x] 1.4 Account settings window. Verified by sheet with ⌘I.
- [x] 1.5 Account name. Verified by account settings.
- [x] 1.6 Bank details of an account. Verified by IBAN, BIC, account number, and owner in the settings.
- [x] 1.7 Account currency. Verified by shown in the settings.
- [x] 1.8 Account owner. Verified by shown in the settings.
- [x] 1.9 Balance comes from the bank. Verified by migrated accounts show the balance of MoneyMoney.
- [ ] 1.10 Several balances and bonus points. Build it and verify it with a test or in the app.
- [ ] 1.11 Initial balance. The field in the account settings is built and editable. Open: at setup, the derived value must leave out booked rows in another currency than the account. Today `Account.deriveInitialBalance` in `Sources/Domain/Models.swift` leaves out pending rows and rows after the day of the bank balance only. Task 3.3 of the change `add-charts` builds the rule and its test with `Account.bookedSum(of:through:)`. Check this task when that task is checked.
- [x] 1.12 Mark an account as closed. Verified by "The account has been closed".
- [ ] 1.13 Clearing entry for a closed account. Build it and verify it with a test or in the app.
- [ ] 1.14 Reopen a closed account. Built in part: the switch can be turned off; no clearing entry exists yet. Finish it and verify it with a test or in the app.
- [x] 1.15 Create and rename account groups. Verified by "Add Account Group" and the group settings.
- [x] 1.16 Move accounts into and out of groups. Verified by drag onto a group or "Move to Group".
- [x] 1.17 Group view. Verified by the debug harness snapshot in the first build.
- [x] 1.18 Account group settings. Verified by name and "Display balance in sidebar".
- [x] 1.19 Collapsed groups keep their information. Verified by the group row shows the sum.
- [x] 1.20 Remove an account. Verified by confirmation names the removed transactions.
- [x] 1.21 Remove an account group. Verified by accounts move to the top level.
- [x] 1.22 Account color: a square in the color of the user, the bank, or the type, in the sidebar and the header; a color row in the account settings; the migration takes the color of the MoneyMoney icon. Verified by MoneyMoneyMigrationTests "Accounts take the color of their MoneyMoney icon", SchemaTests "v5", and sidebar snapshots of the debug harness.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-account-management` when every task is checked.
