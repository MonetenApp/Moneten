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
- [x] 1.12 Mark an account as closed. Verified by "The account has been closed". The scenario "Refresh during the close" is verified by SyncCoordinatorTests "closedLeavesQueue", "closedLeavesAfterRun", and "closedDuringRun", AutoRefreshTests "closedStaysOutOfRetry", whose run again after a failed automatic refresh asked the bank for the closed account before the retry took only the accounts still requested, ClosedAccountTests "lateRefresh" and "lateStatus", and the storage test "lateDelivery", whose three late deliveries (a vanished pending row, a new booking, a changed amount) changed the closed account before `reconcile` ignored a refresh into it.
- [x] 1.13 Clearing entry for a closed account. `Ledger.closing(_:today:now:)` clears the computed balance at the end of the day, pending rows included, in the account currency, and gives a portfolio and a zero balance no entry. Verified by ClosedAccountTests (12,34 €, zero, a negative balance, an initial balance alone, a bank account whose computed 480,00 € differs from its bank balance, a row after that day, a pending row, a row in US$, a portfolio, the cleared refresh error, the limit, and an initial balance typed in the same OK), by SchemaTests "v28", and by ClearingEntryExportTests. In a debug build, closing the seeded "Tagesgeld" adds "Clearing entry" of -16.500,00 € dated today, the header shows 0,00 €, and the bar chart ends at 0 on that day, in light and dark.
- [x] 1.14 Reopen a closed account. `Ledger.reopening(_:)` removes the entry while it has the values that the app gave it, no comment, no category chosen by hand, and no parts. Verified by ClosedAccountTests (an unchanged entry, a checked one, eight kinds of change, a deleted entry, a bank account that shows 500,00 € and 35,00 US$ again with its initial balance unchanged, a second close after a kept entry, a row of another account with the values of the entry, an entry that a file matched, and a kept entry of a bank account that moves the derived initial balance so the balance meets the bank again), by SchemaTests "v28", and by ClearingEntryExportTests "foreignMark", which drops a mark that names a row of another account. In a debug build, reopening "Tagesgeld" removes the entry and shows 16.500,00 € again, and an entry whose purpose the user changed stays.
- [x] 1.15 Create and rename account groups. Verified by "Add Account Group" and the group settings.
- [x] 1.16 Move accounts into and out of groups. Verified by drag onto a group or "Move to Group".
- [x] 1.17 Group view. Verified by the debug harness snapshot in the first build.
- [x] 1.18 Account group settings. Verified by name and "Display balance in sidebar".
- [x] 1.19 Collapsed groups keep their information. Verified by the group row shows the sum.
- [x] 1.20 Remove an account. Verified by confirmation names the removed transactions.
- [x] 1.21 Remove an account group. Verified by accounts move to the top level.
- [x] 1.22 Account color: a square in the color of the user, the bank, or the type, in the sidebar and the header; a color row in the account settings; the migration takes the color of the MoneyMoney icon. Verified by MoneyMoneyMigrationTests "Accounts take the color of their MoneyMoney icon", SchemaTests "v5", and sidebar snapshots of the debug harness.
- [x] 1.23 Derived initial balance beyond the limit (issue #324). `AmountOverflowTests` "A refresh whose balance gives an initial balance beyond the limit keeps the old one and is refused" and `InitialBalanceLimitTests` "The merge fails with the name of the account and writes nothing" failed while the refresh clamped the derived initial balance, and pass since `Store.merge` throws `InitialBalanceTooLarge`.
- [x] 1.24 Balance of a closed account. A closed account shows its computed balance, and a closed portfolio its value. Verified by ClosedAccountTests (the bank account shows 0,00 € alone, the sum of a group leaves the closed account out before and after its entry, and the bar chart ends at 0,00 €), and the scenario "File import into a closed account" by ClosedAccountTests "fileIntoClosedAccount". In a debug build, the closed wallet "Reisekasse" shows 0,00 € without US$, and "Private" sums only its open accounts.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-account-management` when every task is checked.
