# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 Results while typing. Verified by the list filters on every change of the search field.
- [x] 1.2 The search covers all text of a transaction. Verified by LedgerTests "The search finds text inside words...".
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
- [x] 1.13 The period applies to every view. Verified by the period stays when the view changes.
- [x] 1.14 Status filter. Verified by LedgerTests "Status, amount, period, and category filters combine".
- [x] 1.15 Amount filter. Verified by LedgerTests "Status, amount, period, and category filters combine".
- [x] 1.16 Category filter in account views. Verified by LedgerTests "Status, amount, period, and category filters combine".
- [x] 1.17 Account filter in category views. Verified by the filter bar shows "Account" in category views.
- [x] 1.18 Search and filters combine. Verified by LedgerTests "Status, amount, period, and category filters combine".
- [x] 1.19 Hint about active filters. Verified by the debug harness snapshot in the first build.
- [ ] 1.20 Saved searches. Build it and verify it with a test or in the app.
- [x] 1.21 The search is fast with a large history. Verified by PerformanceTests: 10 ms for a search over 50,000 transactions in a release build.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-transaction-search-and-filters` when every task is checked.
