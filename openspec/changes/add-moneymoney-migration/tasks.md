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
- [x] 1.16 Report. Gate round 1 adds literal tests "The report keeps each source when two accounts merge into one existing account" and "A USD source row does not change the report balance of a EUR account". Verified by MoneyMoneyMigrationTests "The report shows each account next to the source, and a pending transaction is no mismatch", "The report shows a difference when an account misses a transaction of the source", "The text of the report lists the accounts and the notes", "A transaction that a file added to a migrated account counts neither in the number nor in the balance of the report", "The report of a second run counts the rows of the source in an account of the first run", "The report of a second run shows a difference when the source deleted a migrated transaction", and the tests of 2.1 and 2.3, and by the debug app check with the harness command `migrationfixture` and the absolute path of `Fixtures/moneymoney`: the sheet lists Giro with 4 transactions and 1.234,56 € beside its pending row, Savings, and Depot, each as a match, and the notes. "Save Report..." asks first and then opens the save panel.
- [x] 1.17 The report contains no secrets. Verified by the report holds account names, counts, balances, and notes only, and by the debug app check of 1.16: "Save Report..." first says "The report contains account names and balances." and saves only after the user confirms.
- [ ] 1.18 Category colors. Built: the color of the icon of each category, verified by MoneyMoneyMigrationTests "The color of a category comes from its icon" and "Categories take the color of MoneyMoney". Verify it with the real export, which was locked in MoneyMoney when this was built.
- [x] 1.19 Migrated rules that the app cannot read. Verified by the tests of 2.1 and the debug app check of 2.5.
- [ ] 1.20 Migrated rules that search account numbers. Not built. Build it in 2.6 and 2.7.
- [ ] 1.21 Migrated rules with operators in lower case. Not built. Build it in 2.8 and 2.9.
- [ ] 1.22 Migrated rules with the words true and false. Not built. Build it in 2.10 and 2.11.

## 2. Changes to the first build

- [x] 2.1 Write MoneyMoneyMigrationTests tests for the scenarios "Missing parenthesis" and "One part of a rule cannot be read": the rule is stored unchanged, and the plan has a note with the category, the position, and the reason. Verified by MoneyMoneyMigrationTests "A rule with a missing parenthesis is stored unchanged and named in the report", "A rule with one part that cannot be read is named with the position of that part, and its category receives nothing", and "A rule that the app reads gives no note and fills its category".
- [x] 2.2 Parse each rule in `MoneyMoneyMigration.plan` in `Sources/Import/MoneyMoneyMigration.swift` and add the note until the tests of 2.1 pass. Verified by the tests of 2.1.
- [x] 2.3 Write MoneyMoneyMigrationTests tests for the scenarios "Not migrated", "Budgets in a version without budgets", and "Icons", with a synthetic category export that carries two budgets. The budget note says that the app did not take the budgets over and promises no later step. Verified by MoneyMoneyMigrationTests "The report names login data, templates, standing orders, and statements as not migrated", "The report counts the categories with a budget and says that the budgets were not taken over", and "The report says that the app takes the color of each icon and draws its own icons".
- [x] 2.4 Add the notes on login data, templates, standing orders, statements, budgets, and icons to the plan until the tests of 2.3 pass. Verified by the tests of 2.3. The key of a budget in the category export is an assumption, see the design.
- [x] 2.5 The category settings check the stored rule when they open, show the message of a rule that cannot be read, and keep OK disabled until the rule can be read. Built by pull request #141 in `App/Sources/Views/CategorySettingsSheet.swift`. Verified by the debug app check: with the stored rule `("Lohn" OR "Gehalt"`, the settings of "Salary" show "A closing parenthesis is missing at the end of the rule. (position 20)" and OK is disabled, see the light and dark snapshots in the pull request.
- [ ] 2.6 Write MoneyMoneyMigrationTests tests for the scenarios "Rule with an IBAN only", "Rule with a word and an IBAN", "Customer number", "Account number of a counterparty", and "Calendar week": the first two rules have a note with the category and `remote_account:DE02120300000000202051`, the fourth has a note with `remote_account:202051`, the third and the fifth have none, and all rules are stored unchanged.
- [ ] 2.7 Add the note for rules with an IBAN or an account number as a term without a field to `MoneyMoneyMigration.plan` in `Sources/Import/MoneyMoneyMigration.swift` until the tests of 2.6 pass.
- [ ] 2.8 Write MoneyMoneyMigrationTests tests for the scenarios "Rule with a lower case or" and "Operators in capitals or in quotation marks": the first rule has a note with the category and the word `or`, the other two have none, and all rules are stored unchanged.
- [ ] 2.9 Add the note for rules with and, or, or not in lower case to `MoneyMoneyMigration.plan` until the tests of 2.8 pass.
- [ ] 2.10 Write MoneyMoneyMigrationTests tests for the scenarios "Rule with the word true" and "Quoted true": the first rule has a note with the category and the word `true`, the second has none, and both rules are stored unchanged. Add a rule `FALSE` and expect a note with the word `FALSE`.
- [ ] 2.11 Add the note for rules with true or false to `MoneyMoneyMigration.plan` until the tests of 2.10 pass.

## 3. Integration

- [ ] 3.1 Check every scenario of the spec in a release build and record the result in the pull request.
  Before this task, the operator exports one category with a budget of 10,00 EUR from MoneyMoney and records the key names. A dictionary without `amount`, for example `["value": 0, "available": 120]`, still counts as a budget today; that changes only the note.

## Workflow follow-up

- Archive the change with `openspec archive add-moneymoney-migration` when every task is checked.
