# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 Three view modes. Verified by ⌘1, ⌘2, ⌘3 and the toolbar switch.
- [x] 1.2 The view mode is remembered. Verified by stored in the user defaults.
- [x] 1.3 Balance bar chart of an account. Verified by BalanceChartTests "One month shows one bar for the balance at the end of each day" and "Overdrawn days point down from the zero line", and by the debug harness snapshot of the bar chart.
- [x] 1.4 Balances are computed from the transactions. Verified by LedgerTests "Balances leave out pending transactions".
- [ ] 1.5 Initial balance at account setup. Built in part: the migration computes it from the balance of the bank. Finish it and verify it with a test or in the app.
- [x] 1.6 Daily balance or monthly average balance. Verified by the debug harness snapshot in the first build.
- [x] 1.7 The balance chart follows the period. Verified by the debug harness snapshot in the first build.
- [x] 1.8 Long periods are averaged. Verified by BalanceChartTests "Ten years of daily balances share bars with their average"; the chart allows one bar per 4 points of width.
- [x] 1.9 Balance chart of an account group. Verified by the debug harness snapshot in the first build.
- [x] 1.10 No balance chart without transactions. Verified by "No transactions; no bar chart.".
- [x] 1.11 Calibrate the computed balance. Verified by "Calibrate" in the account settings.
- [ ] 1.12 Propose a calibration. Build it and verify it with a test or in the app.
- [x] 1.13 Bar chart of a category. Verified by the debug harness snapshot in the first build.
- [x] 1.14 The category chart follows the period and the account filter. Verified by the chart uses the filtered rows.
- [x] 1.15 Pie charts of deposits and withdrawals. Verified by the debug harness snapshot in the first build.
- [x] 1.16 Categories can be left out of charts. Verified by "Show in diagrams".
- [ ] 1.17 Values on hover. Built: balance and category bars show the date or period and the exact amount under the pointer; a snapshot with a preset pointer shows the label. Pie slices show nothing yet. Finish it and verify it with the pointer in the app.
- [ ] 1.18 A click on a bar selects its period. Built: a click on a balance bar sets its day, days, or month as the period of the list, and a click on a category bar its month, quarter, or year. The chart keeps its period, so the other bars stay; the debug harness command `period bar` shows this. Verify it with a click in the app.
- [x] 1.19 Charts stay current. Verified by charts read the ledger on every change.
- [x] 1.20 Charts follow the appearance. Verified by dark mode, see the debug harness snapshot in the first build.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-charts` when every task is checked.
