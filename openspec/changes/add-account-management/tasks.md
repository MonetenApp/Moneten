# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 Account types. Verified by account settings.
- [x] 1.2 Derive a missing account type. Verified by ResultMappingTests "typeFromTheNumberAndTheName", 25 cases of number and name in the order of the requirement, and "givenTypeWins". In a debug build, an extension that lists "Wallet" (K-2231), "Visa Gold" (4111 xxxx xxxx 1111), and "Tagesgeld Plus" without a type adds them as "Other", "Credit card", and "Savings account". A FinTS account without a type keeps "Other".
- [x] 1.3 Change the account type. Verified by BankAccessTests "accountTypeChoices": the menu "Account type" offers every type but "Portfolio", and a portfolio has none. "settingsAfterPortfolioRefresh" and "settingsNeverChoosePortfolio": saving the settings neither leaves nor chooses "Portfolio". In the app, the settings of a portfolio show "Portfolio" as text.
- [x] 1.4 Account settings window. Verified by sheet with ⌘I.
- [x] 1.5 Account name. Verified by account settings.
- [x] 1.6 Bank details of an account. Verified by IBAN, BIC, account number, and owner in the settings.
- [x] 1.7 Account currency. Verified by shown in the settings.
- [x] 1.8 Account owner. Verified by shown in the settings.
- [x] 1.9 Balance comes from the bank. Verified by LedgerTests "balanceSource": an account of a bank access and a portfolio show the reported balance, a migrated and an offline account follow their transactions.
- [x] 1.10 Several balances and bonus points. Verified by ResultMappingTests (pairs add up, a missing account currency is 0, a zero in another currency is left out, the whole part of `bonusPoints`), SeveralBalancesTests (a refresh stores and replaces them, a portfolio has neither, the sidebar, the header, and the group sum show every balance), SchemaTests "v26", and AllDataTests. In a debug build, an extension wallet with 120,00 € and 35,00 US$ shows both in the sidebar row, the header, and the sum of its group, and a card shows "Bonus points: 12.400" in the header. A second refresh with only 80,00 € and no points shows 80,00 € alone and no bonus line.
- [x] 1.11 Initial balance. The field in the account settings is built and editable. At setup, `Account.deriveInitialBalance` subtracts `Account.bookedSum(of:through:)` from the bank balance, which leaves out pending rows, rows after the day of the bank balance, and booked rows in another currency than the account. Verified by LedgerTests "The initial balance that meets the bank balance subtracts the booked rows up to the day of that balance", whose row in USD stays out, and by OpeningBalanceTests (task 3.3 of the change `add-charts`).
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
