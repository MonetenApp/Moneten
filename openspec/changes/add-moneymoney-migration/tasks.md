# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 Migration command. Verified by File menu and empty state, see the debug harness snapshot in the first build.
- [ ] 1.2 Preconditions are checked first. Built in part: messages for a missing app, a locked database, and a refused permission, with "Check again". Finish it and verify it with a test or in the app.
- [x] 1.3 The source is only read. Verified by only the three export commands run.
- [x] 1.4 Summary before the import. Verified by the sheet shows the counts before "Import".
- [x] 1.5 Account groups and accounts. Verified by MoneyMoneyMigrationTests "Group tree with order and balances", and by the sidebar after a real migration: every visible account balance equals MoneyMoney. That holds for an account without pending transactions; one with pending transactions shows them on top, as task 3.4 of the change `add-charts` tests.
- [x] 1.6 Categories. Verified by MoneyMoneyMigrationTests "Categories keep their tree and the default maps to Uncategorized".
- [ ] 1.7 Rules. Built: verified by MoneyMoneyMigrationTests "Rules come over with the categories, and the report mentions rules only when the export has none", and by all 12 rules of a real export parsing. Check it when task 2.2 of `add-categorization-rules` makes the scenario "Lower case operators keep their meaning" pass.
- [x] 1.8 Transactions. Verified by MoneyMoneyMigrationTests "Transaction fields and dates".
- [x] 1.9 Category, comment, and checkmark of each transaction. Verified by MoneyMoneyMigrationTests "Categories keep their tree...".
- [x] 1.10 Migration is all or nothing. Verified by one database transaction stores the whole plan.
- [ ] 1.11 Progress. Built in part: one line per export step, no counts. Finish it and verify it with a test or in the app.
- [x] 1.12 Repeated runs add only what is new. Verified by MoneyMoneyMigrationTests "A second run adds only what is new", "A later run updates the bank balance and books what was pending", "Accounts with the same IBAN stay apart on a later run", "A second run after a refresh stored some of the same transactions adds only the new ones", "A second run adds nothing after an extension took over the ID of a migrated transaction", and "A transaction the user deleted after the first run stays deleted".
- [x] 1.13 Migration into a database with accounts. Verified by MoneyMoneyMigrationTests "An account is matched by IBAN" and "A second run after a refresh stored some of the same transactions adds only the new ones".
- [ ] 1.14 Connect a migrated account to its bank, and ask which migrated account to connect. Build it and verify it with a test or in the app.
- [ ] 1.15 Portfolio accounts. Built in part: taken over with their balance, no positions. The balance becomes the first record of the portfolio history, and a database migrated earlier gets that record when it opens, see the debug harness check of a database made by the build before the history. Finish it and verify it with a test or in the app.
- [ ] 1.16 Report. Built in part: counts and notes. The balance it compares leaves out pending transactions; the scenario "Pending transactions are no mismatch" needs a test once pending transactions count in balances (task 3.2 of `add-charts`). The notes on what is not migrated, on budgets, and on icons come in 2.3 and 2.4. Finish it and verify it with a test or in the app.
- [x] 1.17 The report contains no secrets. Verified by the report holds counts and notes only.
- [ ] 1.18 Category colors. Built: the color of the icon of each category, verified by MoneyMoneyMigrationTests "The color of a category comes from its icon" and "Categories take the color of MoneyMoney". Verify it with the real export, which was locked in MoneyMoney when this was built.
- [ ] 1.19 Migrated rules that the app cannot read. Not built: the plan takes every rule over without parsing it, and the report names no unreadable rule. Build it in 2.1 and 2.2. The category settings part is 2.5.
- [ ] 1.20 Migrated rules that search account numbers. Not built. Build it in 2.6 and 2.7.
- [ ] 1.21 Migrated rules with operators in lower case. Not built. Build it in 2.8 and 2.9.
- [ ] 1.22 Migrated rules with the words true and false. Not built. Build it in 2.10 and 2.11.

## 2. Changes to the first build

- [ ] 2.1 Write MoneyMoneyMigrationTests tests for the scenarios "Missing parenthesis" and "One part of a rule cannot be read": the rule is stored unchanged, and the plan has a note with the category, the position, and the reason.
- [ ] 2.2 Parse each rule in `MoneyMoneyMigration.plan` in `Sources/Import/MoneyMoneyMigration.swift` and add the note until the tests of 2.1 pass.
- [ ] 2.3 Write MoneyMoneyMigrationTests tests for the scenarios "Not migrated", "Budgets in a version without budgets", and "Icons", with a synthetic category export that carries two budgets. The budget note says that the app did not take the budgets over and promises no later step.
- [ ] 2.4 Add the notes on login data, templates, standing orders, statements, budgets, and icons to the plan until the tests of 2.3 pass.
- [ ] 2.5 The category settings check the stored rule when they open, show the message of a rule that cannot be read, and keep OK disabled until the rule can be read. Built by pull request #141 in `App/Sources/Views/CategorySettingsSheet.swift`. Check this task when the settings of "Salary" in the scenario "Missing parenthesis" show the message.
- [ ] 2.6 Write MoneyMoneyMigrationTests tests for the scenarios "Rule with an IBAN only", "Rule with a word and an IBAN", "Customer number", "Account number of a counterparty", and "Calendar week": the first two rules have a note with the category and `remote_account:DE02120300000000202051`, the fourth has a note with `remote_account:202051`, the third and the fifth have none, and all rules are stored unchanged.
- [ ] 2.7 Add the note for rules with an IBAN or an account number as a term without a field to `MoneyMoneyMigration.plan` in `Sources/Import/MoneyMoneyMigration.swift` until the tests of 2.6 pass.
- [ ] 2.8 Write MoneyMoneyMigrationTests tests for the scenarios "Rule with a lower case or" and "Operators in capitals or in quotation marks": the first rule has a note with the category and the word `or`, the other two have none, and all rules are stored unchanged.
- [ ] 2.9 Add the note for rules with and, or, or not in lower case to `MoneyMoneyMigration.plan` until the tests of 2.8 pass.
- [ ] 2.10 Write MoneyMoneyMigrationTests tests for the scenarios "Rule with the word true" and "Quoted true": the first rule has a note with the category and the word `true`, the second has none, and both rules are stored unchanged. Add a rule `FALSE` and expect a note with the word `FALSE`.
- [ ] 2.11 Add the note for rules with true or false to `MoneyMoneyMigration.plan` until the tests of 2.10 pass.

## 3. Integration

- [ ] 3.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-moneymoney-migration` when every task is checked.
