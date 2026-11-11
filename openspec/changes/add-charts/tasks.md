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
- [x] 1.8 Long periods scroll. Verified by BalanceChartTests "Ten years of daily balances keep one bar per day" and snapshots of the debug harness: the daily chart of `history` opens at today with July to November visible, and 50,000 transactions of `bulk` stay under the perf budget of scripts/perf-check.sh. Scrolling with the trackpad still needs a check by hand.
- [x] 1.9 Balance chart of an account group. Verified by the debug harness snapshot in the first build. Portfolios count from their first recorded value on: PortfolioHistoryTests "A group shows the giro alone before the first portfolio record, and both with the last record carried forward after it", and the debug harness log `chart ... last=... total=...` of the group "Private" with "Depot", where the last bar equals the total of 53.500,94 €. The caption "Without portfolios" for a portfolio without any record was checked only before the history existed.
- [x] 1.10 No balance chart without transactions. Verified by "No transactions; no bar chart.".
- [x] 1.11 Calibrate the computed balance. Verified by "Calibrate" in the account settings.
- [ ] 1.12 Propose a calibration. Build it and verify it with a test or in the app.
- [x] 1.13 Bar chart of a category. Verified by the debug harness snapshot in the first build.
- [x] 1.14 The category chart follows the period and the account filter. Verified by the chart uses the filtered rows.
- [x] 1.15 Pie charts of deposits and withdrawals. Verified by the debug harness snapshot in the first build.
- [x] 1.16 Categories can be left out of charts. Verified by "Show in diagrams".
- [ ] 1.17 Values on hover. Built: balance and category bars show a light column and the date or period with the exact amount below the bars, see the debug harness command `barsnapshot`; a pie slice stands out and the middle of its ring shows the category, the amount, and the share, see the debug harness command `piesnapshot`. Verify it with the pointer in the app.
- [ ] 1.18 A click on a bar selects its period. Built: a click on a balance bar sets its day, days, or month as the period of the list, and a click on a category bar its month, quarter, or year. The chart keeps its period, so the other bars stay; the debug harness command `period bar` shows this. Verify it with a click in the app.
- [x] 1.19 Charts stay current. Verified by charts read the ledger on every change.
- [x] 1.20 Charts follow the appearance. Verified by dark mode, see the debug harness snapshot in the first build.
- [x] 1.21 Bars as MoneyMoney draws them, measured in its window: balance bars of 4 points with a gap of 2, white on the slate band behind the title, over a dashed line at zero, month and year lines with labels and no amount axis; category bars of 40 points with a gap of 8 in the color of the category, darker below zero, a line at zero for empty periods, and the highest sum, zero, and the lowest sum at the leading edge. Verified by snapshots of the debug harness in light and dark mode and by BalanceChartTests "A category chart has a bar for every period".
- [x] 1.22 Readable text on the band: dark slate text, labels, and a darker red on the light slate, at least 4.5:1 in light, dark, and "Increase contrast". Verified by the computed ratios in Palette and snapshots of the debug harness in light and dark mode.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-charts` when every task is checked.
