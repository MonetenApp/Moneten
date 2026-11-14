# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 Results while typing. Verified by the list filters on every change of the search field.
- [ ] 1.2 The search covers all text of a transaction. `Ledger.searchText(of:account:)` in `Sources/Domain/Ledger.swift` lacks the category name and the IBAN and the account number of the own account. Write the test first in LedgerTests: a transaction in the category "Groceries" of an account with the IBAN DE02120300000000202051 and no counterparty IBAN is found by "groceries" and by "DE02120300000000202051", and after the user renames the category to "Food" it is found by "food" and not by "groceries". Then add the three fields, and build the search text again for the transactions of a category when the category is renamed, and for the transactions of an account when its IBAN or account number changes, as `upsert(_:)` already does for a renamed account.
- [x] 1.3 The search finds text inside words. Verified by LedgerTests "The search finds text inside words...".
- [x] 1.4 The search ignores case, umlauts, and Unicode form. Verified by LedgerTests "The search finds text inside words...".
- [x] 1.5 All search words must occur. Verified by LedgerTests "The search finds text inside words...".
- [ ] 1.6 The search accepts the rule language. Build it and verify it with a test or in the app.
- [x] 1.7 The search finds exact amounts. Verified by LedgerTests "The search finds exact amounts".
- [x] 1.8 Count and sum of the results. Verified by status line, see the debug harness snapshot in the first build.
- [x] 1.9 Clear the search. Verified by clear button of the search field.
- [x] 1.10 Search for the counterparty of a transaction. Verified by "Search for" in the context menu.
- [x] 1.11 Period filter. Verified by LedgerTests "Status, amount, period, and category filters combine".
- [x] 1.12 Custom period. Verified by "Custom..." opens two date fields.
- [ ] 1.13 The filter bar applies to every view. This task holds the code for the filter bar and the pin, also for tasks 1.22 to 1.24 and for task 1.16 of the change `add-main-window`. Write the test first in LedgerTests: take a `TransactionFilter` with the category filter "Groceries", the account filter "Credit card", the status "Unchecked", and the period "12 Months". After `resetHidden(in:)` with `LedgerScope.account` or `LedgerScope.accountGroup`, the account filter is `nil` and the other three stay. After `resetHidden(in: .category(_:))`, the category filter is `nil` and the other three stay. Then add `resetHidden(in:)` to `TransactionFilter` in `Sources/Domain/Ledger.swift`. In `AppModel` in `App/Sources/AppModel.swift`, call it from one `didSet` on `selection` when `selection` changes and is not `nil`, and from no other place. Every path that sets `selection` then resets the filter that the new view does not show: `select`, which the sidebar, `navigate(to:)`, Back, and Forward use; `open` at launch; `addOfflineAccount`; `addGroup`; `addCategory`; `runMigration`; and the new access in `App/Sources/Extensions/ExtensionAccess.swift`. `select` no longer resets a filter, with or without the pin. Turning the pin on writes the filter bar to `UserDefaults`, every change while the pin is on writes it again, and the launch restores it before `open` sets the first selection, so the `didSet` resets the filter that the first view does not show. A custom period comes back with its start date and end date. Turning the pin off calls `choose(period: .all)`, sets the other filters to "Show All", and clears the search text. The app target has no unit tests, so verify a path that does not use `select` in the app with the debug harness: add the title, the category filter, and the account filter to the `state` line, choose "Groceries" in the "Category" menu of "Girokonto" by hand (the harness has no command for it), send `newcategory Pets`, and check that `state` shows the title "Pets" and the category filter "Show All". Verify every scenario of the four requirements in the app, also after a restart.
- [x] 1.14 Status filter. Verified by LedgerTests "Status, amount, period, and category filters combine".
- [ ] 1.15 Amount filter. Write the test first in LedgerTests: with 150,00 €, -150,00 €, and 500,00 €, the range 100 to 500 shows 150,00 € and 500,00 €, and the range -500 to -100 shows -150,00 €. Then change the custom range in `Ledger.transactions(in:filter:)` in `Sources/Domain/Ledger.swift` to compare the signed amount with both ends included, and change the doc comment "Absolute amounts in minor units." to say that the ends carry a sign. In the "Custom..." popover in `App/Sources/Views/TransactionsView.swift`, rename the fields "Minimum" and "Maximum" to "min. amount" and "max. amount", do not apply a "min. amount" above the "max. amount", and mark "max. amount". Verify that in the app with -100 and -500.
- [x] 1.16 Category filter in account views. Verified by LedgerTests "Status, amount, period, and category filters combine".
- [x] 1.17 Account filter in category views. Verified by the filter bar shows "Account" in category views.
- [x] 1.18 Search and filters combine. Verified by LedgerTests "Status, amount, period, and category filters combine".
- [x] 1.19 Hint about active filters. Verified by the debug harness snapshot in the first build.
- [ ] 1.20 Saved searches. Build it and verify it with a test or in the app. The filter bar of a saved search shows the "Category" menu and the "Account" menu with the entries of the other views, so opening it resets no filter.
- [x] 1.21 The search is fast with a large history. Verified by PerformanceTests: 10 ms for a search over 50,000 transactions in a release build.
- [ ] 1.22 Turning the pin off resets the filters. Task 1.13 builds it.
- [ ] 1.23 Turning the pin on saves the filter bar. Task 1.13 builds it.
- [ ] 1.24 A view resets the filter it does not show. Task 1.13 builds it.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-transaction-search-and-filters` when every task is checked.
