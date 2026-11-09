# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 Three view modes. Verified by ⌘1, ⌘2, ⌘3 and the toolbar switch.
- [x] 1.2 The view mode is remembered. Verified by stored in the user defaults.
- [ ] 1.3 Balance bar chart of an account. Built in part: the daily balance is a step line, the monthly average is bars. Finish it and verify it with a test or in the app.
- [x] 1.4 Balances are computed from the transactions. Verified by LedgerTests "Balances leave out pending transactions".
- [ ] 1.5 Initial balance at account setup. Built in part: the migration computes it from the balance of the bank. Finish it and verify it with a test or in the app.
- [x] 1.6 Daily balance or monthly average balance. Verified by the debug harness snapshot in the first build.
- [x] 1.7 The balance chart follows the period. Verified by the debug harness snapshot in the first build.
- [ ] 1.8 Long periods are averaged. Built in part: groups always show monthly averages. Finish it and verify it with a test or in the app.
- [x] 1.9 Balance chart of an account group. Verified by the debug harness snapshot in the first build.
- [x] 1.10 No balance chart without transactions. Verified by "No transactions; no bar chart.".
- [x] 1.11 Calibrate the computed balance. Verified by "Calibrate" in the account settings.
- [ ] 1.12 Propose a calibration. Build it and verify it with a test or in the app.
- [x] 1.13 Bar chart of a category. Verified by the debug harness snapshot in the first build.
- [x] 1.14 The category chart follows the period and the account filter. Verified by the chart uses the filtered rows.
- [x] 1.15 Pie charts of deposits and withdrawals. Verified by the debug harness snapshot in the first build.
- [x] 1.16 Categories can be left out of charts. Verified by "Show in diagrams".
- [ ] 1.17 Values on hover. Build it and verify it with a test or in the app.
- [ ] 1.18 A click on a bar selects its period. Build it and verify it with a test or in the app.
- [x] 1.19 Charts stay current. Verified by charts read the ledger on every change.
- [x] 1.20 Charts follow the appearance. Verified by dark mode, see the debug harness snapshot in the first build.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-charts` when every task is checked.
