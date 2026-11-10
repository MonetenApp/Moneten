# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 Migration command. Verified by File menu and empty state, see the debug harness snapshot in the first build.
- [ ] 1.2 Preconditions are checked first. Built in part: messages for a missing app, a locked database, and a refused permission, with "Check again". Finish it and verify it with a test or in the app.
- [x] 1.3 The source is only read. Verified by only the three export commands run.
- [x] 1.4 Summary before the import. Verified by the sheet shows the counts before "Import".
- [x] 1.5 Account groups and accounts. Verified by MoneyMoneyMigrationTests "Group tree with order and balances", and by the sidebar after a real migration: every visible account balance equals MoneyMoney.
- [x] 1.6 Categories. Verified by MoneyMoneyMigrationTests "Categories keep their tree and the default maps to Uncategorized".
- [x] 1.7 Rules. Verified by MoneyMoneyMigrationTests "Rules come over with the categories, and the report mentions rules only when the export has none", and by all 12 rules of a real export parsing.
- [x] 1.8 Transactions. Verified by MoneyMoneyMigrationTests "Transaction fields and dates".
- [x] 1.9 Category, comment, and checkmark of each transaction. Verified by MoneyMoneyMigrationTests "Categories keep their tree...".
- [x] 1.10 Migration is all or nothing. Verified by one database transaction stores the whole plan.
- [ ] 1.11 Progress. Built in part: one line per export step, no counts. Finish it and verify it with a test or in the app.
- [x] 1.12 Repeated runs add only what is new. Verified by MoneyMoneyMigrationTests "A second run adds only what is new".
- [x] 1.13 Migration into a database with accounts. Verified by MoneyMoneyMigrationTests "An account is matched by IBAN".
- [ ] 1.14 Connect a migrated account to its bank. Build it and verify it with a test or in the app.
- [ ] 1.15 Portfolio accounts. Built in part: taken over with their balance, no positions. Finish it and verify it with a test or in the app.
- [ ] 1.16 Report. Built in part: counts and notes. Finish it and verify it with a test or in the app.
- [x] 1.17 The report contains no secrets. Verified by the report holds counts and notes only.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-moneymoney-migration` when every task is checked.
